// Stock physics definitions for the 12 cars. Display data (names, prices, lore) lives in
// godot/scripts/data/cars.gd; upgrades and tuning are applied on top via apply_override().
#pragma once

#include "vehicle.h"

#include <string>
#include <utility>
#include <vector>

namespace nt {

enum CarId {
	CAR_MAME_K = 0,
	CAR_HACHI_GT,
	CAR_KYUDO_TYPE_S,
	CAR_SYLPH_S2,
	CAR_ROTORA_FD,
	CAR_TATSU_IX,
	CAR_SENKO,
	CAR_TITAN_RZ,
	CAR_RAIJIN_R,
	CAR_KAIDO_VAN,
	CAR_MUGEN_PROTO,
	CAR_KUROGANE_HYPER,
	CAR_COUNT
};

struct EngineAudioProfile {
	int cylinders = 4;
	int rotors = 0; // >0 = rotary
	bool vtec = false;
	real crossover_rpm = 0.0;
	bool straight_cut = false;
	real exhaust_resonance = 180.0; // Hz
	real roughness = 0.2; // combustion jitter
	real growl = 0.5; // low-order emphasis
	real turbo_whistle = 0.0;
	bool diesel = false;
	bool hybrid = false;
	real uneven = 0.0; // half-order content (V engines / boxers)
};

VehicleParams make_car_params(int car_id);
EngineAudioProfile make_car_audio(int car_id);
const char *car_key(int car_id);
int car_id_from_key(const std::string &key);

// Named numeric overrides from upgrades/tuning ("spring_front" = 52000, "tire_rear" = 3 ...).
// Returns false if the key is unknown.
// key "name" sets, "*name" multiplies, "+name" adds (real fields only for * and +).
bool apply_override(VehicleParams &p, const std::string &key, real value);
// Every overridable value (for garage/tuning screens).
std::vector<std::pair<std::string, real>> dump_params(const VehicleParams &p);

} // namespace nt
