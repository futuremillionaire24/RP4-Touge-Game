---
name: open-model-sourcer
description: >-
  Autonomous agent and workflow for discovering, vetting, downloading, optimizing, and integrating
  open-source (CC0, CC-BY 4.0, MIT) 3D realistic game models into the Godot racing game.
  Use when sourcing new realistic car models, wheels, city props, or running model inspection and extraction.
---

# Open Model Sourcer Agent & Workflow

This agent provides a complete pipeline to source high-fidelity, realistic 3D game models from verified open-source repositories and integrate them into the Neon Touge project for Godot 4.7 / Mali-G77 mobile GPU.

## Model Criteria & Technical Budget

Every model sourced for the project must meet the following mobile performance requirements:
1. **License**: Permissive open-source licenses only:
   - **CC0 (Public Domain)**: Preferred, zero attribution needed.
   - **CC-BY 4.0**: Permitted with attribution in `CREDITS.md` or model metadata.
   - **MIT / BSD**: Permitted for code/asset bundles.
   - *Strictly prohibited*: Non-commercial (CC-NC), Share-Alike (CC-SA) without review, or proprietary rips.
2. **Polygon Budget**:
   - Player cars: 15,000 – 40,000 triangles max.
   - Traffic / Rival cars: 3,000 – 15,000 triangles.
   - Wheels: 1,500 – 4,000 triangles per wheel assembly.
3. **Format**: `.glb` (binary glTF) or `.gltf`. Avoid raw FBX/OBJ when GLB is available.
4. **Hierarchy Requirements for Cars**:
   - The body chassis should be centered at ground contact level (`Y = 0` or wheel axle center).
   - Wheel meshes should either be detached as separate child nodes (`WheelFL`, `WheelFR`, `WheelRL`, `WheelRR`) so the physics sim can steer and spin them, or stripped so `CarWheels` can mount procedural rims.
   - Light meshes (`Headlights`, `Taillights`, `BrakeLights`) should be separate surfaces or child nodes with emissive materials for `CarDetails.set_light_state()`.

## Curated Open-Source Registries

Source models from these verified repositories:
- **Poly Pizza (poly.pizza)**: CC0 & CC-BY low-poly and mid-poly game assets.
- **Khronos glTF-Sample-Assets**: Industry-standard GLB reference models (e.g. `CarConcept`, `ToyCar`).
- **KenneyNL (kenney.nl / GitHub)**: CC0 public domain vehicle kits and racing starter kits.
- **Three.js Car Collections (GitHub)**: CC-BY 4.0 open game-ready vehicles (e.g. `nbogie/three-js-cars-3`).
- **OpenGameArt.org**: Permissive community 3D vehicle models.
- **Quaternius (quaternius.com)**: CC0 modular vehicle and car packs.

## Automated Sourcing Pipeline

The agent operates through the project CLI tool:

```powershell
# 1. Search online open-source registries for models matching a query
powershell -ExecutionPolicy Bypass -File tools/model_sourcer.ps1 search "sports car"

# 2. Download and import a model by URL or registry ID
powershell -ExecutionPolicy Bypass -File tools/model_sourcer.ps1 download <url_or_id> <target_filename>

# 3. Inspect geometry, vertex/triangle counts, node structure, and dimensions
powershell -ExecutionPolicy Bypass -File tools/model_sourcer.ps1 inspect res://assets/models/cars/<file>.glb

# 4. Extract individual cars from multi-car asset packs
powershell -ExecutionPolicy Bypass -File tools/model_sourcer.ps1 extract res://assets/models/cars/pack.glb <car_node_name> res://assets/models/cars/<key>.tscn

# 5. Bind the extracted model to a vehicle in CarData
powershell -ExecutionPolicy Bypass -File tools/model_sourcer.ps1 register <car_key> res://assets/models/cars/<key>.tscn
```

## Integrating Imported Models into CarBuilder

When an external model exists for a car:
1. `CarData.CARS[key]` defines `"model_path": "res://assets/models/cars/<key>.tscn"`.
2. `CarBuilder.build()` detects the model path, instances the model node, and aligns its collision bounds and wheel anchors with physics specs.
3. If external wheels exist in the model, they are bound to the `Spin` and `Steer` pivots. If not, `CarWheels.make_wheel()` attaches the high-fidelity procedural wheel assemblies.
4. `CarDetails.set_light_state()` is wired to any emissive nodes matching headlight or taillight naming conventions.
