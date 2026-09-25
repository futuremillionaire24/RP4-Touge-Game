# Euro GT Festival — Production Overhaul Plan

Supersedes the Antigravity "Euro GT Festival" plan (2026-09-24, never implemented). Key differences
from that plan: **real brands and real car models** (user decision), a **real European map built
from OpenStreetMap + real terrain**, and a model pipeline that uses photoreal CC-BY / CC0 assets.

Target: Retroid Pocket 4 Pro (Dimensity 1100, Mali-G77 MC9, 1334x750, 8 GB) at 60 fps, Godot 4.7
Mobile/Vulkan + C++ GDExtension. Private sideload build.

---

## 1. What is wrong today (root causes)

| Complaint | Root cause found in the code |
|---|---|
| Cars look like Roblox | Player cars are procedural lofted blobs (`car_body.gd` + `subdiv.gd`) or Kenney/cartoon GLBs (`sports_hatch.glb`, `race_future.glb`…) whose single palette texture gets tinted (`car_builder.gd:95-105`). No real glass, lights, interiors or wheels. |
| Paint looks like glitter | `car_paint.gdshader` adds per-light "flake glints" with `glint_gain = 60` from pixel-sized stochastic flakes (lines 115-131, 243-245) plus an albedo speckle. At 1334x750 the flakes are sub-pixel, so they alias into sparkling noise. `metallic` finish uses `flake = 0.8`. |
| NPC cars terrible | Traffic uses the same Kenney low-poly GLBs merged into one surface (`traffic_view.gd`). Also drives on the **left** (Japan) — wrong for Europe. |
| Environment / buildings look fake | Buildings are extruded boxes with a procedural window shader (`facade.gdshader`, flat roofs). Trees are icosphere blobs and cones (`prop_library.gd`). Terrain is vertex-coloured. Sky is a flat `ProceduralSkyMaterial`. No PBR textures anywhere in the world. |
| Map needs more / characterful roads | `world.cpp::layout_roads()` is a 9x9 straight grid, one loop, one touge. Junctions only support axis-aligned rectangles. |
| Theme / menus | JDM neon theme: kanji headers, neon pink/cyan (`ui_kit.gd`), Yen, Omikuji, Daikoku PA, Shuto, Akina. |
| Physics vs look | Roster is JDM; visuals add a fake steer-driven body roll on top of the sim's real roll (`car_view.gd:136-151`), so body motion doesn't match the physics. |

## 2. Direction

* **Theme:** Forza Horizon 4 × Top Gear, European. Festival on the **Côte d'Azur (Monaco / Monte-Carlo, Cap d'Ail, La Turbie, Roquebrune)**. Currency **CR**. Clean German/European typography (DIN-style).
* **Map:** the real road network of Monaco and the Riviera from **OpenStreetMap** (ODbL, attributed) on **real terrain** (AWS Terrain Tiles / SRTM). Includes the Monaco GP street circuit, the tunnel, the harbour, the **Grande / Moyenne / Basse Corniche** switchbacks up to La Turbie, and the **A8 autoroute** with its tunnels and viaducts. ~8.9 × 6.1 km, same footprint as the current world.
* **Cars:** real European cars from Sketchfab CC-BY / CC0 (user-provided token), verified licence per model, no game rips.

## 3. Phases (execution order)

### Phase A — Car pipeline + paint (top priority)
1. `tools/carbake/` (Node + glTF-Transform): download from Sketchfab, verify licence via API, decode Draco/meshopt, bake transforms, orient (−Z forward, wheels on y=0), scale to real length, **split wheels** into `Wheel_FL/FR/RL/RR` pivots at hub centres, classify materials → `paint / glass / chrome / trim / tyre / rim / light_head / light_tail / interior / plate`, weld + simplify to **LOD0 ≤ 90k tris (player), LOD1 ≤ 25k (AI/showroom far), LOD2 ≤ 6k**, textures → 1024 px (ASTC on import), write `credits.json`.
2. `CarBuilder`: load the baked GLB, apply the shared material library per class (new paint shader on `paint`, real glass, chrome, rubber), use the model's own wheels (spin + steer + suspension travel), emissive head/tail/brake/reverse lights, plate.
3. **Paint shader rewrite:** remove per-light glints and albedo speckle; metallic flake becomes a **statistical** effect (brighter face/darker flop + widened secondary specular lobe), clear coat stays; finishes re-tuned (metallic flake 0.25, pearl, matte, satin, chrome). Result: smooth, deep, showroom-real paint.

### Phase B — European roster (16 cars) + save migration
| Class | Car | Source |
|---|---|---|
| D | Volkswagen Golf GTI (Mk2/Mk7 — best available) | Sketchfab CC-BY |
| D | Land Rover Defender 90 | @kekomag |
| D | Mercedes-Benz 300 SL Gullwing (1955) | @Lexyc16 |
| C | BMW M3 (E30) — starter | @TinoD2 |
| C | Porsche 911 Turbo (930) — starter | @Lexyc16 / @lionsharp |
| C | Jaguar E-Type Lightweight — starter | @m17pro |
| B | Audi Sport quattro / RS 6 Avant | @RDoman / @adrianaflak09 |
| B | Jaguar F-Type R | best non-rip |
| B | Mercedes-AMG G 63 | @BlackSnow02 |
| A | BMW M4 (F82) | @BlackSnow02 |
| A | Audi R8 V10 | @realwallon |
| A | Porsche 911 (992) | @n.brizitskaya |
| A | Ferrari F40 | @BlackSnow02 |
| S1 | Ferrari 458 Italia | vicent091036 (three.js) |
| S1 | Lamborghini Aventador SVJ | @Lambo_SC04 |
| S2 | Jaguar XJ220 / Porsche 918 Spyder / McLaren Senna (championship reward) | @comrade1280 / @BlackSnow02 |

Every car gets real specs in `roster.cpp` (mass, weight split, wheelbase, track, tyre sizes, real torque curve, real gear ratios, layout, diffs, aero), a matching engine-audio profile, and a `CarData` entry (real name, maker, year, blurb, price in CR). Old JDM keys migrate in `Profile` to the new keys.

### Phase C — Forza Horizon 4-style European UI
* New `UIKit`: charcoal glass panels, **FH4 tile grid** (1×1 / 2×1 / 2×2 coloured tiles with photo art, bold condensed uppercase titles, white focus frame + scale pop), **LB/RB top tab bar**, CR + level wristband top-right, prompt bar bottom.
* Fonts (OFL): **Barlow Condensed** (headings) + **D-DIN** (body/figures, German road-sign DIN look).
* Palette: FH4 "Horizon pink" accent + season colours; class badges in Forza colours.
* All kanji / Japanese names removed; Omikuji → **Wheelspin**; districts, rivals, event names, festival hub (Port Hercule), title screen ("EURO GT FESTIVAL"), loading tips re-written.
* Car cards with manufacturer name, PI badge, stat bars; dealership by brand.

### Phase D — Real Riviera map
1. `tools/mapbake/` (Node): Overpass (roads, buildings with levels, landuse, parks, trees, water, coastline, POIs) + Terrarium DEM → `godot/assets/map/riviera.bin`: heightfield (8 m grid), road graph split at junctions with trimmed ends, **arbitrary junction polygons**, road kinds from OSM class, bridges/tunnels from tags, smoothed grade-limited profiles, building footprints + heights + style, landuse polygons, named routes for events.
2. Native: `World::build_from_bake()` replaces `layout_roads()`; junction polygon meshing + collision; building extrusion from footprints (pitched terracotta / flat roofs, cornices); landuse-driven vegetation scatter; **right-hand traffic**.
3. Events/activities rewritten on real roads: *Monaco Grand Prix* (street circuit), *Corniche Hillclimb* (Grande Corniche → La Turbie), *Autoroute A8 Sprint*, *Cap d'Ail Coast Run*, *Col de la Madone*, speed traps/drift zones/danger signs on real roads.

### Phase E — Environment realism
* Sky: HDR sky panoramas (Poly Haven CC0) cross-faded through the day + procedural sun/cloud control; ACES, warmer Riviera grading, aerial perspective fog.
* PBR textures (Poly Haven / ambientCG CC0): asphalt (with wear/patching), kerb stone, sidewalk pavers, cobbles, stucco/plaster in Riviera pastels, stone, marble, terracotta roof tile, rock, Mediterranean grass/scrub, sand.
* Buildings: facade shader v2 — real texture sets, window reveals with parallax depth, shutters, balconies with rails, cornices, shop awnings, lit interiors at night; pitched roofs.
* Vegetation: real models — **stone pine, Italian cypress, date/Canary palm, olive, plane tree**, oleander bushes, grass clumps, with LOD + impostors.
* Props: Poly Haven street lamps, bollards, hydrants, barriers, café table sets, planters; European road signs.
* Harbour: sea shader upgrade, yachts (CC-BY), quay walls.

### Phase F — European traffic
Real-model traffic (Golf, Polo/Clio/208/500-class city cars, Mercedes Sprinter/VW Transporter vans, a truck, a bus, taxis) at LOD1/LOD2 budgets, per-car paint variation, working lights; right-hand lanes.

### Phase G — Forza 4 driving feel + animation
* Targets per car from real data: 0-100 km/h, top speed, 100-0 braking (~34-38 m), steady-state lateral g (0.85-1.15 g by tyre).
* Tyres: slightly wider peak slip angles, gentler post-peak falloff, lower load sensitivity → progressive, catchable slides (Forza 4 sim-cade). Stability/traction assists tuned to feel natural.
* Visual rig driven by the sim only: body roll/pitch/heave from the chassis transform + suspension (remove the fake steer roll), wheels spin/steer/compress with the model's own wheel meshes, brake glow, exhaust.
* Camera: FH4-style chase cam spring, speed FOV, bumper/hood/cockpit.

### Phase H — Production pass
On-device (RP4 via adb) profiling to hold 60 fps; LOD/visibility ranges; APK ≤ 250 MB; all QA suites green (physics, map, menus, career); credits screen (CC-BY authors, OSM © contributors); signed APK installed on the RP4.

## 4. Progress log
(Updated by the agent as phases land.)

- **A — done (2026-09-24).** tools/carbake pipeline; 19 hero cars + 6 traffic cars baked from Sketchfab CC-BY
  (credits in each `<key>.json`); CarBuilder uses the real models (wheels spin/steer from the sim,
  lamps, glass, paint classes); paint shader rewritten without glints. The Ferrari 458 (three.js) and
  Maserati MC20 were dropped: their Sketchfab sources are gone so the licence can't be verified. The
  Ferrari SF90 "Reward Recycled" and a GTA-derived Aventador were rejected as game rips.
- **B — done.** roster.cpp with real specs for all 19 cars; save migration v3 maps the JDM keys.
  Known follow-up for G: standing-start acceleration is 10-30 % slower than the real cars.
- **F — mostly done.** Traffic = VW Polo, Skoda Superb, Volvo V60, VW T6, Mercedes Sprinter, town bus;
  right-hand driving; spinning wheels; near/far LODs. Road connectivity moves to the map graph in D.
- A parallel agent (Antigravity) edited the tree concurrently; its WIP was committed separately
  (ab5c123) and the user stopped it. A later burst of its edits (paint clear-coat, car view/stage,
  QA test) was reviewed and kept in e0d6975.
- **D — done.** Riviera baked from OSM + Terrarium DEM (a6fd3e0, e4fc94c); Monaco GP route measures
  3331 m (real 3337 m); events run on real routes.
- **E — core done (e0d6975).** Real props (Sketchfab CC-BY: plane/pine/palm/cypress/olive trees,
  shrub, boulder, street lamp, curve sign, cone; `tools/carbake/props.mjs`), Poly Haven CC0 texture
  arrays for ground/road/facades (`envtex.mjs`), European facade shader (parallax windows,
  shutters, balconies, cornices, shop awnings), clay/gravel roofs, photographic day-cycle sky
  (`skybake.mjs`, qwantani set + weather layers), depth-aware sea with shore foam.
  Remaining: yachts in the harbours, street furniture placement (benches, bins, bollards,
  hydrants), guard-rail/kerb textures, landmarks, lamp density at plazas.
- Dev loop: `tools\play.ps1 [args]` opens/restarts a play-test window; native builds work while it
  runs (the loaded DLL is moved aside).
