# 3D Vehicle Models & Asset Credits

All vehicle models in Neon Touge are open-source assets adhering to permissive licensing (CC0, CC-BY 4.0, MIT). 
In compliance with the project licensing guidelines and user directive for real-world JDM vehicle representation:

## 1. Modular Vehicle Collection (`cars_big_set.glb`)
- **Source**: [nbogie/three-js-cars-3](https://github.com/nbogie/three-js-cars-3)
- **Author**: Nick Bogie / three-js-cars community
- **License**: Creative Commons Attribution 4.0 International (CC-BY 4.0)
- **Extracted Models**:
  - `sylph_s2.tscn` — Nissan Silvia Spec-R (S15)
  - `rotora_fd.tscn` — Mazda RX-7 Type R (FD3S)
  - `titan_rz.tscn` — Toyota Supra RZ (JZA80)
  - `hachi_gt.tscn` — Toyota Sprinter Trueno GT-APEX (AE86)
  - `raijin_r.tscn` — Nissan Skyline GT-R V-Spec II (BNR34)
  - `senko.tscn` — Honda NSX (NA1)
  - `kyudo_type_s.tscn` — Honda Civic Type R (EK9)
  - `tatsu_ix.tscn` — Mitsubishi Lancer Evolution IX MR
  - `mame_k.tscn` — Suzuki Cappuccino (EA11R)
  - `kaido_van.tscn` — Toyota HiAce Custom (H200)
  - `mugen_proto.tscn` — Tommykaira ZZ Proto
- **Modifications**: Re-centered origin to axle contact plane, decoupled wheels into separate simulation attachment points (`CarWheels`), tagged emissive headlight and taillight meshes for dynamic night driving and brake states.

## 2. Hypercar Reference Model (`car_concept.glb`)
- **Source**: [KhronosGroup/glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/CarConcept)
- **Author**: Khronos Group & Contributors
- **License**: Creative Commons Attribution 4.0 International (CC-BY 4.0)
- **Extracted Model**:
  - `kurogane_hyper.tscn` — Kurogane Hyper GT-Concept
- **Modifications**: Extracted chassis LOD and optimized material passes for mobile Mali-G77 GPU budget.

## 3. Procedural JDM Chassis & Aerodynamics
- **Author**: Neon Touge Project Team
- **License**: MIT / Original Project Code
- **Components**: Recaro sports bucket seats, aerodynamic teardrop side mirrors with chrome reflective faces, +0.052m blister fender arches, JDM 3-spoke sports steering rims, custom exhaust geometries.

## 4. Kenney Vehicle & Racing Kits
- **Source**: [KenneyNL/Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing) & Kenney Car Kit
- **Author**: Kenney (Kenney.nl)
- **License**: CC0 1.0 Universal (Public Domain)
- **Integrated Models**:
  - `sports_hatch.glb` — Honda Civic Type R (EK9)
  - `sports_sedan.glb` — Mitsubishi Lancer Evolution IX MR
  - `race_future.glb` — Tommykaira ZZ Proto
  - `traffic_kei.glb` — Ambient Kei car
  - `traffic_sedan.glb` — Ambient 4-door family sedan
  - `traffic_taxi.glb` — Japanese green/black taxi with roof sign
  - `traffic_van.glb` — Ambient delivery van
  - `traffic_truck.glb` — Commercial freight truck

## 5. Urban Transit Bus
- **Source**: [matthewmain/bus_derby](https://github.com/matthewmain/bus_derby)
- **Author**: Matthew Main
- **License**: MIT
- **Model**: `traffic_bus.glb` — Tokyo metropolitan transit bus
