#include "nt_audio.h"

#include "sim/roster.h"

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

int32_t NTEngineAudioPlayback::_mix(AudioFrame *p_buffer, float p_rate_scale, int32_t p_frames) {
	if (!active || !synth) {
		for (int i = 0; i < p_frames; ++i) p_buffer[i] = AudioFrame{0.0f, 0.0f};
		return p_frames;
	}
	if ((int)scratch.size() < p_frames) scratch.resize(p_frames);
	synth->render(scratch.data(), p_frames);
	for (int i = 0; i < p_frames; ++i) {
		float s = scratch[i];
		p_buffer[i] = AudioFrame{s, s};
	}
	return p_frames;
}

NTEngineAudio::NTEngineAudio() : synth_(std::make_shared<nt::EngineSynth>()) {}

Ref<AudioStreamPlayback> NTEngineAudio::_instantiate_playback() const {
	Ref<NTEngineAudioPlayback> pb;
	pb.instantiate();
	pb->synth = synth_;
	return pb;
}

void NTEngineAudio::configure(const String &car_key, bool detailed) {
	int id = nt::car_id_from_key(car_key.utf8().get_data());
	if (id < 0) id = 0;
	nt::VehicleParams p = nt::make_car_params(id);
	float fs = (float)AudioServer::get_singleton()->get_mix_rate();
	max_boost_ = (float)p.max_boost;
	synth_->configure(nt::make_car_audio(id), (float)p.idle_rpm, (float)p.redline_rpm, (float)p.max_boost, fs, detailed);
}

// Keys: rpm, throttle, load, boost, speed, gear_ratio, slip, slip_pitch, loose, roughness, wet,
// limiter, shifting, interior. Missing keys keep their previous value.
void NTEngineAudio::set_state(const Dictionary &d) {
	nt::EngineAudioInput &in = synth_->in;
	const auto rel = std::memory_order_relaxed;
	if (d.has("rpm")) in.rpm.store((float)(double)d["rpm"], rel);
	if (d.has("throttle")) in.throttle.store((float)(double)d["throttle"], rel);
	if (d.has("load")) in.load.store((float)(double)d["load"], rel);
	if (d.has("boost")) in.boost.store(max_boost_ > 0.0f ? (float)(double)d["boost"] / max_boost_ : 0.0f, rel);
	if (d.has("speed")) in.speed.store((float)(double)d["speed"], rel);
	if (d.has("gear_ratio")) in.gear_ratio.store((float)(double)d["gear_ratio"], rel);
	if (d.has("slip")) in.slip.store((float)(double)d["slip"], rel);
	if (d.has("slip_pitch")) in.slip_pitch.store((float)(double)d["slip_pitch"], rel);
	if (d.has("loose")) in.loose.store((float)(double)d["loose"], rel);
	if (d.has("roughness")) in.roughness.store((float)(double)d["roughness"], rel);
	if (d.has("wet")) in.wet.store((float)(double)d["wet"], rel);
	if (d.has("limiter")) in.limiter.store((bool)d["limiter"], rel);
	if (d.has("shifting")) in.shifting.store((bool)d["shifting"], rel);
	if (d.has("interior")) in.interior.store((bool)d["interior"], rel);
}

void NTEngineAudio::set_volume(double v) { synth_->in.volume.store((float)v, std::memory_order_relaxed); }

void NTEngineAudio::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "car_key", "detailed"), &NTEngineAudio::configure);
	ClassDB::bind_method(D_METHOD("set_state", "state"), &NTEngineAudio::set_state);
	ClassDB::bind_method(D_METHOD("set_volume", "volume"), &NTEngineAudio::set_volume);
}
