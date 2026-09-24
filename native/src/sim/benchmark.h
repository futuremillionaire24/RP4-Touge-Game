// Performance Index benchmark: runs the real physics on a virtual test pad (launch, top speed,
// braking, skidpad) and maps the results to a PI and class, like the garage in FH.
#pragma once

#include "vehicle.h"

namespace nt {

struct BenchmarkResult {
	real t_0_100 = 99.0; // s
	real t_0_200 = 99.0;
	real top_speed = 0.0; // km/h
	real brake_100_0 = 99.0; // m
	real lateral_g = 0.0;
	real quarter_mile = 99.0; // s
	real power_kw = 0.0;
	real weight_kg = 0.0;
	int pi = 100;
	int pi_class = 0; // 0 D, 1 C, 2 B, 3 A, 4 S1, 5 S2, 6 X
	real accel_score = 0, speed_score = 0, handling_score = 0, braking_score = 0, launch_score = 0; // 0..10
};

BenchmarkResult run_benchmark(const VehicleParams &p);
int pi_from_scores(real accel, real top, real grip, real brake);
const char *pi_class_name(int c);
int pi_class_of(int pi);

} // namespace nt
