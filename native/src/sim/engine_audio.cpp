#include "engine_audio.h"

#include <algorithm>

namespace nt {

void EngineSynth::configure(const EngineAudioProfile &p, float idle_rpm, float redline_rpm, float max_boost, float sample_rate, bool detailed) {
	prof_ = p;
	fs_ = sample_rate;
	idle_ = idle_rpm;
	redline_ = redline_rpm;
	max_boost_ = max_boost;
	detailed_ = detailed;
	noise_ = Noise((uint32_t)(p.cylinders * 7919 + p.exhaust_resonance * 13 + (detailed ? 1 : 3)));
	// Fixed per-cylinder character: slight imbalance makes it sound mechanical, not synthetic.
	for (int i = 0; i < 16; ++i) cyl_gain_[i] = 1.0f - prof_.roughness * 0.35f * noise_.uni();
	s_rpm_.set_time(fs_, 0.012f);
	s_thr_.set_time(fs_, 0.02f);
	s_load_.set_time(fs_, 0.03f);
	s_boost_.set_time(fs_, 0.05f);
	s_speed_.set_time(fs_, 0.05f);
	s_slip_.set_time(fs_, 0.04f);
	s_loose_.set_time(fs_, 0.05f);
	s_rough_.set_time(fs_, 0.05f);
	s_vol_.set_time(fs_, 0.05f);
	s_rpm_.v = idle_;
	dc_block_.highpass(fs_, 25.0f);
	update_filters(idle_, 0.0f);
}

void EngineSynth::update_filters(float rpm, float load) {
	float r = std::clamp(rpm / redline_, 0.0f, 1.3f);
	// VTEC-style cam changeover: resonance and brightness jump above the crossover.
	if (prof_.vtec) vtec_blend_ += ((rpm > prof_.crossover_rpm ? 1.0f : 0.0f) - vtec_blend_) * 0.2f;
	float base = prof_.exhaust_resonance * (0.85f + 0.55f * r) * (1.0f + 0.25f * vtec_blend_);
	float q = 1.4f + prof_.growl * 1.6f;
	exhaust_[0].bandpass(fs_, base, q);
	exhaust_[1].bandpass(fs_, base * 2.35f, q * 1.3f);
	exhaust_[2].bandpass(fs_, base * 4.1f + (prof_.rotors ? 900.0f : 0.0f), q * 1.8f);
	intake_bp_.bandpass(fs_, 900.0f + 2600.0f * r, 1.2f);
	float bright = 1800.0f + 5200.0f * r * (0.4f + 0.6f * load) + vtec_blend_ * 1500.0f;
	if (in.interior.load(std::memory_order_relaxed)) bright *= 0.45f;
	body_lp_.lowpass(fs_, bright, 0.8f);
	float boost = s_boost_.v;
	whistle_bp_.bandpass(fs_, 2200.0f + boost * 6000.0f, 14.0f);
	float speed = s_speed_.v;
	road_lp_.lowpass(fs_, 180.0f + speed * 9.0f, 0.9f);
	wind_bp_.bandpass(fs_, 600.0f + speed * 22.0f, 0.55f);
	float sq = 620.0f + in.slip_pitch.load(std::memory_order_relaxed) * 520.0f;
	squeal_bp_[0].bandpass(fs_, sq, 9.0f);
	squeal_bp_[1].bandpass(fs_, sq * 2.07f, 7.0f);
	gravel_bp_.bandpass(fs_, 2400.0f, 1.3f);
	pop_lp_.lowpass(fs_, 650.0f, 1.2f);
}

void EngineSynth::render(float *out, int frames) {
	s_rpm_.target = std::max(in.rpm.load(std::memory_order_relaxed), 200.0f);
	s_thr_.target = in.throttle.load(std::memory_order_relaxed);
	s_load_.target = in.load.load(std::memory_order_relaxed);
	s_boost_.target = in.boost.load(std::memory_order_relaxed);
	s_speed_.target = in.speed.load(std::memory_order_relaxed);
	s_slip_.target = in.slip.load(std::memory_order_relaxed);
	s_loose_.target = in.loose.load(std::memory_order_relaxed);
	s_rough_.target = in.roughness.load(std::memory_order_relaxed);
	s_vol_.target = in.volume.load(std::memory_order_relaxed);
	const bool limiter = in.limiter.load(std::memory_order_relaxed);
	const float wet = in.wet.load(std::memory_order_relaxed);
	const float gear_ratio = in.gear_ratio.load(std::memory_order_relaxed);
	const bool interior = in.interior.load(std::memory_order_relaxed);
	const float dt = 1.0f / fs_;
	const int cyl = std::max(1, prof_.cylinders);
	const int harmonics = detailed_ ? 8 : 4;
	const float growl = prof_.growl;

	for (int n = 0; n < frames; ++n) {
		float rpm = s_rpm_.tick();
		float thr = s_thr_.tick();
		float load = s_load_.tick();
		float boost = s_boost_.tick();
		float speed = s_speed_.tick();
		float slip = s_slip_.tick();
		float loose = s_loose_.tick();
		float rough = s_rough_.tick();
		float vol = s_vol_.tick();
		if ((filter_counter_++ & 63) == 0) update_filters(rpm, load);

		float crank_hz = rpm / 60.0f;
		float fire_hz = prof_.rotors > 0 ? crank_hz * (float)prof_.rotors : crank_hz * (float)cyl * 0.5f;
		// Uneven firing (V engines / boxers / triples): alternate interval lengths.
		float interval_mod = 1.0f + prof_.uneven * 0.3f * ((cyl_index_ & 1) ? 1.0f : -1.0f);
		fire_phase_ += fire_hz * dt / interval_mod;
		if (fire_phase_ >= 1.0f) {
			fire_phase_ -= 1.0f;
			cyl_index_ = (cyl_index_ + 1) % std::min(cyl, 16);
			float strength = 0.35f + 0.65f * std::max(thr, load);
			if (limiter) strength *= 0.06f; // fuel cut
			if (thr < 0.02f && rpm > idle_ * 1.3f) strength *= 0.4f; // overrun
			pulse_amp_ = cyl_gain_[cyl_index_] * strength * (1.0f + prof_.roughness * 0.4f * noise_.next());
			pulse_env_ = 1.0f;
		}
		float period = 1.0f / std::max(fire_hz, 1.0f);
		float decay = std::exp(-dt / (period * (prof_.diesel ? 0.18f : 0.32f)));
		pulse_env_ *= decay;
		float nz = noise_.next();
		float excite = pulse_amp_ * pulse_env_ * (0.85f + 0.15f * nz);
		if (prof_.diesel) excite += pulse_amp_ * pulse_env_ * pulse_env_ * nz * 0.9f; // clatter
		if (prof_.rotors > 0) excite += pulse_amp_ * pulse_env_ * nz * 0.45f; // rotary rasp

		float res = exhaust_[0].process(excite) * 1.0f + exhaust_[1].process(excite) * 0.55f + exhaust_[2].process(excite) * (0.25f + 0.2f * vtec_blend_);

		// Order harmonics for body and pitch clarity.
		float harm = 0.0f;
		float base_hz = fire_hz * 0.5f;
		for (int h = 0; h < harmonics; ++h) {
			float order = (float)(h + 1);
			harm_phase_[h] = wrap_pi(harm_phase_[h] + F_TAU * base_hz * order * dt);
			float weight = (h == 1 ? 1.0f : 0.5f / order) * (h < 2 ? (0.6f + growl * 0.8f) : (0.3f + load * 0.7f));
			harm += fast_sin(harm_phase_[h]) * weight;
		}

		float intake = intake_bp_.process(nz) * (0.2f + 0.8f * thr) * (rpm / redline_) * (0.4f + pulse_env_);
		float level = (0.4f + 0.6f * (load * 0.6f + thr * 0.4f)) * (0.45f + 0.55f * std::min(rpm / redline_, 1.1f));
		float eng = (res * 2.2f + harm * 0.16f + intake * (interior ? 0.6f : 0.2f)) * level;
		float drive = 1.2f + growl * 2.2f + load * 1.2f;
		eng = tanh_clip(body_lp_.process(eng) * drive) * 0.55f;

		// Turbo: spool whistle + blow-off / flutter on lift.
		float turbo = 0.0f;
		if (max_boost_ > 0.0f) {
			whistle_phase_ = wrap_pi(whistle_phase_ + F_TAU * (2200.0f + boost * 6000.0f) * dt);
			turbo += fast_sin(whistle_phase_) * boost * boost * prof_.turbo_whistle * 0.05f;
			turbo += whistle_bp_.process(nz) * boost * prof_.turbo_whistle * 0.12f;
			if (prev_thr_ > 0.55f && thr < 0.25f && boost > 0.3f && bov_env_ < 0.05f) {
				bov_env_ = 1.0f;
				bov_sweep_ = 0.0f;
				boost_at_lift_ = boost;
			}
			prev_thr_ = thr;
			if (bov_env_ > 0.001f) {
				bov_sweep_ += dt;
				if ((filter_counter_ & 63) == 1) bov_bp_.bandpass(fs_, 4200.0f - 2800.0f * std::min(bov_sweep_ / 0.35f, 1.0f), 2.2f);
				float flutter = prof_.turbo_whistle > 0.75f ? (0.55f + 0.45f * fast_sin(wrap_pi(F_TAU * 21.0f * bov_sweep_))) : 1.0f;
				turbo += bov_bp_.process(nz) * bov_env_ * flutter * boost_at_lift_ * 0.55f;
				bov_env_ *= std::exp(-dt / 0.16f);
			}
		}

		// Overrun pops / crackle.
		if (thr < 0.05f && rpm > redline_ * 0.5f && !prof_.diesel) {
			pop_timer_ -= dt;
			if (pop_timer_ <= 0.0f) {
				pop_timer_ = 0.04f + noise_.uni() * (0.35f - 0.25f * (rpm / redline_));
				pop_env_ = 0.4f + 0.6f * noise_.uni();
			}
		}
		float pop = 0.0f;
		if (pop_env_ > 0.001f) {
			pop = pop_lp_.process(nz * 3.0f) * pop_env_;
			pop_env_ *= std::exp(-dt / 0.018f);
		}

		// Drivetrain whine + hybrid motor.
		float whine = 0.0f;
		if (gear_ratio > 0.0f && speed > 0.5f) {
			float shaft_hz = speed / 0.32f / F_TAU * gear_ratio;
			whine_phase_ = wrap_pi(whine_phase_ + F_TAU * shaft_hz * 26.0f * dt);
			whine = fast_sin(whine_phase_) * (prof_.straight_cut ? 0.028f : 0.005f) * std::min(speed / 30.0f, 1.0f) * (0.4f + load);
		}
		if (prof_.hybrid) {
			motor_phase_ = wrap_pi(motor_phase_ + F_TAU * (speed * 52.0f + 90.0f) * dt);
			whine += fast_sin(motor_phase_) * 0.02f * (0.3f + thr) * std::max(0.0f, 1.0f - speed / 45.0f);
		}

		// Tires, road, wind, gravel.
		float grip_squeal = slip * slip * (1.0f - loose) * (1.0f - 0.6f * wet);
		squeal_phase_ += dt;
		float wobble = 1.0f + 0.15f * fast_sin(wrap_pi(F_TAU * 5.3f * squeal_phase_));
		float squeal = (squeal_bp_[0].process(nz) * 1.0f + squeal_bp_[1].process(nz) * 0.45f) * grip_squeal * 0.9f * wobble;
		float road = road_lp_.process(nz) * std::min(speed / 50.0f, 1.2f) * (0.25f + rough * 0.9f + wet * 0.5f) * 0.35f;
		float sp = std::min(speed / 70.0f, 1.3f);
		float wind = wind_bp_.process(nz) * sp * sp * 0.22f;
		gravel_timer_ -= dt * (loose * speed * 2.5f + 0.001f);
		if (gravel_timer_ <= 0.0f && loose > 0.05f && speed > 1.0f) {
			gravel_timer_ = 0.02f + 0.03f * noise_.uni();
			gravel_env_ = 0.5f + 0.5f * noise_.uni();
		}
		float gravel = gravel_bp_.process(nz) * gravel_env_ * loose * 0.5f;
		gravel_env_ *= std::exp(-dt / 0.008f);
		if (interior) {
			wind *= 0.4f;
			road *= 1.4f;
		}

		float mix = (eng + turbo + pop * 0.8f + whine) * (interior ? 0.7f : 1.0f) + squeal + road + wind + gravel;
		mix = dc_block_.process(mix);
		out[n] = soft_clip(mix * 1.4f) * vol;
	}
}

} // namespace nt
