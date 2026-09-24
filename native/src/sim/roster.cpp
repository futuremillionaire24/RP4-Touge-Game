#include "roster.h"

#include <cstdlib>
#include <cstring>
#include <initializer_list>

namespace nt {

static const char *KEYS[CAR_COUNT] = {
	"mame_k", "hachi_gt", "kyudo_type_s", "sylph_s2", "rotora_fd", "tatsu_ix",
	"senko", "titan_rz", "raijin_r", "kaido_van", "mugen_proto", "kurogane_hyper",
};

const char *car_key(int id) { return (id >= 0 && id < CAR_COUNT) ? KEYS[id] : "unknown"; }

int car_id_from_key(const std::string &key) {
	for (int i = 0; i < CAR_COUNT; ++i)
		if (key == KEYS[i]) return i;
	return -1;
}

static void curve(VehicleParams &p, std::initializer_list<std::pair<real, real>> pts) {
	p.torque_curve = Curve1D();
	for (auto &pt : pts) p.torque_curve.add(pt.first, pt.second);
}

static void gears(VehicleParams &p, std::initializer_list<real> r, real final_drive) {
	int i = 0;
	for (real v : r) p.gear_ratios[i++] = v;
	p.gear_count = i;
	p.final_drive = final_drive;
}

static void tires(VehicleParams &p, TireCompound c, real wf, real wr) {
	p.tire_front = TireSpec::compound(c);
	p.tire_rear = TireSpec::compound(c);
	p.tire_width_front = wf;
	p.tire_width_rear = wr;
}

// Suspension from natural frequency (Hz) and damping ratio: keeps every car's ride consistent.
static void springs(VehicleParams &p, real freq_f, real freq_r, real zeta_bump, real zeta_rebound) {
	real mf = p.mass * p.weight_front * 0.5;
	real mr = p.mass * (1.0 - p.weight_front) * 0.5;
	p.spring_front = mf * sqr(TAU * freq_f);
	p.spring_rear = mr * sqr(TAU * freq_r);
	real cf = 2.0 * std::sqrt(p.spring_front * mf);
	real cr = 2.0 * std::sqrt(p.spring_rear * mr);
	p.bump_front = cf * zeta_bump;
	p.bump_rear = cr * zeta_bump;
	p.rebound_front = cf * zeta_rebound;
	p.rebound_rear = cr * zeta_rebound;
}

VehicleParams make_car_params(int id) {
	VehicleParams p;
	switch (id) {
		case CAR_MAME_K: // 660cc kei turbo, front-engine RWD roadster
			p.mass = 740; p.cg_height = 0.44; p.wheelbase = 2.06; p.weight_front = 0.51;
			p.track_front = 1.21; p.track_rear = 1.20; p.half_extents = {0.70, 0.60, 1.66};
			p.wheel_radius_front = p.wheel_radius_rear = 0.27;
			tires(p, TIRE_STREET, 0.165, 0.165);
			p.engine_kind = ENGINE_TURBO; p.cylinders = 3;
			curve(p, {{800, 32}, {2000, 48}, {3500, 58}, {5000, 62}, {6500, 58}, {7800, 48}, {8600, 38}});
			p.idle_rpm = 1000; p.redline_rpm = 8200; p.limiter_rpm = 8500;
			p.max_boost = 0.8; p.boost_gain = 0.85; p.spool_rpm = 3600; p.spool_rate = 3.0;
			p.engine_inertia = 0.08;
			gears(p, {3.48, 2.10, 1.43, 1.00, 0.82}, 5.1);
			p.diff_rear = DIFF_OPEN;
			p.brake_torque = 1700; p.handbrake_torque = 1500;
			p.drag_area = 0.56; p.lift_front = 0.0; p.lift_rear = 0.02;
			p.clutch_torque = 240;
			springs(p, 1.55, 1.65, 0.28, 0.45);
			p.arb_front = 9000; p.arb_rear = 5000;
			p.max_steer = 0.64;
			break;

		case CAR_HACHI_GT: // 1.6 NA twin-cam, light FR hatch
			p.mass = 950; p.cg_height = 0.48; p.wheelbase = 2.40; p.weight_front = 0.54;
			p.track_front = 1.36; p.track_rear = 1.35; p.half_extents = {0.83, 0.67, 2.10};
			p.wheel_radius_front = p.wheel_radius_rear = 0.29;
			tires(p, TIRE_STREET, 0.185, 0.185);
			curve(p, {{800, 95}, {2000, 118}, {3500, 132}, {4800, 144}, {5800, 149}, {6600, 139}, {7400, 118}, {7800, 104}});
			p.idle_rpm = 850; p.redline_rpm = 7400; p.limiter_rpm = 7700;
			p.engine_inertia = 0.12;
			gears(p, {3.587, 2.022, 1.384, 1.000, 0.861}, 4.3);
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.35; p.lsd_decel = 0.15; p.lsd_preload = 60;
			p.brake_torque = 2100; p.handbrake_torque = 2000;
			p.drag_area = 0.64; p.lift_front = -0.04; p.lift_rear = -0.02;
			p.clutch_torque = 330;
			springs(p, 1.60, 1.75, 0.30, 0.48);
			p.arb_front = 14000; p.arb_rear = 6000;
			p.max_steer = 0.62;
			break;

		case CAR_KYUDO_TYPE_S: // 1.8 high-rev VTEC-style FF
			p.mass = 1100; p.cg_height = 0.47; p.wheelbase = 2.62; p.weight_front = 0.62;
			p.track_front = 1.48; p.track_rear = 1.47; p.half_extents = {0.85, 0.68, 2.20};
			p.wheel_radius_front = p.wheel_radius_rear = 0.30;
			tires(p, TIRE_SPORT, 0.195, 0.195);
			p.layout = DRIVE_FF; p.diff_front = DIFF_LSD; p.lsd_accel = 0.40; p.lsd_decel = 0.10;
			curve(p, {{900, 110}, {2500, 140}, {4500, 152}, {5600, 158}, {6000, 170}, {7400, 182}, {8400, 170}, {9000, 148}});
			p.idle_rpm = 950; p.redline_rpm = 8800; p.limiter_rpm = 9000;
			p.engine_inertia = 0.10;
			gears(p, {3.23, 2.105, 1.458, 1.107, 0.848}, 4.4);
			p.brake_torque = 2500; p.brake_bias = 0.68;
			p.drag_area = 0.62; p.lift_front = 0.02; p.lift_rear = 0.04;
			p.clutch_torque = 360;
			springs(p, 1.85, 2.05, 0.30, 0.50);
			p.arb_front = 15000; p.arb_rear = 22000; // rear bar rotates the FF on lift
			p.max_steer = 0.60;
			break;

		case CAR_SYLPH_S2: // 2.0 turbo FR coupe, drift benchmark
			p.mass = 1240; p.cg_height = 0.48; p.wheelbase = 2.525; p.weight_front = 0.55;
			p.track_front = 1.48; p.track_rear = 1.47; p.half_extents = {0.87, 0.65, 2.23};
			p.wheel_radius_front = p.wheel_radius_rear = 0.31;
			tires(p, TIRE_SPORT, 0.215, 0.225);
			p.engine_kind = ENGINE_TURBO;
			curve(p, {{800, 120}, {2000, 160}, {3200, 190}, {4800, 205}, {6400, 190}, {7200, 165}, {7600, 150}});
			p.idle_rpm = 850; p.redline_rpm = 7200; p.limiter_rpm = 7500;
			p.max_boost = 0.9; p.boost_gain = 0.48; p.spool_rpm = 3600; p.spool_rate = 2.6;
			p.engine_inertia = 0.15;
			gears(p, {3.321, 1.902, 1.308, 1.000, 0.759, 0.63}, 4.08);
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.55; p.lsd_decel = 0.35; p.lsd_preload = 110;
			p.brake_torque = 2700; p.handbrake_torque = 2500;
			p.drag_area = 0.63; p.lift_front = 0.02; p.lift_rear = 0.05;
			p.clutch_torque = 480;
			springs(p, 1.75, 1.85, 0.30, 0.50);
			p.arb_front = 20000; p.arb_rear = 10000;
			p.max_steer = 0.70;
			break;

		case CAR_ROTORA_FD: // twin-rotor sequential turbo FR
			p.mass = 1280; p.cg_height = 0.45; p.wheelbase = 2.425; p.weight_front = 0.50;
			p.track_front = 1.46; p.track_rear = 1.46; p.half_extents = {0.88, 0.62, 2.15};
			p.wheel_radius_front = p.wheel_radius_rear = 0.315;
			tires(p, TIRE_SPORT, 0.225, 0.255);
			p.engine_kind = ENGINE_ROTARY; p.cylinders = 2;
			curve(p, {{900, 110}, {2500, 150}, {4000, 185}, {5000, 196}, {6500, 188}, {7600, 160}, {8200, 140}});
			p.idle_rpm = 900; p.redline_rpm = 8000; p.limiter_rpm = 8300;
			p.max_boost = 0.85; p.boost_gain = 0.55; p.spool_rpm = 3200; p.spool_rate = 3.2;
			p.engine_inertia = 0.11;
			gears(p, {3.483, 2.015, 1.391, 1.000, 0.719}, 4.1);
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.25;
			p.brake_torque = 2900;
			p.drag_area = 0.58; p.lift_front = 0.06; p.lift_rear = 0.10;
			p.clutch_torque = 500;
			springs(p, 1.85, 1.95, 0.30, 0.52);
			p.arb_front = 21000; p.arb_rear = 12000;
			p.max_steer = 0.64;
			break;

		case CAR_TATSU_IX: // 2.0 turbo AWD rally sedan
			p.mass = 1400; p.cg_height = 0.52; p.wheelbase = 2.625; p.weight_front = 0.59;
			p.track_front = 1.52; p.track_rear = 1.52; p.half_extents = {0.89, 0.72, 2.24};
			p.wheel_radius_front = p.wheel_radius_rear = 0.32;
			tires(p, TIRE_SPORT, 0.235, 0.235);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.50; p.center_lock = 0.45;
			p.diff_front = DIFF_LSD; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45;
			p.engine_kind = ENGINE_TURBO;
			curve(p, {{800, 140}, {2000, 200}, {3000, 245}, {4500, 250}, {6500, 215}, {7200, 185}, {7600, 165}});
			p.idle_rpm = 850; p.redline_rpm = 7000; p.limiter_rpm = 7300;
			p.max_boost = 1.2; p.boost_gain = 0.52; p.spool_rpm = 3000; p.spool_rate = 2.8;
			p.engine_inertia = 0.15;
			gears(p, {2.785, 1.950, 1.407, 1.031, 0.720}, 4.53);
			p.brake_torque = 3300;
			p.drag_area = 0.68; p.lift_front = 0.08; p.lift_rear = 0.14;
			p.clutch_torque = 600;
			springs(p, 1.75, 1.80, 0.32, 0.50);
			p.arb_front = 20000; p.arb_rear = 16000;
			p.max_steer = 0.60;
			break;

		case CAR_SENKO: // 3.0 NA V6 mid-engine
			p.mass = 1370; p.cg_height = 0.44; p.wheelbase = 2.53; p.weight_front = 0.42;
			p.track_front = 1.51; p.track_rear = 1.53; p.half_extents = {0.90, 0.59, 2.21};
			p.wheel_radius_front = 0.30; p.wheel_radius_rear = 0.32;
			tires(p, TIRE_SPORT, 0.215, 0.255);
			p.layout = DRIVE_MR; p.cylinders = 6;
			curve(p, {{900, 190}, {2500, 245}, {4000, 270}, {5400, 294}, {6500, 285}, {7300, 270}, {8000, 235}});
			p.idle_rpm = 900; p.redline_rpm = 8000; p.limiter_rpm = 8300;
			p.engine_inertia = 0.14;
			gears(p, {3.066, 1.956, 1.428, 1.125, 0.914, 0.717}, 4.235);
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.40; p.lsd_decel = 0.20;
			p.brake_torque = 3300; p.brake_bias = 0.58;
			p.drag_area = 0.56; p.lift_front = 0.08; p.lift_rear = 0.12;
			p.clutch_torque = 520;
			springs(p, 1.95, 2.10, 0.32, 0.55);
			p.arb_front = 22000; p.arb_rear = 14000;
			p.max_steer = 0.58;
			break;

		case CAR_TITAN_RZ: // 3.0 twin-turbo I6 GT
			p.mass = 1510; p.cg_height = 0.48; p.wheelbase = 2.55; p.weight_front = 0.53;
			p.track_front = 1.52; p.track_rear = 1.53; p.half_extents = {0.91, 0.64, 2.26};
			p.wheel_radius_front = 0.32; p.wheel_radius_rear = 0.33;
			tires(p, TIRE_SPORT, 0.235, 0.265);
			p.engine_kind = ENGINE_TURBO; p.cylinders = 6;
			curve(p, {{800, 190}, {2000, 250}, {3000, 285}, {4000, 300}, {5600, 290}, {6800, 250}, {7200, 225}});
			p.idle_rpm = 750; p.redline_rpm = 6800; p.limiter_rpm = 7100;
			p.max_boost = 1.0; p.boost_gain = 0.5; p.spool_rpm = 3600; p.spool_rate = 2.2;
			p.engine_inertia = 0.20;
			gears(p, {3.827, 2.360, 1.685, 1.312, 1.000, 0.793}, 3.27);
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.25;
			p.brake_torque = 3700;
			p.drag_area = 0.66; p.lift_front = 0.04; p.lift_rear = 0.10;
			p.clutch_torque = 700;
			springs(p, 1.70, 1.85, 0.30, 0.50);
			p.arb_front = 24000; p.arb_rear = 13000;
			p.max_steer = 0.60;
			break;

		case CAR_RAIJIN_R: // 2.6 twin-turbo I6, rear-biased AWD
			p.mass = 1560; p.cg_height = 0.49; p.wheelbase = 2.665; p.weight_front = 0.56;
			p.track_front = 1.48; p.track_rear = 1.48; p.half_extents = {0.89, 0.68, 2.30};
			p.wheel_radius_front = p.wheel_radius_rear = 0.33;
			tires(p, TIRE_SPORT, 0.245, 0.245);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.30; p.center_lock = 0.55;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.50; p.lsd_decel = 0.30;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 6;
			curve(p, {{800, 180}, {2200, 240}, {3500, 280}, {4400, 295}, {6000, 280}, {7200, 245}, {7700, 215}});
			p.idle_rpm = 900; p.redline_rpm = 7700; p.limiter_rpm = 8000;
			p.max_boost = 1.05; p.boost_gain = 0.55; p.spool_rpm = 3600; p.spool_rate = 2.4;
			p.engine_inertia = 0.18;
			gears(p, {3.827, 2.360, 1.685, 1.312, 1.000, 0.793}, 3.545);
			p.brake_torque = 3900;
			p.drag_area = 0.70; p.lift_front = 0.10; p.lift_rear = 0.16;
			p.clutch_torque = 720;
			springs(p, 1.85, 1.95, 0.32, 0.52);
			p.arb_front = 26000; p.arb_rear = 15000;
			p.max_steer = 0.58;
			break;

		case CAR_KAIDO_VAN: // 3.0 turbo-diesel box van
			p.mass = 1900; p.cg_height = 0.78; p.wheelbase = 2.57; p.weight_front = 0.52;
			p.track_front = 1.66; p.track_rear = 1.64; p.half_extents = {0.94, 0.98, 2.40};
			p.wheel_radius_front = p.wheel_radius_rear = 0.34;
			tires(p, TIRE_STREET, 0.215, 0.215);
			p.engine_kind = ENGINE_DIESEL; p.cylinders = 4;
			curve(p, {{700, 210}, {1400, 300}, {1600, 330}, {2800, 330}, {3400, 290}, {4000, 230}, {4400, 190}});
			p.idle_rpm = 700; p.redline_rpm = 4000; p.limiter_rpm = 4300;
			p.max_boost = 1.1; p.boost_gain = 0.3; p.spool_rpm = 1800; p.spool_rate = 2.0;
			p.engine_inertia = 0.30; p.engine_brake = 0.030;
			gears(p, {4.313, 2.330, 1.436, 1.000, 0.838}, 4.1);
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.40; p.lsd_decel = 0.20;
			p.brake_torque = 4600; p.handbrake_torque = 3200;
			p.drag_area = 1.05; p.lift_front = -0.08; p.lift_rear = -0.06;
			p.clutch_torque = 600;
			springs(p, 1.45, 1.55, 0.30, 0.45);
			p.arb_front = 18000; p.arb_rear = 8000;
			p.max_steer = 0.66;
			break;

		case CAR_MUGEN_PROTO: // featherweight MR track car with real aero
			p.mass = 800; p.cg_height = 0.38; p.wheelbase = 2.37; p.weight_front = 0.40;
			p.track_front = 1.50; p.track_rear = 1.48; p.half_extents = {0.88, 0.55, 1.95};
			p.wheel_radius_front = 0.29; p.wheel_radius_rear = 0.30;
			tires(p, TIRE_SEMI_SLICK, 0.225, 0.255);
			p.layout = DRIVE_MR;
			curve(p, {{1000, 150}, {3000, 190}, {5000, 225}, {7000, 250}, {8400, 240}, {9000, 220}, {9400, 200}});
			p.idle_rpm = 1100; p.redline_rpm = 9000; p.limiter_rpm = 9300;
			p.engine_inertia = 0.08;
			gears(p, {3.10, 2.20, 1.68, 1.35, 1.12, 0.95}, 4.1);
			p.shift_time = 0.07;
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.30;
			p.brake_torque = 2900; p.brake_bias = 0.56;
			p.drag_area = 0.72; p.lift_front = 0.55; p.lift_rear = 0.85;
			p.clutch_torque = 420;
			springs(p, 2.60, 2.80, 0.35, 0.60);
			p.rest_length_front = p.rest_length_rear = 0.28; p.travel_front = p.travel_rear = 0.12;
			p.arb_front = 26000; p.arb_rear = 18000;
			p.max_steer = 0.56;
			break;

		case CAR_KUROGANE_HYPER: // twin-turbo V8 hybrid AWD hypercar
			p.mass = 1650; p.cg_height = 0.42; p.wheelbase = 2.78; p.weight_front = 0.45;
			p.track_front = 1.66; p.track_rear = 1.62; p.half_extents = {0.99, 0.58, 2.38};
			p.wheel_radius_front = 0.34; p.wheel_radius_rear = 0.35;
			tires(p, TIRE_SEMI_SLICK, 0.265, 0.325);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.35; p.center_lock = 0.5;
			p.diff_front = DIFF_LSD; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.25;
			p.engine_kind = ENGINE_HYBRID; p.cylinders = 8;
			curve(p, {{900, 340}, {2500, 420}, {4000, 470}, {5500, 480}, {7000, 450}, {8200, 400}, {8600, 370}});
			p.idle_rpm = 950; p.redline_rpm = 8300; p.limiter_rpm = 8600;
			p.max_boost = 1.2; p.boost_gain = 0.55; p.spool_rpm = 3400; p.spool_rate = 3.2;
			p.hybrid_boost_nm = 260;
			p.engine_inertia = 0.17;
			gears(p, {3.13, 2.24, 1.73, 1.39, 1.13, 0.93, 0.76}, 3.6);
			p.shift_time = 0.05;
			p.brake_torque = 5600; p.brake_bias = 0.60;
			p.drag_area = 0.78; p.lift_front = 0.55; p.lift_rear = 0.85;
			p.clutch_torque = 1400;
			springs(p, 2.30, 2.50, 0.34, 0.56);
			p.arb_front = 30000; p.arb_rear = 22000;
			p.max_steer = 0.56;
			p.top_speed_limiter = 97.0;
			break;
	}
	return p;
}

EngineAudioProfile make_car_audio(int id) {
	EngineAudioProfile a;
	switch (id) {
		case CAR_MAME_K: a.cylinders = 3; a.exhaust_resonance = 260; a.roughness = 0.25; a.growl = 0.3; a.turbo_whistle = 0.5; a.uneven = 0.3; break;
		case CAR_HACHI_GT: a.cylinders = 4; a.exhaust_resonance = 210; a.roughness = 0.18; a.growl = 0.45; break;
		case CAR_KYUDO_TYPE_S: a.cylinders = 4; a.vtec = true; a.crossover_rpm = 5800; a.exhaust_resonance = 240; a.roughness = 0.12; a.growl = 0.35; break;
		case CAR_SYLPH_S2: a.cylinders = 4; a.exhaust_resonance = 180; a.roughness = 0.2; a.growl = 0.55; a.turbo_whistle = 0.7; break;
		case CAR_ROTORA_FD: a.cylinders = 2; a.rotors = 2; a.exhaust_resonance = 300; a.roughness = 0.3; a.growl = 0.4; a.turbo_whistle = 0.6; break;
		case CAR_TATSU_IX: a.cylinders = 4; a.exhaust_resonance = 170; a.roughness = 0.28; a.growl = 0.6; a.turbo_whistle = 0.9; break;
		case CAR_SENKO: a.cylinders = 6; a.exhaust_resonance = 220; a.roughness = 0.1; a.growl = 0.5; a.uneven = 0.15; break;
		case CAR_TITAN_RZ: a.cylinders = 6; a.exhaust_resonance = 150; a.roughness = 0.1; a.growl = 0.65; a.turbo_whistle = 0.8; break;
		case CAR_RAIJIN_R: a.cylinders = 6; a.exhaust_resonance = 160; a.roughness = 0.12; a.growl = 0.6; a.turbo_whistle = 0.85; break;
		case CAR_KAIDO_VAN: a.cylinders = 4; a.diesel = true; a.exhaust_resonance = 110; a.roughness = 0.45; a.growl = 0.8; a.turbo_whistle = 0.6; break;
		case CAR_MUGEN_PROTO: a.cylinders = 4; a.exhaust_resonance = 280; a.roughness = 0.1; a.growl = 0.4; a.straight_cut = true; break;
		case CAR_KUROGANE_HYPER: a.cylinders = 8; a.hybrid = true; a.exhaust_resonance = 140; a.roughness = 0.14; a.growl = 0.75; a.turbo_whistle = 0.5; a.uneven = 0.35; a.straight_cut = true; break;
		default: break;
	}
	return a;
}

#define NT_REAL_FIELDS(X) \
	X(mass) X(cg_height) X(weight_front) X(inertia_scale) \
	X(tire_width_front) X(tire_width_rear) X(camber_front) X(camber_rear) \
	X(toe_front) X(toe_rear) X(tire_pressure_front) X(tire_pressure_rear) \
	X(rest_length_front) X(rest_length_rear) X(travel_front) X(travel_rear) \
	X(spring_front) X(spring_rear) X(bump_front) X(bump_rear) \
	X(rebound_front) X(rebound_rear) X(arb_front) X(arb_rear) \
	X(max_steer) X(ackermann) X(caster_trail) \
	X(idle_rpm) X(redline_rpm) X(limiter_rpm) X(engine_inertia) \
	X(engine_brake) X(max_boost) X(boost_gain) X(spool_rpm) X(spool_rate) \
	X(hybrid_boost_nm) X(reverse_ratio) X(final_drive) X(shift_time) \
	X(clutch_torque) X(drivetrain_efficiency) X(lsd_accel) X(lsd_decel) \
	X(lsd_preload) X(awd_front_split) X(center_lock) X(brake_torque) \
	X(brake_bias) X(handbrake_torque) X(drag_area) X(lift_front) \
	X(lift_rear) X(top_speed_limiter) X(wheel_inertia) X(mount_height)

static real *real_field(VehicleParams &p, const std::string &k) {
#define NT_FIELD(name) if (k == #name) return &p.name;
	NT_REAL_FIELDS(NT_FIELD)
#undef NT_FIELD
	return nullptr;
}

std::vector<std::pair<std::string, real>> dump_params(const VehicleParams &p) {
	std::vector<std::pair<std::string, real>> out;
#define NT_DUMP(name) out.emplace_back(#name, p.name);
	NT_REAL_FIELDS(NT_DUMP)
#undef NT_DUMP
	out.emplace_back("wheel_radius_front", p.wheel_radius_front);
	out.emplace_back("wheel_radius_rear", p.wheel_radius_rear);
	out.emplace_back("gear_count", (real)p.gear_count);
	for (int g = 0; g < p.gear_count; ++g) out.emplace_back("gear_" + std::to_string(g + 1), p.gear_ratios[g]);
	out.emplace_back("layout", (real)p.layout);
	out.emplace_back("diff_front", (real)p.diff_front);
	out.emplace_back("diff_rear", (real)p.diff_rear);
	out.emplace_back("engine_kind", (real)p.engine_kind);
	out.emplace_back("cylinders", (real)p.cylinders);
	return out;
}

bool apply_override(VehicleParams &p, const std::string &key, real v) {
	// "*name" multiplies and "+name" adds to the current value, so upgrades stack on swaps.
	char op = '=';
	std::string k = key;
	if (!k.empty() && (k[0] == '*' || k[0] == '+')) {
		op = k[0];
		k = k.substr(1);
	}
	if (real *f = real_field(p, k)) {
		if (op == '*') *f *= v;
		else if (op == '+') *f += v;
		else *f = v;
		return true;
	}
	if (op != '=') return false;
	if (k == "torque_scale") {
		for (int i = 0; i < p.torque_curve.n; ++i) p.torque_curve.ys[i] *= v;
		return true;
	}
	if (k == "torque_top_end") { // cams/ECU: shift torque toward high rpm
		for (int i = 0; i < p.torque_curve.n; ++i) {
			real t = p.torque_curve.xs[i] / p.redline_rpm;
			p.torque_curve.ys[i] *= 1.0 + v * (t - 0.5);
		}
		return true;
	}
	if (k.rfind("gear_", 0) == 0) {
		int g = std::atoi(k.c_str() + 5);
		if (g >= 1 && g <= 8) {
			p.gear_ratios[g - 1] = v;
			return true;
		}
		return false;
	}
	if (k == "gear_count") { p.gear_count = (int)clampr(v, 4, 8); return true; }
	if (k == "tire_compound") {
		TireCompound c = (TireCompound)(int)clampr(v, 0, TIRE_COUNT - 1);
		p.tire_front = TireSpec::compound(c);
		p.tire_rear = TireSpec::compound(c);
		return true;
	}
	if (k == "layout") { p.layout = (DriveLayout)(int)clampr(v, 0, 4); return true; }
	if (k == "diff_front") { p.diff_front = (DiffType)(int)clampr(v, 0, 2); return true; }
	if (k == "diff_rear") { p.diff_rear = (DiffType)(int)clampr(v, 0, 2); return true; }
	if (k == "engine_kind") { p.engine_kind = (EngineKind)(int)clampr(v, 0, 4); return true; }
	if (k == "cylinders") { p.cylinders = (int)v; return true; }
	if (k == "wheel_radius") { p.wheel_radius_front = p.wheel_radius_rear = v; return true; }
	if (k == "engine_swap") {
		// Transplant another car's engine: torque curve, rev range, induction, inertia, cylinders.
		int src = (int)v;
		if (src < 0 || src >= CAR_COUNT) return false;
		VehicleParams donor = make_car_params(src);
		// Heavier engines add weight up front.
		real delta_mass = (donor.cylinders - p.cylinders) * 18.0;
		p.mass += std::max(delta_mass, -40.0);
		p.torque_curve = donor.torque_curve;
		p.idle_rpm = donor.idle_rpm;
		p.redline_rpm = donor.redline_rpm;
		p.limiter_rpm = donor.limiter_rpm;
		p.engine_inertia = donor.engine_inertia;
		p.engine_brake = donor.engine_brake;
		p.engine_kind = donor.engine_kind;
		p.max_boost = donor.max_boost;
		p.boost_gain = donor.boost_gain;
		p.spool_rpm = donor.spool_rpm;
		p.spool_rate = donor.spool_rate;
		p.cylinders = donor.cylinders;
		p.hybrid_boost_nm = donor.hybrid_boost_nm;
		p.clutch_torque = std::max(p.clutch_torque, donor.clutch_torque);
		return true;
	}
	return false;
}

} // namespace nt
