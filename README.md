# Neon Touge RP4 (ネオン峠)

> **High-Performance JDM Mountain Pass & Expressway Racing Game**  
> Engineered specifically for the **Retroid Pocket 4 Pro** handheld gaming console.  
> Built with **Godot Engine 4.7.2**, **C++ GDExtension Native Simulation**, and **Vulkan Mobile**.

---

## 🏎️ Overview

**Neon Touge** is a precision arcade-sim racing game celebrating 1990s–2000s Japanese car culture. Set across dense mountain passes, high-speed coastal expressways, and neon-lit urban avenues, the game delivers an authentic driving feel inspired by *Gran Turismo 7* and *Forza Horizon 5*, locked at **60 FPS** on the Retroid Pocket 4 Pro's Mali-G77 MC9 GPU ($1334 \times 750$).

---

## 🛠️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Neon Touge Game Engine                     │
├───────────────────────────────┬─────────────────────────────────┤
│    GDScript 2.0 (Godot 4.7)   │      C++ Native GDExtension     │
├───────────────────────────────┼─────────────────────────────────┤
│ • World Map & Minimap (UI)    │ • Sub-stepped Vehicle Dynamics  │
│ • CarBuilder & PBR Rigging    │ • Pacejka Brush Tire Physics    │
│ • Shaders & Post-Processing   │ • Drivetrain, Clutch & Turbo    │
│ • Career, Economy & Garage    │ • AI Traffic & Rival Paths      │
│ • GPS Navigation Ribbon       │ • Procedural Engine Audio Synth │
├───────────────────────────────┴─────────────────────────────────┤
│                 Android RP4 Bridge (Kotlin Plugin)              │
├─────────────────────────────────────────────────────────────────┤
│ • Active Fan Mode Control (Quiet, Sport, High)                  │
│ • Low-Latency Analog Trigger Sampling (L2/R2)                   │
│ • Dual-Motor Haptic Vibration Feedback                          │
└─────────────────────────────────────────────────────────────────┘
```

- **Godot 4.7.2 (Vulkan Mobile)**: Handles rendering, materials, UI, and scene composition within a strict mobile thermal budget.
- **Native C++ Extension (`native/`)**: High-frequency 120 Hz physics sub-stepping, custom collision grid, spline interpolation, and procedural audio synthesis.
- **RP4 Android Plugin (`android_plugin/`)**: Direct hardware access to RP4 Pro fan speed profiles, battery management, and vibration actuators.

---

## 🚗 The 12 JDM Vehicle Roster

All vehicles feature authentic 20,000–35,000 vertex Catmull-Clark smooth subdivision lofts with blister fender arches, custom interiors with Recaro bucket seats, drilled disc rotors with Brembo calipers, dual polished chrome exhausts, and authentic JDM license plates.

| Key | Model | Maker | Year | PI | Class | Drivetrain | Wheels | Highlights |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `mame_k` | Suzuki Cappuccino (EA11R) | Suzuki | 1992 | 335 | **D** | FR (660cc Turbo) | BBS Sport 5 | 50:50 weight distribution, open-top |
| `hachi_gt` | Toyota Sprinter Trueno (AE86) | Toyota | 1985 | 376 | **D** | FR (4A-GE Twin-Cam) | RS Watanabe 8 | Working animated popup headlights, Panda two-tone |
| `kyudo_type_s` | Honda Civic Type R (EK9) | Honda | 1998 | 608 | **B** | FF (B16B VTEC) | Championship 5 | 9,000 RPM redline, helical LSD |
| `sylph_s2` | Nissan Silvia Spec-R (S15) | Nissan | 1999 | 545 | **C** | FR (SR20DET Turbo) | Volk TE37 6 | The benchmark touge drift machine |
| `rotora_fd` | Mazda RX-7 Type R (FD3S) | Mazda | 1997 | 579 | **C** | FR (13B-REW Twin-Turbo) | Mazdaspeed Split 5 | Sequential rotary power, sculpted aero wing |
| `tatsu_ix` | Mitsubishi Lancer Evo IX MR | Mitsubishi | 2006 | 658 | **A** | 4WD (4G63 MIVEC) | Enkei Rally 8 | Super All-Wheel Control, rally wing |
| `senko` | Honda NSX (NA1) | Honda | 1995 | 601 | **B** | MR (C30A VTEC) | Championship 5 | Animated popup headlights, Ayrton Senna chassis |
| `titan_rz` | Toyota Supra RZ (JZA80) | Toyota | 1998 | 617 | **B** | FR (2JZ-GTE Twin-Turbo) | Mazdaspeed Split 5 | 6-speed Getrag, Wangan king GT wing |
| `raijin_r` | Nissan Skyline GT-R (BNR34) | Nissan | 2001 | 690 | **A** | 4WD (RB26DETT) | Volk TE37 6 | ATTESA E-TS Pro AWD, Super HICAS steering |
| `kaido_van` | Toyota HiAce Custom (H200) | Toyota | 2004 | 206 | **D** | FR (Turbo-Diesel) | Enkei Rally 8 | Slammed custom delivery van, welded diff |
| `mugen_proto` | Tommykaira ZZ Proto | Tommykaira | 2021 | 779 | **S1** | MR (Lightweight Four) | Mazdaspeed Split 5 | Sub-800 kg track weapon with license plates |
| `kurogane_hyper` | Kurogane Hyper GT-Concept | Kurogane | 2026 | 897 | **S2** | AWD (Twin-Turbo V8 + Hybrid) | Volk TE37 6 | 1,000+ hp festival flagship hypercar |

---

## 🎮 Driving Physics & Simulation Engine

The C++ simulation runs at **120 Hz** using a customized non-linear Pacejka brush tire formulation:

1. **Zero-Bog Launch Acceleration**:
   - Standing-start auto-clutch launch torque is dynamically capped to $90\%$ of engine output below launch RPM.
   - Eliminates engine bogging and RPM collapse off the line; ensures clean, punchy launches in every gear.
2. **Handbrake Drift Initiation**:
   - Service braking utilizes active ABS modulation to prevent wheel lockups.
   - Handbrake input on rear wheels ($>0.05$) completely bypasses ABS, instantly locking rear tires to break traction and initiate smooth, controllable touge drifts.
3. **Drift-Adaptive Countersteer Authority**:
   - The high-speed steering limiter smoothly relaxes as drift angle increases ($k = \text{smoothstep}(0.04, 0.22, \|\text{drift\_angle}\|)$).
   - Drivers have full steering lock available mid-slide to catch extreme angles without fighting artificial steering clamp limits.
4. **Drift Snap Recovery Damping**:
   - Yaw damping is actively applied when yaw rate opposes the drift angle during countersteer exits ($2.4 \times \text{snap\_intensity}$).
   - Completely eliminates violent tank-slapper pendulum snaps, providing clean, predictable exits.
5. **Touge Hill-Hold Clamping**:
   - Longitudinal damping activates under stationary braking (`speed < 0.25 km/h` and `brake > 40 Nm`).
   - Vehicles remain firmly anchored on steep $12\%+$ mountain inclines without creep, slide, or physics oscillation chatter.
6. **Progressive Off-Throttle Coasting**:
   - Closed-throttle engine drag tuned to $0.006\text{ Nm/RPM}$ and friction torque to $14\text{ Nm}$, allowing realistic momentum preservation into high-speed corner entries.

---

## 🗺️ Vector Mapping & Navigation System

- **Vector Road Network**: Anti-aliased procedural 2D vector geometry rendering on high-priority CanvasLayer 25.
  - Touge passes in glowing Amber (`#FF8C00`)
  - Expressways in Magenta (`#E6007A`)
  - Urban Avenues in Silver (`#C8D2DC`)
- **A* GPS Road Routing**: Calculates turn-by-turn routes across the 176-segment road network and renders an in-world glowing 3D GPS navigation ribbon.
- **Dynamic Minimap**: Speed-sensitive automatic zoom ($240\text{m} \to 800\text{m}$), bezel radar clamping with directional chevrons for off-screen rivals/activities, and rotating North compass pip.
- **Forza Horizon Category Tabs**: Instant filtering between `ALL`, `RACES`, `PR STUNTS`, and `BARN FINDS`.

---

## 🎨 Graphics, Shaders & Lighting

- **Automotive PBR Paint (`car_paint.gdshader`)**:
  - Base coat, metallic flake layer, thin-film interference pearl layer, and Fresnel-weighted clearcoat.
  - Live damage deformation (8 car-local dent contact vectors), wetness, and dirt accumulation.
- **Animated Popup Headlights**:
  - Smooth motorized pivot animation for AE86 and NSX that raises lights $24^\circ$ on night driving mode.
- **Multi-Stage Lighting**:
  - Running lights glow soft at night; brake lights punch to $5.2\times$ vivid red emissive.
  - Twin polished chrome exhaust barrels emit backfire ignition sparks.

---

## 🎮 Retroid Pocket 4 Pro Controls

| Control | Action |
| :--- | :--- |
| **Left Stick / D-Pad** | Steering / UI Navigation |
| **Right Trigger (R2)** | Progressive Analog Throttle |
| **Left Trigger (L2)** | Progressive Analog Footbrake / Reverse |
| **A Button** | Handbrake (Drift Initiation) / Confirm |
| **B Button** | Back / Cancel / Clutch |
| **X Button** | Shift Down (Manual Sequential) |
| **Y Button** | Shift Up (Manual Sequential) |
| **Select Button** | Full-Screen World Map (Toggle) |
| **Start Button** | Pause Menu / Settings |
| **R1 / L1** | Map Filter Tabs (Left / Right) |
| **R3 (Right Stick Click)** | Headlights On / Off (Toggle Popups) |

---

## 🏗️ Build, Test & Export Guide

### Prerequisites
- Windows 10/11 x64
- Toolchain: `D:\RP4Toolchain` (Godot 4.7.2, Android SDK 36.1.0, NDK 28.0.12433566, JDK 21, SCons, LLVM/Clang)

### 1. Run Automated Regression Test Suites
```powershell
# Comprehensive Visual Rig & Physics Engine Audit (100% PASS)
D:\RP4Toolchain\godot\godot_console.exe --headless --path godot --script res://qa/racing_master_test.gd

# World Map, GPS Routing & Minimap Test (100% PASS)
D:\RP4Toolchain\godot\godot_console.exe --headless --path godot res://qa/map_test.tscn
```

### 2. Compile C++ GDExtension Native Libraries
```powershell
# Build for Windows x86_64
powershell -ExecutionPolicy Bypass -File tools/build-native.ps1 -Platform windows

# Build for Android arm64
powershell -ExecutionPolicy Bypass -File tools/build-native.ps1 -Platform android
```

### 3. Export Signed Android APK
```powershell
# Compiles arm64 native lib, builds RP4Bridge AAR, signs, and exports to dist/NeonTougeRP4.apk
powershell -ExecutionPolicy Bypass -File tools/export-android.ps1
```

The resulting signed APK will be output to:
`d:\Android_RP4_Game\dist\NeonTougeRP4.apk`

---

## 📄 License & Attribution

- **Game Code & Shaders**: MIT License.
- **Vehicle Models & Procedural Rigs**: CC0 & CC-BY 4.0 (Full details in `godot/assets/models/cars/CREDITS.md`).
- **Soundtrack & Audio**: Procedurally generated synthesized engine harmonics and CC0 atmospheric audio.