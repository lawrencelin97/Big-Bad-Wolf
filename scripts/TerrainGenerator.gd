extends MeshInstance3D

## Attach this to a MeshInstance3D. It builds a heightmap-based ground mesh
## with slight rolling hills and generates matching collision at runtime.

@export var width: int = 100
@export var depth: int = 100
@export var height_scale: float = 0.0       # keep LOW for "slight" hills (try 2-5)
@export var noise_frequency: float = 0.00    # lower = broader, gentler hills
@export var random_seed: int = 0             # 0 = random each run

var noise := FastNoiseLite.new()

func _ready():
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = noise_frequency
	noise.seed = random_seed if random_seed != 0 else randi()
	generate_terrain()
	add_to_group("terrain")

func generate_terrain():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var heights = []
	for z in range(depth + 1):
		heights.append([])
		for x in range(width + 1):
			var h = noise.get_noise_2d(x, z) * height_scale
			heights[z].append(h)

	for z in range(depth):
		for x in range(width):
			var h00 = heights[z][x]
			var h10 = heights[z][x + 1]
			var h01 = heights[z + 1][x]
			var h11 = heights[z + 1][x + 1]

			# center on origin so the map spans roughly -width/2..width/2
			var ox = x - width / 2.0
			var oz = z - depth / 2.0

			var v00 = Vector3(ox, h00, oz)
			var v10 = Vector3(ox + 1, h10, oz)
			var v01 = Vector3(ox, h01, oz + 1)
			var v11 = Vector3(ox + 1, h11, oz + 1)

			st.set_normal(_calc_normal(v00, v10, v01))
			st.add_vertex(v00)
			st.set_normal(_calc_normal(v10, v11, v01))
			st.add_vertex(v10)
			st.set_normal(_calc_normal(v01, v10, v11))
			st.add_vertex(v01)

			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v01)

	st.generate_normals()
	mesh = st.commit()

	# simple green material so the ground reads as ground
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.55, 0.3)
	mat.roughness = 1.0
	material_override = mat

	# collision
	var static_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	static_body.add_child(collision)
	add_child(static_body)

func _calc_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (b - a).cross(c - a).normalized()

## Returns the world-space height of the terrain at a given x,z — useful for
## placing the player/boss above the ground instead of guessing a Y value.
func get_height_at(x: float, z: float) -> float:
	return noise.get_noise_2d(x + width / 2.0, z + depth / 2.0) * height_scale
