#include "roster.h"

#include <cstdlib>
#include <cstring>
#include <initializer_list>

namespace nt {

static const char *KEYS[CAR_COUNT] = {
	"abarth_500", "golf_gti", "bmw_m3_e30", "porsche_930", "jaguar_etype", "mb_300sl", "defender_90",
	"audi_quattro", "jaguar_ftype", "mb_g63", "bmw_m4", "audi_r8", "porsche_992", "ferrari_testarossa",
	"ferrari_f40", "lambo_svj", "jaguar_xj220", "porsche_918", "ferrari_laferrari",
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

// Geometry from the baked model (wheelbase, tracks, radii) + real body size and weight split.
static void geo(VehicleParams &p, real mass, real wf, real cg, real wb, real tf, real tr, real rf, real rr, real W, real H, real L) {
	p.mass = mass;
	p.weight_front = wf;
	p.cg_height = cg;
	p.wheelbase = wb;
	p.track_front = tf;
	p.track_rear = tr;
	p.wheel_radius_front = rf;
	p.wheel_radius_rear = rr;
	p.half_extents = {W * 0.5, H * 0.5, L * 0.5};
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

// Masses include a 75 kg driver and a half tank. Torque curves are crank torque without boost;
// boosted peak = curve * (1 + max_boost * boost_gain).
VehicleParams make_car_params(int id) {
	VehicleParams p;
	switch (id) {
		case CAR_ABARTH_500: // 2008 Fiat Abarth 500, 1.4 T-Jet 135 PS / 206 Nm, FF
			geo(p, 1110, 0.63, 0.50, 2.2985, 1.392, 1.392, 0.297, 0.297, 1.627, 1.485, 3.657);
			tires(p, TIRE_SPORT, 0.195, 0.195);
			p.layout = DRIVE_FF; p.diff_front = DIFF_OPEN;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 4;
			curve(p, {{800, 95}, {1800, 125}, {2750, 138}, {4000, 136}, {5500, 116}, {6250, 100}, {6600, 88}});
			p.max_boost = 1.0; p.boost_gain = 0.5; p.spool_rpm = 2400; p.spool_rate = 4.0;
			p.idle_rpm = 850; p.redline_rpm = 6400; p.limiter_rpm = 6600;
			p.engine_inertia = 0.11;
			gears(p, {3.909, 2.238, 1.520, 1.156, 0.872}, 3.353);
			p.brake_torque = 3700; p.brake_bias = 0.70; p.handbrake_torque = 1500;
			p.drag_area = 0.70; p.lift_front = -0.02; p.lift_rear = 0.0;
			p.clutch_torque = 320;
			springs(p, 1.75, 1.95, 0.30, 0.50);
			p.arb_front = 16000; p.arb_rear = 14000;
			p.max_steer = 0.62;
			break;

		case CAR_GOLF_GTI: // 2005 Volkswagen Golf GTI (Mk5), 2.0 TFSI 200 PS / 280 Nm, FF
			geo(p, 1410, 0.61, 0.53, 2.5738, 1.520, 1.520, 0.313, 0.313, 1.759, 1.466, 4.216);
			tires(p, TIRE_SPORT, 0.225, 0.225);
			p.layout = DRIVE_FF; p.diff_front = DIFF_OPEN;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 4;
			curve(p, {{800, 120}, {1800, 187}, {3000, 187}, {5000, 185}, {5700, 172}, {6300, 150}, {6700, 128}});
			p.max_boost = 1.0; p.boost_gain = 0.5; p.spool_rpm = 1900; p.spool_rate = 4.5;
			p.idle_rpm = 750; p.redline_rpm = 6500; p.limiter_rpm = 6700;
			p.engine_inertia = 0.13;
			gears(p, {3.36, 2.09, 1.47, 1.10, 0.87, 0.73}, 3.65);
			p.brake_torque = 5200; p.brake_bias = 0.68; p.handbrake_torque = 1800;
			p.drag_area = 0.71; p.lift_front = 0.0; p.lift_rear = 0.02;
			p.clutch_torque = 420;
			springs(p, 1.65, 1.85, 0.30, 0.50);
			p.arb_front = 17000; p.arb_rear = 19000; // stiff rear bar: lift-off rotation
			p.max_steer = 0.60;
			break;

		case CAR_BMW_M3_E30: // 1986 BMW M3 (E30), S14 2.3 195 PS / 240 Nm, FR
			geo(p, 1275, 0.51, 0.47, 2.5816, 1.389, 1.414, 0.311, 0.311, 1.680, 1.370, 4.346);
			tires(p, TIRE_STREET, 0.205, 0.205);
			curve(p, {{800, 150}, {2000, 195}, {3500, 222}, {4750, 240}, {6000, 232}, {6750, 212}, {7300, 185}, {7500, 168}});
			p.idle_rpm = 900; p.redline_rpm = 7250; p.limiter_rpm = 7500;
			p.engine_inertia = 0.12;
			gears(p, {3.72, 2.40, 1.77, 1.26, 1.00}, 3.25); // Getrag 265 dog-leg
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.25; p.lsd_decel = 0.25; p.lsd_preload = 60;
			p.brake_torque = 4700; p.brake_bias = 0.66; p.handbrake_torque = 2200;
			p.drag_area = 0.61; p.lift_front = 0.02; p.lift_rear = 0.02;
			p.clutch_torque = 380;
			springs(p, 1.70, 1.85, 0.30, 0.50);
			p.arb_front = 18000; p.arb_rear = 9000;
			p.max_steer = 0.64;
			break;

		case CAR_PORSCHE_930: // 1975 Porsche 911 Turbo (930), 3.0 flat-6 turbo 260 PS / 343 Nm, RR
			geo(p, 1215, 0.38, 0.46, 2.2717, 1.514, 1.552, 0.321, 0.314, 1.775, 1.310, 4.291);
			tires(p, TIRE_STREET, 0.205, 0.225);
			p.layout = DRIVE_RR;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 6;
			curve(p, {{900, 150}, {2500, 205}, {4000, 238}, {5000, 232}, {5500, 222}, {6200, 196}, {6800, 170}});
			p.max_boost = 0.8; p.boost_gain = 0.55; p.spool_rpm = 4200; p.spool_rate = 1.4; // old-school lag
			p.idle_rpm = 950; p.redline_rpm = 6800; p.limiter_rpm = 7000;
			p.engine_inertia = 0.15;
			gears(p, {2.25, 1.30, 0.89, 0.66}, 4.0);
			p.shift_time = 0.22;
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.40; p.lsd_decel = 0.40;
			p.brake_torque = 5600; p.brake_bias = 0.58; p.handbrake_torque = 2200;
			p.drag_area = 0.70; p.lift_front = 0.06; p.lift_rear = 0.02;
			p.clutch_torque = 520;
			springs(p, 1.75, 1.95, 0.30, 0.50);
			p.arb_front = 16000; p.arb_rear = 8000;
			p.max_steer = 0.60;
			break;

		case CAR_JAGUAR_ETYPE: // 1963 Jaguar E-Type Lightweight, 3.8 I6 ~330 PS / 380 Nm, FR
			geo(p, 1040, 0.49, 0.44, 2.5502, 1.456, 1.456, 0.313, 0.313, 1.657, 1.220, 4.453);
			tires(p, TIRE_STREET, 0.185, 0.185);
			p.tire_front.grip = p.tire_rear.grip = 0.96; // period Dunlop racing crossplies
			p.cylinders = 6;
			curve(p, {{800, 220}, {2000, 300}, {3500, 360}, {4500, 380}, {5500, 365}, {6200, 335}, {6700, 300}});
			p.idle_rpm = 800; p.redline_rpm = 6500; p.limiter_rpm = 6700;
			p.engine_inertia = 0.16;
			gears(p, {2.68, 1.74, 1.27, 1.00}, 3.31);
			p.shift_time = 0.2;
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.35; p.lsd_decel = 0.20;
			p.brake_torque = 3600; p.brake_bias = 0.62;
			p.drag_area = 0.58; p.lift_front = -0.06; p.lift_rear = -0.04;
			p.clutch_torque = 520;
			springs(p, 1.60, 1.70, 0.28, 0.48);
			p.arb_front = 14000; p.arb_rear = 5000;
			p.max_steer = 0.60;
			break;

		case CAR_MB_300SL: // 1955 Mercedes-Benz 300 SL (W198), 3.0 I6 215 PS / 274 Nm, FR
			geo(p, 1370, 0.52, 0.49, 2.4209, 1.395, 1.395, 0.341, 0.341, 1.790, 1.300, 4.520);
			tires(p, TIRE_STREET, 0.175, 0.175);
			p.tire_front.grip = p.tire_rear.grip = 0.92; // 1950s cross-plies
			p.cylinders = 6;
			curve(p, {{700, 170}, {2000, 225}, {3500, 258}, {4600, 274}, {5500, 262}, {6000, 240}, {6400, 212}});
			p.idle_rpm = 750; p.redline_rpm = 6200; p.limiter_rpm = 6400;
			p.engine_inertia = 0.18;
			gears(p, {3.34, 2.27, 1.44, 1.00}, 3.64);
			p.shift_time = 0.25;
			p.diff_rear = DIFF_OPEN;
			p.brake_torque = 4000; p.brake_bias = 0.62;
			p.drag_area = 0.70; p.lift_front = -0.04; p.lift_rear = -0.05;
			p.clutch_torque = 420;
			springs(p, 1.35, 1.45, 0.26, 0.44);
			p.arb_front = 12000; p.arb_rear = 2000; // swing-axle rear: no rear bar
			p.camber_rear = -0.01;
			p.max_steer = 0.58;
			break;

		case CAR_DEFENDER_90: // Land Rover Defender 90 Td5, 2.5 I5 turbo-diesel 122 PS / 300 Nm, permanent 4x4
			geo(p, 1990, 0.52, 0.82, 2.4888, 1.484, 1.484, 0.399, 0.399, 1.790, 1.990, 3.883);
			tires(p, TIRE_RALLY, 0.235, 0.235); // all-terrains
			p.layout = DRIVE_AWD; p.awd_front_split = 0.50; p.center_lock = 0.60;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_OPEN;
			p.engine_kind = ENGINE_DIESEL; p.cylinders = 5;
			curve(p, {{700, 130}, {1400, 185}, {1950, 200}, {3000, 190}, {3600, 160}, {4200, 120}});
			p.max_boost = 1.0; p.boost_gain = 0.5; p.spool_rpm = 1700; p.spool_rate = 2.2;
			p.idle_rpm = 750; p.redline_rpm = 4000; p.limiter_rpm = 4200;
			p.engine_inertia = 0.32; p.engine_brake = 0.03;
			gears(p, {3.69, 2.13, 1.40, 1.00, 0.77}, 4.29); // incl. transfer-box high range
			p.brake_torque = 8600; p.brake_bias = 0.62; p.handbrake_torque = 2800;
			p.drag_area = 1.55; p.lift_front = -0.10; p.lift_rear = -0.08;
			p.clutch_torque = 560;
			p.rest_length_front = p.rest_length_rear = 0.42; p.travel_front = p.travel_rear = 0.28;
			springs(p, 1.25, 1.35, 0.28, 0.45);
			p.arb_front = 9000; p.arb_rear = 4000;
			p.max_steer = 0.66;
			break;

		case CAR_AUDI_QUATTRO: // 1983 Audi quattro, 2.1 I5 turbo 200 PS / 285 Nm, permanent quattro
			geo(p, 1365, 0.58, 0.50, 2.5136, 1.380, 1.380, 0.315, 0.315, 1.723, 1.344, 4.404);
			tires(p, TIRE_SPORT, 0.205, 0.205);
			p.tire_front.loose_bonus = p.tire_rear.loose_bonus = 0.15;
			p.layout = DRIVE_AWD; p.awd_front_split = 0.50; p.center_lock = 0.35;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.35;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 5;
			curve(p, {{800, 140}, {2200, 175}, {3500, 190}, {4500, 186}, {5500, 172}, {6200, 150}, {6600, 132}});
			p.max_boost = 0.85; p.boost_gain = 0.6; p.spool_rpm = 3400; p.spool_rate = 2.0;
			p.idle_rpm = 850; p.redline_rpm = 6500; p.limiter_rpm = 6800;
			p.engine_inertia = 0.15;
			gears(p, {3.60, 2.13, 1.36, 0.97, 0.75}, 3.89);
			p.brake_torque = 4900; p.brake_bias = 0.64; p.handbrake_torque = 2600;
			p.drag_area = 0.72; p.lift_front = 0.02; p.lift_rear = 0.04;
			p.clutch_torque = 480;
			springs(p, 1.70, 1.85, 0.30, 0.50);
			p.arb_front = 16000; p.arb_rear = 12000;
			p.max_steer = 0.62;
			break;

		case CAR_JAGUAR_FTYPE: // 2017 Jaguar F-Type R Coupe AWD, 5.0 supercharged V8 550 PS / 680 Nm
			geo(p, 1825, 0.51, 0.47, 2.63, 1.562, 1.626, 0.358, 0.358, 1.923, 1.311, 4.470);
			tires(p, TIRE_SPORT, 0.255, 0.295);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.25; p.center_lock = 0.45;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.55; p.lsd_decel = 0.30;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 8; // twin-screw supercharger: boost from idle
			curve(p, {{700, 330}, {1500, 420}, {2500, 470}, {3500, 486}, {5000, 470}, {6000, 440}, {6500, 405}, {6800, 370}});
			p.max_boost = 0.8; p.boost_gain = 0.5; p.spool_rpm = 1200; p.spool_rate = 9.0;
			p.idle_rpm = 700; p.redline_rpm = 6500; p.limiter_rpm = 6800;
			p.engine_inertia = 0.22;
			gears(p, {4.71, 3.14, 2.11, 1.67, 1.29, 1.00, 0.84, 0.67}, 3.15); // ZF 8HP
			p.shift_time = 0.12;
			p.brake_torque = 8000; p.brake_bias = 0.62; p.handbrake_torque = 2400;
			p.drag_area = 0.76; p.lift_front = 0.04; p.lift_rear = 0.10;
			p.clutch_torque = 1100;
			springs(p, 1.95, 2.10, 0.32, 0.54);
			p.arb_front = 26000; p.arb_rear = 16000;
			p.max_steer = 0.58;
			break;

		case CAR_MB_G63: // 2019 Mercedes-AMG G 63, 4.0 V8 biturbo 585 PS / 850 Nm, 4MATIC 40:60
			geo(p, 2620, 0.52, 0.80, 2.8766, 1.601, 1.601, 0.348, 0.348, 1.984, 1.966, 4.873);
			tires(p, TIRE_SPORT, 0.275, 0.275);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.40; p.center_lock = 0.55;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.40;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 8;
			curve(p, {{700, 330}, {1500, 470}, {2500, 567}, {3500, 567}, {5000, 535}, {6000, 478}, {6500, 430}, {6900, 380}});
			p.max_boost = 1.0; p.boost_gain = 0.5; p.spool_rpm = 2200; p.spool_rate = 4.0;
			p.idle_rpm = 650; p.redline_rpm = 6500; p.limiter_rpm = 6900;
			p.engine_inertia = 0.24;
			gears(p, {5.35, 3.24, 2.25, 1.64, 1.21, 1.00, 0.87, 0.72, 0.60}, 3.27); // 9G-Tronic
			p.shift_time = 0.12;
			p.top_speed_limiter = 61.1; // 220 km/h governed
			p.brake_torque = 11000; p.brake_bias = 0.64; p.handbrake_torque = 3000;
			p.drag_area = 1.65; p.lift_front = -0.08; p.lift_rear = -0.06;
			p.clutch_torque = 1300;
			p.rest_length_front = p.rest_length_rear = 0.40; p.travel_front = p.travel_rear = 0.24;
			springs(p, 1.45, 1.55, 0.32, 0.52);
			p.arb_front = 30000; p.arb_rear = 20000;
			p.max_steer = 0.60;
			break;

		case CAR_BMW_M4: // 2015 BMW M4 (F82), S55 3.0 I6 twin-turbo 431 PS / 550 Nm, FR, Active M Diff
			geo(p, 1612, 0.52, 0.48, 2.793, 1.502, 1.502, 0.297, 0.297, 1.870, 1.383, 4.671);
			tires(p, TIRE_SPORT, 0.255, 0.275);
			p.engine_kind = ENGINE_TURBO; p.cylinders = 6;
			curve(p, {{800, 250}, {1850, 367}, {3500, 367}, {5500, 365}, {6250, 340}, {7000, 300}, {7400, 270}});
			p.max_boost = 1.0; p.boost_gain = 0.5; p.spool_rpm = 2100; p.spool_rate = 4.5;
			p.idle_rpm = 750; p.redline_rpm = 7300; p.limiter_rpm = 7600;
			p.engine_inertia = 0.16;
			gears(p, {4.806, 2.593, 1.701, 1.277, 1.000, 0.844, 0.671}, 3.462); // M DCT
			p.shift_time = 0.07;
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.55; p.lsd_decel = 0.35; p.lsd_preload = 100;
			p.top_speed_limiter = 69.4; // 250 km/h
			p.brake_torque = 6200; p.brake_bias = 0.62; p.handbrake_torque = 2600;
			p.drag_area = 0.68; p.lift_front = 0.04; p.lift_rear = 0.08;
			p.clutch_torque = 900;
			springs(p, 2.00, 2.20, 0.32, 0.54);
			p.arb_front = 26000; p.arb_rear = 14000;
			p.max_steer = 0.58;
			break;

		case CAR_AUDI_R8: // 2019 Audi R8 V10 performance, 5.2 V10 620 PS / 580 Nm, quattro, mid-engine
			geo(p, 1670, 0.42, 0.44, 2.5671, 1.714, 1.797, 0.351, 0.358, 1.940, 1.240, 4.426);
			tires(p, TIRE_SPORT, 0.245, 0.305);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.30; p.center_lock = 0.45;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.25;
			p.cylinders = 10;
			curve(p, {{1000, 330}, {2500, 420}, {4000, 490}, {5500, 545}, {6600, 580}, {8000, 555}, {8500, 520}, {8800, 480}});
			p.idle_rpm = 1000; p.redline_rpm = 8500; p.limiter_rpm = 8800;
			p.engine_inertia = 0.13;
			gears(p, {3.13, 2.19, 1.63, 1.29, 1.03, 0.84, 0.66}, 4.89); // S tronic 7
			p.shift_time = 0.06;
			p.brake_torque = 7200; p.brake_bias = 0.58; p.handbrake_torque = 2600;
			p.drag_area = 0.72; p.lift_front = 0.20; p.lift_rear = 0.35;
			p.clutch_torque = 1000;
			springs(p, 2.25, 2.45, 0.34, 0.56);
			p.arb_front = 28000; p.arb_rear = 18000;
			p.max_steer = 0.56;
			break;

		case CAR_PORSCHE_992: // 2020 Porsche 911 Turbo S (992), 3.7 flat-6 twin-turbo 650 PS / 800 Nm, AWD, rear-engine
			geo(p, 1715, 0.39, 0.45, 2.4429, 1.552, 1.564, 0.335, 0.352, 1.900, 1.303, 4.535);
			tires(p, TIRE_SPORT, 0.255, 0.315);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.20; p.center_lock = 0.40;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.50; p.lsd_decel = 0.30;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 6;
			curve(p, {{800, 330}, {2000, 480}, {2500, 533}, {4500, 533}, {6000, 500}, {6750, 470}, {7200, 420}});
			p.max_boost = 1.0; p.boost_gain = 0.5; p.spool_rpm = 2200; p.spool_rate = 5.0;
			p.idle_rpm = 800; p.redline_rpm = 7000; p.limiter_rpm = 7200;
			p.engine_inertia = 0.15;
			gears(p, {4.89, 3.17, 2.15, 1.56, 1.18, 0.94, 0.76, 0.61}, 3.26); // PDK 8
			p.shift_time = 0.05;
			p.brake_torque = 7800; p.brake_bias = 0.60; p.handbrake_torque = 2600;
			p.drag_area = 0.72; p.lift_front = 0.18; p.lift_rear = 0.30;
			p.clutch_torque = 1400;
			springs(p, 2.20, 2.40, 0.34, 0.56);
			p.arb_front = 28000; p.arb_rear = 18000;
			p.max_steer = 0.58;
			break;

		case CAR_FERRARI_TESTAROSSA: // 1985 Ferrari Testarossa, 4.9 flat-12 390 PS / 490 Nm, mid-engine RWD
			geo(p, 1580, 0.40, 0.46, 2.5154, 1.571, 1.645, 0.297, 0.297, 1.976, 1.130, 4.485);
			tires(p, TIRE_SPORT, 0.225, 0.255);
			p.layout = DRIVE_MR; p.cylinders = 12;
			curve(p, {{900, 300}, {2500, 400}, {4500, 490}, {5500, 478}, {6300, 455}, {6800, 420}, {7100, 385}});
			p.idle_rpm = 900; p.redline_rpm = 6800; p.limiter_rpm = 7100;
			p.engine_inertia = 0.20;
			gears(p, {3.139, 2.014, 1.526, 1.167, 0.875}, 3.21);
			p.shift_time = 0.18;
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.40; p.lsd_decel = 0.25;
			p.brake_torque = 5700; p.brake_bias = 0.60;
			p.drag_area = 0.68; p.lift_front = 0.02; p.lift_rear = 0.04;
			p.clutch_torque = 800;
			springs(p, 1.85, 2.00, 0.30, 0.50);
			p.arb_front = 20000; p.arb_rear = 14000;
			p.max_steer = 0.58;
			break;

		case CAR_FERRARI_F40: // 1987 Ferrari F40, 2.9 V8 twin-turbo 478 PS / 577 Nm, mid-engine RWD, no assists era
			geo(p, 1330, 0.42, 0.42, 2.4274, 1.551, 1.548, 0.322, 0.322, 1.970, 1.124, 4.358);
			tires(p, TIRE_SPORT, 0.245, 0.335);
			p.layout = DRIVE_MR;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 8;
			curve(p, {{1000, 230}, {2500, 300}, {4000, 360}, {5500, 352}, {7000, 302}, {7750, 262}, {8000, 240}});
			p.max_boost = 1.1; p.boost_gain = 0.55; p.spool_rpm = 4000; p.spool_rate = 1.8; // famous lag, then a kick
			p.idle_rpm = 1000; p.redline_rpm = 7750; p.limiter_rpm = 8000;
			p.engine_inertia = 0.12;
			gears(p, {2.769, 1.722, 1.217, 0.964, 0.806}, 3.45);
			p.shift_time = 0.16;
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.50; p.lsd_decel = 0.35;
			p.brake_torque = 5600; p.brake_bias = 0.58;
			p.drag_area = 0.60; // Cd 0.34 x ~1.8 m2 p.lift_front = 0.12; p.lift_rear = 0.30;
			p.clutch_torque = 900;
			springs(p, 2.30, 2.50, 0.34, 0.56);
			p.arb_front = 26000; p.arb_rear = 18000;
			p.max_steer = 0.56;
			break;

		case CAR_LAMBO_SVJ: // 2019 Lamborghini Aventador SVJ, 6.5 V12 770 PS / 720 Nm, AWD, mid-engine, ALA aero
			geo(p, 1750, 0.43, 0.42, 2.7205, 1.697, 1.703, 0.350, 0.365, 2.098, 1.136, 4.943);
			tires(p, TIRE_SEMI_SLICK, 0.255, 0.355);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.30; p.center_lock = 0.40;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.25;
			p.cylinders = 12;
			curve(p, {{1000, 360}, {2500, 480}, {4500, 600}, {6750, 720}, {8000, 700}, {8500, 670}, {8900, 620}});
			p.idle_rpm = 1000; p.redline_rpm = 8700; p.limiter_rpm = 8900;
			p.engine_inertia = 0.16;
			gears(p, {3.91, 2.44, 1.81, 1.46, 1.19, 0.97, 0.84}, 2.86); // ISR 7
			p.shift_time = 0.05;
			p.brake_torque = 7400; p.brake_bias = 0.58;
			p.drag_area = 0.86; p.lift_front = 0.50; p.lift_rear = 0.85;
			p.clutch_torque = 1500;
			springs(p, 2.45, 2.65, 0.35, 0.58);
			p.arb_front = 32000; p.arb_rear = 22000;
			p.max_steer = 0.55;
			break;

		case CAR_JAGUAR_XJ220: // 1992 Jaguar XJ220, 3.5 V6 twin-turbo 550 PS / 644 Nm, mid-engine RWD
			geo(p, 1545, 0.42, 0.44, 2.6531, 1.854, 1.704, 0.335, 0.338, 2.220, 1.150, 4.930);
			tires(p, TIRE_SPORT, 0.255, 0.345);
			p.layout = DRIVE_MR;
			p.engine_kind = ENGINE_TURBO; p.cylinders = 6;
			curve(p, {{1000, 260}, {2500, 330}, {4000, 405}, {4500, 415}, {6000, 400}, {7000, 370}, {7400, 330}});
			p.max_boost = 1.0; p.boost_gain = 0.55; p.spool_rpm = 3600; p.spool_rate = 2.2;
			p.idle_rpm = 900; p.redline_rpm = 7200; p.limiter_rpm = 7400;
			p.engine_inertia = 0.14;
			gears(p, {2.90, 1.94, 1.45, 1.13, 0.88}, 2.90);
			p.shift_time = 0.15;
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.30;
			p.brake_torque = 6200; p.brake_bias = 0.58;
			p.drag_area = 0.68; p.lift_front = 0.15; p.lift_rear = 0.30;
			p.clutch_torque = 1000;
			springs(p, 2.20, 2.40, 0.34, 0.56);
			p.arb_front = 26000; p.arb_rear = 18000;
			p.max_steer = 0.55;
			break;

		case CAR_PORSCHE_918: // 2015 Porsche 918 Spyder, 4.6 V8 608 PS + e-motors (887 PS / 1280 Nm), AWD hybrid
			geo(p, 1750, 0.43, 0.40, 2.7142, 1.847, 1.847, 0.304, 0.304, 1.940, 1.167, 4.643);
			tires(p, TIRE_SEMI_SLICK, 0.265, 0.325);
			p.layout = DRIVE_AWD; p.awd_front_split = 0.30; p.center_lock = 0.40;
			p.diff_front = DIFF_OPEN; p.diff_rear = DIFF_LSD; p.lsd_accel = 0.45; p.lsd_decel = 0.25;
			p.engine_kind = ENGINE_HYBRID; p.cylinders = 8;
			curve(p, {{1000, 330}, {3000, 440}, {5000, 500}, {6700, 528}, {8500, 505}, {9000, 470}, {9300, 430}});
			p.hybrid_boost_nm = 380; p.hybrid_power_kw = 205; // front + rear e-motors: 887 PS system
			p.top_speed_limiter = 345.0 / 3.6; // factory Vmax
			p.idle_rpm = 1000; p.redline_rpm = 9000; p.limiter_rpm = 9300;
			p.engine_inertia = 0.11;
			gears(p, {3.91, 2.35, 1.69, 1.31, 1.08, 0.90, 0.72}, 3.30); // PDK 7
			p.shift_time = 0.05;
			p.brake_torque = 7400; p.brake_bias = 0.58;
			p.drag_area = 0.74; p.lift_front = 0.40; p.lift_rear = 0.70;
			p.clutch_torque = 1600;
			springs(p, 2.40, 2.60, 0.35, 0.58);
			p.arb_front = 30000; p.arb_rear = 22000;
			p.max_steer = 0.55;
			break;

		case CAR_FERRARI_LAFERRARI: // 2014 Ferrari LaFerrari, 6.3 V12 800 PS + HY-KERS (963 PS / 900+ Nm), RWD hybrid
			geo(p, 1660, 0.41, 0.40, 2.6365, 1.659, 1.645, 0.328, 0.345, 1.992, 1.116, 4.702);
			tires(p, TIRE_SEMI_SLICK, 0.265, 0.345);
			p.layout = DRIVE_MR;
			p.engine_kind = ENGINE_HYBRID; p.cylinders = 12;
			curve(p, {{1000, 380}, {3000, 520}, {5000, 610}, {6750, 700}, {8500, 670}, {9000, 630}, {9400, 580}});
			p.hybrid_boost_nm = 270; p.hybrid_power_kw = 120; // HY-KERS 163 PS: 963 PS system
			p.top_speed_limiter = 350.0 / 3.6; // factory Vmax (electronically limited)
			p.diff_rear = DIFF_LSD; p.lsd_accel = 0.50; p.lsd_decel = 0.30;
			p.idle_rpm = 1000; p.redline_rpm = 9250; p.limiter_rpm = 9400;
			p.engine_inertia = 0.13;
			gears(p, {3.08, 2.19, 1.63, 1.29, 1.03, 0.84, 0.69}, 4.44); // Getrag 7DCT
			p.shift_time = 0.04;
			p.brake_torque = 7600; p.brake_bias = 0.58;
			p.drag_area = 0.74; p.lift_front = 0.45; p.lift_rear = 0.75;
			p.clutch_torque = 1600;
			springs(p, 2.40, 2.60, 0.35, 0.58);
			p.arb_front = 30000; p.arb_rear = 22000;
			p.max_steer = 0.55;
			break;
	}
	return p;
}

EngineAudioProfile make_car_audio(int id) {
	EngineAudioProfile a;
	switch (id) {
		case CAR_ABARTH_500: a.cylinders = 4; a.exhaust_resonance = 240; a.roughness = 0.22; a.growl = 0.5; a.turbo_whistle = 0.5; break;
		case CAR_GOLF_GTI: a.cylinders = 4; a.exhaust_resonance = 200; a.roughness = 0.16; a.growl = 0.42; a.turbo_whistle = 0.45; break;
		case CAR_BMW_M3_E30: a.cylinders = 4; a.exhaust_resonance = 225; a.roughness = 0.16; a.growl = 0.5; break;
		case CAR_PORSCHE_930: a.cylinders = 6; a.exhaust_resonance = 175; a.roughness = 0.18; a.growl = 0.55; a.turbo_whistle = 0.9; a.uneven = 0.25; break;
		case CAR_JAGUAR_ETYPE: a.cylinders = 6; a.exhaust_resonance = 150; a.roughness = 0.14; a.growl = 0.6; break;
		case CAR_MB_300SL: a.cylinders = 6; a.exhaust_resonance = 145; a.roughness = 0.14; a.growl = 0.45; break;
		case CAR_DEFENDER_90: a.cylinders = 5; a.diesel = true; a.exhaust_resonance = 105; a.roughness = 0.45; a.growl = 0.75; a.turbo_whistle = 0.5; a.uneven = 0.2; break;
		case CAR_AUDI_QUATTRO: a.cylinders = 5; a.exhaust_resonance = 170; a.roughness = 0.2; a.growl = 0.62; a.turbo_whistle = 0.85; a.uneven = 0.22; break;
		case CAR_JAGUAR_FTYPE: a.cylinders = 8; a.exhaust_resonance = 120; a.roughness = 0.14; a.growl = 0.9; a.turbo_whistle = 0.35; a.uneven = 0.35; break;
		case CAR_MB_G63: a.cylinders = 8; a.exhaust_resonance = 112; a.roughness = 0.16; a.growl = 0.85; a.turbo_whistle = 0.4; a.uneven = 0.35; break;
		case CAR_BMW_M4: a.cylinders = 6; a.exhaust_resonance = 150; a.roughness = 0.12; a.growl = 0.62; a.turbo_whistle = 0.55; break;
		case CAR_AUDI_R8: a.cylinders = 10; a.exhaust_resonance = 210; a.roughness = 0.1; a.growl = 0.6; a.uneven = 0.12; break;
		case CAR_PORSCHE_992: a.cylinders = 6; a.exhaust_resonance = 170; a.roughness = 0.12; a.growl = 0.55; a.turbo_whistle = 0.6; a.uneven = 0.2; break;
		case CAR_FERRARI_TESTAROSSA: a.cylinders = 12; a.exhaust_resonance = 190; a.roughness = 0.1; a.growl = 0.55; a.uneven = 0.1; break;
		case CAR_FERRARI_F40: a.cylinders = 8; a.exhaust_resonance = 205; a.roughness = 0.16; a.growl = 0.72; a.turbo_whistle = 1.0; a.straight_cut = true; break;
		case CAR_LAMBO_SVJ: a.cylinders = 12; a.exhaust_resonance = 220; a.roughness = 0.08; a.growl = 0.78; a.straight_cut = true; break;
		case CAR_JAGUAR_XJ220: a.cylinders = 6; a.exhaust_resonance = 165; a.roughness = 0.16; a.growl = 0.6; a.turbo_whistle = 0.9; a.uneven = 0.3; break;
		case CAR_PORSCHE_918: a.cylinders = 8; a.hybrid = true; a.exhaust_resonance = 235; a.roughness = 0.08; a.growl = 0.68; a.straight_cut = true; break;
		case CAR_FERRARI_LAFERRARI: a.cylinders = 12; a.hybrid = true; a.exhaust_resonance = 240; a.roughness = 0.07; a.growl = 0.72; a.straight_cut = true; break;
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
	X(hybrid_boost_nm) X(hybrid_power_kw) X(reverse_ratio) X(final_drive) X(shift_time) \
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
		if (g >= 1 && g <= 9) {
			p.gear_ratios[g - 1] = v;
			return true;
		}
		return false;
	}
	if (k == "gear_count") { p.gear_count = (int)clampr(v, 4, 9); return true; }
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
		p.hybrid_power_kw = donor.hybrid_power_kw;
		p.clutch_torque = std::max(p.clutch_torque, donor.clutch_torque);
		return true;
	}
	return false;
}

} // namespace nt
