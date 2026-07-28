# 3D Game Starter (Godot 4)

## Setup
1. Open Godot 4.3+, choose **Import**, and select this folder's `project.godot`.
2. Press **F5** (or the Play button) — it should run `scenes/Main.tscn` automatically.
3. WASD to move, mouse to look, Space to jump. Esc toggles mouse capture.

## What's in here
- `scripts/TerrainGenerator.gd` — attach-and-go: builds a heightmap mesh with
  slight rolling hills using Perlin noise, plus matching trimesh collision.
  Tweak `height_scale` (try 2–5 for gentle hills) and `noise_frequency`
  (lower = broader hills) in the Inspector on the `Terrain` node.
- `scripts/Player.gd` — CharacterBody3D controller: WASD movement, mouse-look
  camera on a SpringArm3D, jumping, gravity, and a basic `take_damage`/health
  loop.
- `scripts/Boss.gd` — a large, slow enemy that walks toward the player and,
  once in range, telegraphs an MMO-style ground AOE: a red disc + brighter
  edge ring appear under the boss, pulsing faster as the hit approaches
  (`telegraph_time`), then anyone still standing inside `attack_radius`
  when it resolves takes damage. The circle is built at runtime (no extra
  scene setup needed) and drawn with `no_depth_test` so it reads clearly on
  top of hilly terrain instead of clipping into slopes.
- `scenes/Main.tscn` — wires it all together: terrain, a directional light,
  one Player instance, one Boss instance.
- `scenes/Player.tscn` / `scenes/Boss.tscn` — placeholder capsule meshes for
  collision/visual so you can playtest immediately. Swap the `MeshInstance3D`
  mesh for real art whenever you're ready — the scripts don't care what mesh
  is attached.

## Known placeholders to improve first
- **Spawn height**: Player/Boss start at fixed Y positions (10 and 6). Since
  terrain height varies, they may spawn slightly above or clipped into a
  hill depending on your noise seed. Use `Terrain.get_height_at(x, z)` (added
  in `TerrainGenerator.gd`) to place them exactly on the surface at
  `_ready()` time instead of a fixed Y.
- **Boss telegraph** is a procedural disc/ring, not modeled art — it works
  well as a placeholder but you may want a decal texture (soft-edged circle
  PNG on a Decal node) for a cleaner look later. `telegraph_y_offset` on the
  Boss node controls how far below the boss origin the circle sits — tweak
  it once you swap in a real model, since the capsule's height (8m) won't
  match your character's actual collision height.
- **AOE is a simple circle only** — no cone, line, or donut-shaped attacks
  yet. If you want other telegraph shapes later, swap the `CylinderMesh`/
  `TorusMesh` in `_create_telegraph_visual()` for a flattened `BoxMesh`
  (cone/line) or a shader-based decal.
- **No AnimationPlayer** yet on either character — movement is purely
  positional. Add an AnimationTree/AnimationPlayer once you have art with
  walk/attack animations.
- **Input map** was written by hand into `project.godot` (WASD + Space). If
  a key doesn't register on your OS, just re-bind it in
  **Project > Project Settings > Input Map** in the editor — it's tolerant
  of manual edits but the UI is the reliable source of truth.

## Suggested next steps
1. Get it running and confirm you can walk around and see the boss chase you.
2. Replace capsule placeholders with real meshes (import `.glb`/`.fbx` models).
3. Add a HealthBar UI (a `ProgressBar` in a CanvasLayer) wired to
   `Player.current_health` and `Boss.current_health`.
4. Give the boss a simple state machine (idle → chase → attack → stagger)
   once you want more than one attack pattern.
