// Procedural engine + drivetrain + tire/wind audio. Parameters are written by the game thread
// (atomics) and read by the audio mixing thread.
#pragma once

#include "audio_dsp.h"
#include "roster.h"

#include <atomic>

namespace nt {

struct EngineAudioInput {
	std::atomic<float> rpm{900.0f};
	std::atomic<float> throttle{0.0f};
	std::atomic<float> load{0.0f}; // 0..1 engine torque output / peak
	std::atomic<float> boost{0.0f}; // 0..1 of max boost
	std::atomic<float> speed{0.0f}; // m/s
	std::atomic<float> gear_ratio{0.0f}; // total ratio (gear * final), 0 in neutral
	std::atomic<float> slip{0.0f}; // 0..1 tire squeal amount
	std::atomic<float> slip_pitch{0.0f}; // 0..1 (drift angle / slide speed)
	std::atomic<float> loose{0.0f}; // 0..1 gravel/dirt contact
	std::atomic<float> roughness{0.0f}; // 0..1 road roughness (cobbles, curbs)
	std::atomic<float> wet{0.0f};
	std::atomic<float> volume{1.0f};
	std::atomic<bool> limiter{false};
	std::atomic<bool> shifting{false};
	std::atomic<bool> interior{false}; // cockpit camera: muffle exhaust, add intake
};

class EngineSynth {
public:
	EngineAudioInput in;

	void configure(const EngineAudioProfile &p, float idle_rpm, float redline_rpm, float max_boost, float sample_rate, bool detailed);
	// Renders mono samples (engine + drivetrain + tires + wind), returns peak.
	void render(float *out, int frames);
	float sample_rate() const { return fs_; }

private:
	void update_filters(float rpm, float load);

	EngineAudioProfile prof_;
	float fs_ = 48000.0f;
	float idle_ = 900.0f, redline_ = 7500.0f, max_boost_ = 0.0f;
	bool detailed_ = true;

	// Crank phase in firing events (fractional).
	float fire_phase_ = 0.0f;
	int cyl_index_ = 0;
	float pulse_env_ = 0.0f;
	float pulse_amp_ = 0.0f;
	float cyl_gain_[16] = {};
	float harm_phase_[10] = {};

	Biquad exhaust_[3];
	Biquad intake_bp_;
	Biquad body_lp_;
	Biquad dc_block_;
	Biquad whistle_bp_;
	Biquad bov_bp_;
	Biquad pop_lp_;
	Biquad squeal_bp_[2];
	Biquad road_lp_, wind_bp_, gravel_bp_;
	Smooth s_rpm_, s_thr_, s_load_, s_boost_, s_speed_, s_slip_, s_loose_, s_rough_, s_vol_;
	Noise noise_;
	float whistle_phase_ = 0.0f, whine_phase_ = 0.0f, motor_phase_ = 0.0f, squeal_phase_ = 0.0f;
	float bov_env_ = 0.0f, bov_sweep_ = 0.0f;
	float pop_env_ = 0.0f, pop_timer_ = 0.0f;
	float prev_thr_ = 0.0f;
	float boost_at_lift_ = 0.0f;
	float gravel_env_ = 0.0f, gravel_timer_ = 0.0f;
	int filter_counter_ = 0;
	float vtec_blend_ = 0.0f;
};

} // namespace nt
