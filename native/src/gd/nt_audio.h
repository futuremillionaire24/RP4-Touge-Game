// NTEngineAudio: an AudioStream whose playback runs the procedural engine synth on Godot's
// audio thread. GDScript pushes car state each frame via set_state().
#pragma once

#include "sim/engine_audio.h"

#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <memory>
#include <vector>

namespace godot {

class NTEngineAudioPlayback : public AudioStreamPlayback {
	GDCLASS(NTEngineAudioPlayback, AudioStreamPlayback);

public:
	std::shared_ptr<nt::EngineSynth> synth;
	bool active = false;
	std::vector<float> scratch;

	void _start(double p_from_pos) override { active = true; }
	void _stop() override { active = false; }
	bool _is_playing() const override { return active; }
	int32_t _get_loop_count() const override { return 0; }
	double _get_playback_position() const override { return 0.0; }
	void _seek(double p_position) override {}
	int32_t _mix(AudioFrame *p_buffer, float p_rate_scale, int32_t p_frames) override;

protected:
	static void _bind_methods() {}
};

class NTEngineAudio : public AudioStream {
	GDCLASS(NTEngineAudio, AudioStream);

public:
	NTEngineAudio();
	Ref<AudioStreamPlayback> _instantiate_playback() const override;
	String _get_stream_name() const override { return "NTEngineAudio"; }
	double _get_length() const override { return 0.0; }
	bool _is_monophonic() const override { return true; }

	void configure(const String &car_key, bool detailed);
	void set_state(const Dictionary &state);
	void set_volume(double v);

protected:
	static void _bind_methods();

private:
	std::shared_ptr<nt::EngineSynth> synth_;
	float max_boost_ = 0.0f;
};

} // namespace godot
