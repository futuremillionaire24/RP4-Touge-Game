# Euro GT Festival (RP4 Edition)

> **Premier European Open-World Racing Festival on the French Riviera**  
> Engineered specifically for the **Retroid Pocket 4 Pro** handheld console (Dimensity 1100, Mali-G77 MC9, $1334 \times 750$ @ 60 FPS locked).  
> Built with **Godot Engine 4.7.2**, **C++ GDExtension Native Simulation**, and **Vulkan Mobile**.

---

## 🏁 Overview

**Euro GT Festival** is an authentic European open-world arcade-simulation racing game inspired by *Forza Horizon 4* and *Gran Turismo 7*. Set along the scenic Mediterranean coast of the **French Riviera** and the principality of **Monaco**, drivers explore iconic real-world roads including the **Monaco Grand Prix street circuit**, the **Grande, Moyenne, and Basse Corniches** ascending to La Turbie, and the high-speed **A8 autoroute** viaducts and tunnels.

The game features an authentic **19-car European roster** spanning hot hatches, vintage grand tourers, Group B homologations, modern supercars, and flagship hypercars, all backed by real manufacturer engineering specs and locked at a solid **60 FPS** on mobile hardware.

---

## 🛠️ System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Euro GT Festival Architecture                │
├───────────────────────────────┬─────────────────────────────────┤
│    GDScript 2.0 (Godot 4.7)   │      C++ Native GDExtension     │
├───────────────────────────────┼─────────────────────────────────┤
│ • FH4-Style Tile & Tab UI     │ • 120 Hz Sub-stepped Physics    │
│ • CarBuilder PBR Rigging      │ • Pacejka Brush Tire Model      │
│ • European PBR World Shaders  │ • 19-Car Dyno Engine Curves     │
│ • OSM Vector Map & GPS Ribbon │ • Native Open-World Streamer    │
│ • Weather & Mediterranean Rig │ • Procedural Multi-Cyl Audio    │
├───────────────────────────────┴─────────────────────────────────┤
│                 Android RP4 Bridge (Kotlin Plugin)              │
├─────────────────────────────────────────────────────────────────┤
│ • Active Fan Profiles (Quiet, Sport, High)                      │
│ • Progressive Low-Latency Trigger Sampling (L2/R2)              │
│ • Dual-Motor Force Feedback Haptics                             │
└─────────────────────────────────────────────────────────────────┘
```

- **Godot 4.7.2 (Vulkan Mobile)**: MultiMesh GPU batching, 4-cascade directional shadows (280m), ACES filmic tonemapping, and customized PBR surface shaders.
- **Native C++ Extension (`native/`)**: High-frequency sub-stepped physics simulation, arbitrary polygon junction meshing, 8m heightfield DEM terrain, and AI race director.
- **RP4 Android Plugin (`android_plugin/`)**: Direct hardware access to cooling fan speeds, analog triggers, and dual rumble motors.

---

## 🏎️ The European Vehicle Roster (19 Cars)

Every vehicle is modeled from verified CC-BY / CC0 photoreal scans with separated spinning/steering wheels, real suspension travel, authentic manufacturer dimensions, dyno power/torque curves, and accurate gear ratios.

| Class | Model | Year | Drivetrain | Power | Weight | Benchmark (0–100 / Top) | Source / Attribution |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **D** | **Abarth 500 Esseesse** | 2012 | FWD (1.4L Turbo I4) | 160 hp | 1,035 kg | 7.4s / 211 km/h | Sketchfab CC-BY (@xplm) |
| **D** | **Volkswagen Golf GTI (Mk2)** | 1990 | FWD (1.8L 16V I4) | 139 hp | 1,010 kg | 8.2s / 208 km/h | Sketchfab CC-BY (@alex.yaremenko) |
| **D** | **Mercedes-Benz 300 SL Gullwing** | 1955 | RWD (3.0L M198 I6) | 215 hp | 1,295 kg | 8.8s / 225 km/h | Sketchfab CC-BY (@Lexyc16) |
| **D** | **Land Rover Defender 90** | 1997 | 4WD (2.5L Td5 Turbo) | 122 hp | 1,770 kg | 15.8s / 140 km/h | Sketchfab CC-BY (@kekomag) |
| **C** | **BMW M3 (E30)** *(Starter)* | 1988 | RWD (2.3L S14 I4) | 200 hp | 1,200 kg | 6.7s / 235 km/h | Sketchfab CC-BY (@TinoD2) |
| **C** | **Porsche 911 Turbo (930)** *(Starter)* | 1982 | RWD (3.3L Turbo Flat-6) | 300 hp | 1,300 kg | 5.2s / 260 km/h | Sketchfab CC-BY (@Lexyc16) |
| **C** | **Jaguar E-Type Lightweight** *(Starter)* | 1963 | RWD (3.8L XK I6) | 300 hp | 975 kg | 5.3s / 240 km/h | Sketchfab CC-BY (@m17pro) |
| **B** | **Audi Sport quattro** | 1984 | AWD (2.1L 20V Turbo I5) | 306 hp | 1,298 kg | 4.8s / 250 km/h | Sketchfab CC-BY (@RDoman) |
| **B** | **Jaguar F-Type R** | 2016 | AWD (5.0L Supercharged V8) | 550 hp | 1,730 kg | 4.1s / 300 km/h | Sketchfab CC-BY (@oneSteven) |
| **B** | **Mercedes-AMG G 63** | 2019 | 4WD (4.0L BiTurbo V8) | 577 hp | 2,560 kg | 4.5s / 240 km/h | Sketchfab CC-BY (@BlackSnow02) |
| **A** | **BMW M4 Coupe (F82)** | 2018 | RWD (3.0L Twin-Turbo I6) | 431 hp | 1,572 kg | 4.1s / 280 km/h | Sketchfab CC-BY (@BlackSnow02) |
| **A** | **Ferrari Testarossa** | 1984 | RWD (4.9L Flat-12) | 390 hp | 1,506 kg | 5.3s / 290 km/h | Sketchfab CC-BY (@Lexyc16) |
| **A** | **Audi R8 V10 Plus** | 2017 | AWD (5.2L FSI V10) | 610 hp | 1,555 kg | 3.2s / 330 km/h | Sketchfab CC-BY (@realwallon) |
| **A** | **Porsche 911 GT3 (992)** | 2021 | RWD (4.0L Boxer-6) | 510 hp | 1,435 kg | 3.4s / 318 km/h | Sketchfab CC-BY (@n.brizitskaya) |
| **A** | **Ferrari F40** | 1987 | RWD (2.9L Twin-Turbo V8) | 478 hp | 1,254 kg | 4.1s / 324 km/h | Sketchfab CC-BY (@BlackSnow02) |
| **S1** | **Lamborghini Aventador SVJ** | 2019 | AWD (6.5L L539 V12) | 770 hp | 1,525 kg | 2.8s / 352 km/h | Sketchfab CC-BY (@Lambo_SC04) |
| **S1** | **Jaguar XJ220** | 1992 | RWD (3.5L Twin-Turbo V6) | 542 hp | 1,470 kg | 3.8s / 349 km/h | Sketchfab CC-BY (@comrade1280) |
| **S2** | **Porsche 918 Spyder** | 2015 | AWD (4.6L V8 Hybrid) | 887 hp | 1,674 kg | 2.6s / 345 km/h | Sketchfab CC-BY (@BlackSnow02) |
| **S2** | **Ferrari LaFerrari** *(Championship)* | 2013 | RWD (6.3L V12 HY-KERS) | 963 hp | 1,430 kg | 2.6s / 352 km/h | Sketchfab CC-BY (@BlackSnow02) |

---

## 🎨 Automotive Paint & PBR Material Pipeline

The car paint shader (`car_paint.gdshader`) was completely overhauled to eliminate sub-pixel mobile glitter artifacts:

- **Statistical Flake Formulation**: Replaced noisy per-pixel stochastic sparklers with a continuous micro-facet metallic flake lobe, providing authentic showroom depth without sub-pixel aliasing.
- **Factory Finish Presets**:
  - `Solid`: Pure high-gloss basecoat with deep clearcoat reflection.
  - `Metallic`: Fine statistical aluminum flake (0.25 gain) with dual-layer clearcoat.
  - `Pearlescent`: Angle-dependent color travel and thin-film interference.
  - `Matte & Satin`: Micro-roughness scatter with suppressed specular highlights.
  - `Chrome & Carbon`: Mirror specular reflectance and anisotropic carbon weave normals.
- **Realistic Lighting Response**: PBR headlight lenses, front/rear split brake lights, thermal rotor glow, and exhaust overrun flames.

---

## 🌍 Real-World Riviera Map & Environment

The racing environment represents **~8.9 × 6.1 km** of the French Riviera and Monaco:

1. **Real OpenStreetMap & Elevation Terrain**:
   - Built via `tools/mapbake/` using OpenStreetMap vectors (ODbL) and AWS Terrarium 8m DEM elevation tiles (`riviera.bin`).
   - Features **219.3 km of drivable roads**, 1,670 road spans, 813 arbitrary polygon junctions, and 14 districts.
   - Includes the complete **Monaco Grand Prix street circuit** (3,331 m modeled, 3,337 m real), Sainte-Dévote, Casino Square, the Fairmont Hairpin Tunnel, and Portier.
2. **Procedural Architectural Realism**:
   - European facade shader (`facade.gdshader`) with parallax-recessed windows, Provencal shutters, and shop awnings.
   - **Procedural 3D Balconies & Roof Cornices**: Extruded geometric balconies on Riviera apartment buildings and projecting eaves at rooflines cast true 3D silhouettes at high glancing angles.
   - **Stone Retaining Walls (*Murs de Soutènement*)**: Mountain cuts along the Grande Corniche feature dressed-limestone retaining walls and concrete tunnel portal headwalls.
3. **Authentic Road Infrastructure & Safety**:
   - European standard road markings: transverse give-way lines, solid stop bars, and pedestrian zebra crossings (residual Shibuya scramble removed).
   - **W-Beam Guardrails (`rail.gdshader`)**: Galvanized corrugated steel normal profile, post shadows, and retro-reflective delineator cat-eyes every 4 meters.
   - **Night Streetlight Ground Cookies**: Projected warm sodium/LED light pools illuminate asphalt beneath streetlights with zero dynamic light draw-call overhead.
4. **Foliage & Maritime Realism**:
   - Merged multi-mesh glTF ingestion in `prop_library.gd`: Canary Island date palms, stone umbrella pines, pencil cypresses, and gnarled olive trees.
   - **Port Hercule Marina**: Multi-deck mega-yachts moored Mediterranean-style stern-to along concrete quays with depth-based turquoise-to-ultramarine sea gradients and Mediterranean sun glitter (`water.gdshader`).

---

## 🧭 Forza Horizon 4-Style European UI

The user interface was redesigned from the ground up:

- **Typography**: Authentic European road-sign DIN typeface (**D-DIN**) paired with bold uppercase headings (**Barlow Condensed**).
- **Navigation**: Top **LB / RB category tab bar** (Campaign, Cars, My Festival, Settings), interactive tile grids with focus-pop frames, and bottom controller button glyph bar.
- **Color Palette**: Sophisticated charcoal glass panels (`#1A1A2E`), Horizon pink accents, British Racing Green, and Italian Rosso Corsa class badges (**D, C, B, A, S1, S2**).
- **Festival Hub**: Open-air seaside plaza vehicle stage set under a dynamic day-night photographic HDR sky cycle.
- **European Economy**: Currency transitioned to **CR** (Credits), vehicle dealerships categorized by European marque, and Horizon-style Festival prize spins.

---

## 🎮 Retroid Pocket 4 Pro Controls

| Control | Action |
| :--- | :--- |
| **Left Stick / D-Pad** | Steering / Menu Tile Navigation |
| **Right Trigger (R2)** | Progressive Analog Throttle |
| **Left Trigger (L2)** | Progressive Analog Footbrake / Reverse |
| **A Button** | Handbrake (Drift Initiation) / Confirm |
| **B Button** | Back / Cancel / Clutch |
| **X Button** | Shift Down (Manual Sequential) |
| **Y Button** | Shift Up (Manual Sequential) |
| **Select Button** | Full-Screen Vector Map (Toggle) |
| **Start Button** | Pause Menu / Festival Hub |
| **L1 / R1** | Tab Navigation (Left / Right) |
| **R3 (Right Stick Click)** | Headlights Toggle (High / Low Beam) |

---

## 🏗️ Build, Test & Verification Guide

### Prerequisites
- Toolchain: `D:\RP4Toolchain` (Clang++ 19, Python 3.12, Android SDK 36.1.0, NDK 28.1.13356709, JDK 17, Godot 4.7.2 official console).

### 1. Run Automated Test Suites
```powershell
# Run native simulation doctest suite (19 test cases, 1,653 assertions - 100% PASS)
powershell -ExecutionPolicy Bypass -File tools/run-native-tests.ps1

# Run Godot script and shader compile verification (137 files, 0 failures)
D:\RP4Toolchain\godot\godot_console.exe --headless --path godot -- scene=check
```

### 2. Compile Native GDExtension Libraries
```powershell
# Builds Windows (.dll) and Android arm64 (.so) for debug and release
powershell -ExecutionPolicy Bypass -File tools/build-native.ps1 -Platform all -Target both
```

### 3. Package & Sign Android APK
```powershell
# Builds Android RP4Bridge plugin, compiles release APK, signs with release keystore
powershell -ExecutionPolicy Bypass -File tools/export-android.ps1 -SkipNative
```

The signed release APK will be output to:
- `NeonTougeRP4.apk` (Root directory, 252.4 MB)
- `dist/NeonTougeRP4.apk`

---

## 📄 License & Attribution

- **Game Code & Shaders**: MIT License.
- **Map & Geography**: OpenStreetMap data © OpenStreetMap contributors (ODbL), AWS Terrain Tiles / SRTM.
- **3D Vehicle & Prop Models**: CC-BY 4.0 / CC0 models from Sketchfab authors (complete attribution list available on the in-game Credits screen and `credits.json`).