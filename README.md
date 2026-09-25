# Euro GT Festival

An open-world driving festival on the real roads of **Monaco and the French Riviera**, built for the
**Retroid Pocket 4 Pro** handheld (Android, Dimensity 1100 / Mali-G77, 1334×750). Forza Horizon 4 in
spirit: a festival hub, European sports and grand-touring cars, road races, rival duels, time attack and
Gendarmerie pursuits across Monte-Carlo, the three Corniches, La Turbie and the A8.

Godot 4.7.2 (Mobile / Vulkan) with the vehicle physics, world generation and traffic in a C++
GDExtension. Version 0.5.0 — **a private, non-commercial fan project** (see [Legal](#legal)).

## Status

| Area | State |
|---|---|
| Cars | 19 real European cars + 6 traffic cars from CC-BY models, rigged for the game (steering / spinning wheels, lights, glass, paint), real-spec physics |
| Map | Real Monaco / Riviera from OpenStreetMap and elevation data: ~9 × 6 km, the Monaco GP circuit (3.33 km, real 3.34 km), the Corniches, A8, harbours |
| World | Photo-textured roads, pavements, hillsides and buildings (Riviera facades, tiled roofs), real trees and street furniture, yachts, day/night photographic sky, weather, sea with shallows |
| Events | 17 events on real routes: circuits, sprints, rival duels, time attack, pursuits, the Festival Grand Prix finale |
| Menus | Forza Horizon 4-style front end: LB/RB tabs, tile pages, events browser, credits. In progress: tile artwork, Autoshow / Garage car grids, Wheelspin |
| Performance | Optimised draw calls and shadows (see `docs/RP4_PERFORMANCE_PLAN.md`); on-device RP4 measurements in progress |

Planning and progress: [`docs/EURO_OVERHAUL_PLAN.md`](docs/EURO_OVERHAUL_PLAN.md) (overhaul phases and log),
[`docs/RP4_PERFORMANCE_PLAN.md`](docs/RP4_PERFORMANCE_PLAN.md) (device budgets and measurements).

## Cars

FH4-style performance index (PI) and classes. Models are credited to their authors below and in the
in-game Credits screen; each was scaled, re-rigged and optimised for the game.

| Class | PI | Car | Year | How to get it | 3D model (CC-BY 4.0) |
| :---: | :---: | :--- | :---: | :--- | :--- |
| D | 224 | **Land Rover Defender 90** | 1998 | Autoshow · CR 42,000 | [Land Rover Defender 90 Lowpoly](https://sketchfab.com/3d-models/land-rover-defender-90-lowpoly-88e5f30687ec4d508cebafa876e014d6) by kekomag |
| D | 377 | **Mercedes-Benz 300 SL Gullwing** | 1955 | Barn find | [Mercedes-Benz 300 SL Gullwing](https://sketchfab.com/3d-models/mercedes-benz-300-sl-gullwing-505241c829c540a4921533000736904e) by Lexyc16 |
| C | 533 | **BMW M3 (E30)** | 1987 | Starter choice · CR 58,000 | [[FREE] BMW M3 E30](https://sketchfab.com/3d-models/free-bmw-m3-e30-ac3c7013434e403e8faff87948caf422) by Martin Trafas |
| C | 551 | **Jaguar E-Type Lightweight** | 1963 | Barn find | [Jaguar E-Type Lightweight GT](https://sketchfab.com/3d-models/jaguar-e-type-lightweight-gt-8c53321301234400b70975fa6abb5e5d) by M17pro |
| C | 561 | **Porsche 911 Turbo (930)** | 1975 | Autoshow · CR 125,000 | [FREE 1975 Porsche 911 (930) Turbo](https://sketchfab.com/3d-models/free-1975-porsche-911-930-turbo-8568d9d14a994b9cae59499f0dbed21e) by Lionsharp Studios |
| C | 574 | **Audi quattro** | 1983 | Autoshow · CR 82,000 | [1980 Audi Ur Quattro](https://sketchfab.com/3d-models/1980-audi-ur-quattro-b9ccdd8ddc154ee99ab153794042fd07) by Robert Doman |
| C | 593 | **Fiat Abarth 500** | 2008 | Starter choice · CR 32,000 | [Fiat Abarth 500](https://sketchfab.com/3d-models/fiat-abarth-500-b59a403dfa1d40318c1126e658f87c19) by Luquita |
| B | 633 | **Volkswagen Golf GTI** | 2005 | Starter choice · CR 38,000 | [vw golf 5 gti](https://sketchfab.com/3d-models/vw-golf-5-gti-4389c32f54964b5ab01aa8462419b6c1) by Preview2SEbIT69 |
| B | 663 | **Mercedes-AMG G 63** | 2019 | Autoshow · CR 178,000 | [Mersedes-Benz G63 AMG](https://sketchfab.com/3d-models/mersedes-benz-g63-amg-e5e2a1d2238048a1a494b3df983c16bb) by Black Snow |
| A | 703 | **Ferrari Testarossa** | 1985 | Autoshow · CR 148,000 | [Ferrari Testarossa 84 Low Poly](https://sketchfab.com/3d-models/ferrari-testarossa-84-low-poly-1786b089bfbb40ea9ecd9dc4f4e73127) by kekomag |
| A | 727 | **BMW M4 Coupé (F82)** | 2015 | Autoshow · CR 74,000 | [BMW M4 f82](https://sketchfab.com/3d-models/bmw-m4-f82-8e87379f40fd40dcac0a751e22c1a188) by Black Snow |
| A | 788 | **Jaguar XJ220** | 1992 | Autoshow · CR 480,000 | [Jaguar XJ220 1991](https://sketchfab.com/3d-models/jaguar-xj220-1991-d99bb7b0fc0e4e3c9553246679dd067f) by Comrade1280 |
| A | 792 | **Jaguar F-Type R Coupé** | 2017 | Autoshow · CR 115,000 | [2017 Jaguar F-Type R Coupe](https://sketchfab.com/3d-models/2017-jaguar-f-type-r-coupe-de4dfe1256564276b9a134535f324b7a) by Galaxy Car Showroom |
| A | 793 | **Ferrari F40** | 1987 | Autoshow · CR 1,350,000 | [Ferrari f40](https://sketchfab.com/3d-models/ferrari-f40-52a66c41cfcd4f999fb1b1c49bf24d70) by Black Snow |
| S1 | 829 | **Porsche 911 Turbo S (992)** | 2020 | Autoshow · CR 235,000 | [Porsche 911 with interior](https://sketchfab.com/3d-models/porsche-911-with-interior-877b1bc1739f4a2bb65d62fd7ffd9f75) by n.brizitskaya |
| S1 | 835 | **Audi R8 V10 performance** | 2019 | Autoshow · CR 188,000 | [Audi R8](https://sketchfab.com/3d-models/audi-r8-e17e438f076f4427a58d93aa779edaed) by wallon |
| S1 | 853 | **Lamborghini Aventador SVJ** | 2019 | Autoshow · CR 520,000 | [Lamborghini Aventador SVJ SDC ( FREE )](https://sketchfab.com/3d-models/lamborghini-aventador-svj-sdc-free-784e4656aca649cca55d6b18740a19b2) by SDC PERFORMANCE™ |
| S1 | 866 | **Ferrari LaFerrari** | 2014 | Festival Grand Prix prize | [2013 Ferrari laferrari](https://sketchfab.com/3d-models/2013-ferrari-laferrari-f75b682bb0de4a14b3b6c1f52862ca48) by XENVOR creations |
| S1 | 889 | **Porsche 918 Spyder** | 2015 | Autoshow · CR 1,600,000 | [Porsche 918 Free](https://sketchfab.com/3d-models/porsche-918-free-ec8eebcdbf534bbba151375b9992f6d7) by Black Snow |

Traffic (right-hand driving, near/far detail levels):

| Traffic | 3D model (CC-BY 4.0) |
| :--- | :--- |
| Volkswagen Polo | [2016 Volkswagen Polo](https://sketchfab.com/3d-models/2016-volkswagen-polo-bab77902c638427bb85e68b6762a481f) by BHP3D |
| Škoda Superb | [2017 Skoda Superb](https://sketchfab.com/3d-models/2017-skoda-superb-2da5059c3068448b9541eafb930a45a0) by BHP3D |
| Volvo V60 | [Volvo V60 Polestar (2013)](https://sketchfab.com/3d-models/volvo-v60-polestar-2013-504ce39150fe49c7979f702d5f0f8580) by Myedsu |
| Volkswagen Transporter T6 | [Volkswagen van T6](https://sketchfab.com/3d-models/volkswagen-van-t6-b36c0e9bf97b479f9193cce337f4d4c2) by IrisProcess |
| Mercedes-Benz Sprinter | [Mercedes Benz Sprinter 2006](https://sketchfab.com/3d-models/mercedes-benz-sprinter-2006-f69de1315bb049c8946d57f6006acd73) by Max |
| Town bus | [Generic Town Bus](https://sketchfab.com/3d-models/generic-town-bus-14fe03d792914d51b6c6250b393c44fd) by own.guest |

## The map

Everything drivable comes from real data, baked offline by `tools/mapbake` into
`godot/assets/map/riviera.bin`:

* **Roads** from OpenStreetMap: split at junctions, real widths and lane counts, one-way streets,
  bridges and tunnels, junction polygons with French markings, grade-limited profiles.
* **Terrain** from AWS Terrain Tiles (8 m grid) with land cover (town, park, forest, scrub, rock, sand,
  farm, port) driving the surfaces and vegetation.
* **Buildings** from OSM footprints and heights, dressed by a Riviera facade shader (recessed windows,
  shutters, balconies, cornices, shop fronts) with clay-tile or flat roofs.
* **Routes**: the Circuit de Monaco follows the real lap (Sainte-Dévote, Casino, Mirabeau, the tunnel,
  Tabac, the Piscine), plus the Grande / Moyenne / Basse Corniche, the A8, Col du Mont Agel and the
  Route de La Turbie.

## Controls (Retroid Pocket 4 Pro)

| Input | Driving | Menus |
|---|---|---|
| Right trigger | Throttle | |
| Left trigger | Brake / reverse | |
| Left stick | Steer | Navigate |
| A | Handbrake | Select |
| B | Clutch | Back |
| Y / X | Shift up / down | Screen actions |
| LB | Rewind | Previous tab |
| RB | Change camera | Next tab |
| L3 | Look back | |
| R3 | Map | |
| D-pad up / down | Headlights / horn | Navigate |
| D-pad left / right | Radio previous / next | Navigate |
| Select | Recover car | |
| Start | Pause | |

Every action can be remapped in Options → Controls.

## Repository layout

```
godot/            Godot project (scripts, shaders, scenes, baked assets)
  assets/cars/    baked car models + metadata/credits (tools/carbake)
  assets/props/   baked world props (tools/carbake/props.mjs)
  assets/env/     texture arrays + sky panoramas (Poly Haven CC0)
  assets/map/     riviera.bin / riviera.json (tools/mapbake)
native/           C++ GDExtension: vehicle physics, world, traffic, AI (+ doctest suite)
android_plugin/   RP4 Android bridge (thermal / performance hints, haptics)
tools/            build, export, device and asset-pipeline scripts
docs/             plans and progress
```

## Building

Toolchain: `D:\RP4Toolchain` (Godot 4.7.2, llvm-mingw, Android SDK/NDK 28, JDK 17, Python), set up by
`tools/setup-toolchain.ps1`; `tools/env.ps1` puts it on the path.

```powershell
tools\build-native.ps1 -Platform windows -Target template_debug   # C++ GDExtension (desktop)
tools\build-native.ps1 -Platform all -Target both                 # desktop + Android arm64
tools\run-native-tests.ps1                                         # native physics / world tests
tools\play.ps1 [scene=freeroam car=ferrari_f40 time=18]            # open (or restart) a play window
tools\export-android.ps1                                           # signed APK for the RP4
tools\device_harness.ps1 deploy                                    # install on the connected RP4
```

Checks: `godot_console --headless --path godot -- scene=check` compiles every script;
`-- scene=festival ui_shot=<dir>` screenshots every menu.

## Asset pipelines

| Tool | Does |
|---|---|
| `tools/carbake/fetch.mjs` + `bake.mjs` | Sketchfab download (licence-checked, CC-BY / CC0 only), orient/scale to real dimensions, split wheels to hub pivots, classify materials (paint, glass, lamps, tyres…), simplify, write credits |
| `tools/carbake/props.mjs` | World props from model packs: real size, foliage-aware thinning, far LODs |
| `tools/carbake/envtex.mjs` | Poly Haven texture arrays (ground, road, facade) |
| `tools/carbake/skybake.mjs` | Poly Haven HDRI day cycle → sky panoramas |
| `tools/mapbake` | OpenStreetMap + elevation → the baked map |
| `tools/readme_tables.mjs` | Regenerates the car / credit tables in this README |

Downloading from Sketchfab needs a personal API token in the `SKETCHFAB_TOKEN` environment variable;
it is never stored in the repository.

## Credits

* **Car and prop models**: the authors listed above, under Creative Commons Attribution 4.0
  (props: see the in-game Credits screen or `godot/assets/props/*/*.json`).
* **Textures and skies**: [Poly Haven](https://polyhaven.com) (CC0).
* **Map data**: © OpenStreetMap contributors (ODbL). Elevation: AWS Terrain Tiles (SRTM, EU-DEM, NOAA).
* **Type**: Barlow and Barlow Condensed by Jeremy Tribby (SIL Open Font License 1.1).
* **Engine**: Godot Engine (MIT), Jolt Physics (MIT).

## Legal

This is an unofficial fan project for private use on the author's own device. Car makes, model names
and logos are trademarks of their owners and are used for identification only; the project is not
affiliated with or endorsed by any manufacturer, Microsoft / Playground Games (Forza Horizon) or the
BBC (Top Gear). Do not distribute builds commercially.
