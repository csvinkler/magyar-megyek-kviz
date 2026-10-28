extends Node3D

const DATA_PATH := "res://data/counties.json"
const MAP_SCALE := 0.04
const MAP_CENTER := Vector2(380.0, 230.0)
const TILE_HEIGHT := 0.12
const SOLDIER_SPEED := 5.2
const WALK_TIME := 0.38
const MAX_LIVES := 3
const BATTLE_DURATION := 1.4

const COLOR_PENDING := Color("#d8d8c8")
const COLOR_MASTERED := Color("#5d9c7d")
const COLOR_REVIEW := Color("#cb7253")
const COLOR_BORDER := Color("#f6efd9")
const COLOR_UNIFORM := Color("#596f47")
const COLOR_HELMET := Color("#778857")

var counties: Array[Dictionary] = []
var polygons: Dictionary = {}
var county_tiles: Dictionary = {}
var county_labels: Dictionary = {}
var mastered: Dictionary = {}
var mistakes: Dictionary = {}
var review_ids: Dictionary = {}
var base_queue: Array[String] = []
var review_queue: Array[String] = []
var current_county_id := ""
var phase := "base"
var phase_answered := 0
var phase_total := 0
var score := 0
var total_wrong := 0
var lives_remaining := MAX_LIVES
var is_advancing := false
var game_finished := false
var game_over := false
var feedback_generation := 0
var walk_clock := 0.0
var last_player_county_id := ""
var player_county_id := ""
var battle_rng := RandomNumberGenerator.new()
var battle_enemy: Node3D
var sword: Node3D
var lives_label: Label

var world_root: Node3D
var player: CharacterBody3D
var soldier_model: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var camera: Camera3D

var status_label: Label
var round_label: Label
var score_label: Label
var wrong_label: Label
var question_panel: PanelContainer
var question_title: Label
var question_hint: Label
var feedback_label: Label
var review_list: VBoxContainer
var restart_button: Button
var help_label: Label


func _ready() -> void:
	_load_counties()
	_build_world()
	_build_map()
	_build_soldier()
	_build_camera_and_lighting()
	_build_hud()
	battle_rng.randomize()
	_begin_game()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		_confirm_current_county()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_advancing or game_finished or game_over:
		player.velocity = Vector3.ZERO
		player.move_and_slide()
		_animate_soldier(0.0, delta)
		return

	var horizontal := float(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) \
		- float(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A))
	var vertical := float(Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)) \
		- float(Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W))
	var input_direction := Vector2(horizontal, vertical)
	if input_direction.length_squared() > 1.0:
		input_direction = input_direction.normalized()

	player.velocity = Vector3(input_direction.x, 0.0, input_direction.y) * SOLDIER_SPEED
	player.move_and_slide()
	player.position.x = clampf(player.position.x, -15.1, 15.1)
	player.position.z = clampf(player.position.z, -9.0, 9.0)
	_animate_soldier(input_direction.length(), delta)

	if not current_county_id.is_empty() and not is_advancing:
		var county_id := _county_at_player()
		if county_id != last_player_county_id:
			last_player_county_id = county_id
			player_county_id = county_id
			_update_county_labels()
			if county_id.is_empty():
				feedback_label.text = "Lépj be egy vármegyébe, majd nyomj Entert!"
			else:
				feedback_label.text = "Megye kiválasztva. Enter: csata és ellenőrzés."
			_update_hud()


func _load_counties() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or not parsed.has("counties"):
		push_error("County map data could not be loaded.")
		return

	for raw_county: Dictionary in parsed["counties"]:
		var county := raw_county.duplicate()
		var polygon := PackedVector2Array()
		for point: Array in county["points"]:
			polygon.append(Vector2(float(point[0]), float(point[1])))
		polygons[county["id"]] = polygon
		counties.append(county)
	if counties.size() != 19:
		push_error("Expected 19 counties, got %d." % counties.size())


func _build_world() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)

	var ground := MeshInstance3D.new()
	ground.name = "MapBoard"
	var board := PlaneMesh.new()
	board.size = Vector2(36.0, 23.0)
	ground.mesh = board
	ground.position.y = -0.22
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color("#183a35")
	board_material.roughness = 0.95
	ground.material_override = board_material
	world_root.add_child(ground)


func _build_map() -> void:
	for county: Dictionary in counties:
		var polygon: PackedVector2Array = polygons[county["id"]]
		if polygon.size() < 3:
			push_error("County boundary is too short: %s." % county["name"])
			continue

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = county["id"]
		mesh_instance.mesh = _make_county_mesh(polygon)
		mesh_instance.material_override = _county_material(COLOR_PENDING)
		world_root.add_child(mesh_instance)
		county_tiles[county["id"]] = mesh_instance

		var border := MeshInstance3D.new()
		border.name = "%sBorder" % county["id"]
		border.mesh = _make_border_mesh(polygon)
		border.material_override = _unshaded_material(COLOR_BORDER)
		world_root.add_child(border)

		var seat_position := _map_to_world(Vector2(float(county["seat_x"]), float(county["seat_y"])))
		var name_label := Label3D.new()
		name_label.name = "%sName" % county["id"]
		name_label.text = county["name"]
		name_label.position = seat_position + Vector3(0.0, 0.34, 0.0)
		name_label.font_size = 30
		name_label.pixel_size = 0.005
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.outline_size = 6
		name_label.modulate = Color("#16352d")
		name_label.visible = false
		world_root.add_child(name_label)
		county_labels[county["id"]] = name_label


func _make_county_mesh(polygon: PackedVector2Array) -> ArrayMesh:
	var triangulation := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for index in range(0, triangulation.size(), 3):
		var a := polygon[triangulation[index]]
		var b := polygon[triangulation[index + 1]]
		var c := polygon[triangulation[index + 2]]
		var world_a := _map_to_world(a) + Vector3(0.0, TILE_HEIGHT, 0.0)
		var world_b := _map_to_world(b) + Vector3(0.0, TILE_HEIGHT, 0.0)
		var world_c := _map_to_world(c) + Vector3(0.0, TILE_HEIGHT, 0.0)
		if (world_b - world_a).cross(world_c - world_a).y < 0.0:
			var swap := world_b
			world_b = world_c
			world_c = swap
		surface.add_vertex(world_a)
		surface.add_vertex(world_b)
		surface.add_vertex(world_c)

	for index in polygon.size():
		var start := _map_to_world(polygon[index])
		var finish := _map_to_world(polygon[(index + 1) % polygon.size()])
		var top_start := start + Vector3(0.0, TILE_HEIGHT, 0.0)
		var top_finish := finish + Vector3(0.0, TILE_HEIGHT, 0.0)
		surface.add_vertex(top_start)
		surface.add_vertex(start)
		surface.add_vertex(finish)
		surface.add_vertex(top_start)
		surface.add_vertex(finish)
		surface.add_vertex(top_finish)

	surface.generate_normals()
	return surface.commit()


func _make_border_mesh(polygon: PackedVector2Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point: Vector2 in polygon:
		surface.add_vertex(_map_to_world(point) + Vector3(0.0, TILE_HEIGHT + 0.012, 0.0))
	surface.add_vertex(_map_to_world(polygon[0]) + Vector3(0.0, TILE_HEIGHT + 0.012, 0.0))
	return surface.commit()


func _build_soldier() -> void:
	player = CharacterBody3D.new()
	player.name = "HungarianSoldier"
	player.floor_snap_length = 0.25
	world_root.add_child(player)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.35
	collision.shape = capsule
	collision.position.y = 0.69
	player.add_child(collision)

	soldier_model = Node3D.new()
	soldier_model.name = "SoldierModel"
	player.add_child(soldier_model)

	_add_soldier_mesh(
		soldier_model,
		"UniformBody",
		CapsuleMesh.new(),
		Vector3(0.0, 0.93, 0.0),
		Vector3(0.28, 0.43, 0.22),
		COLOR_UNIFORM
	)
	_add_soldier_mesh(
		soldier_model,
		"Vest",
		BoxMesh.new(),
		Vector3(0.0, 0.98, -0.03),
		Vector3(0.4, 0.34, 0.28),
		Color("#718250")
	)
	_add_soldier_mesh(
		soldier_model,
		"Head",
		SphereMesh.new(),
		Vector3(0.0, 1.49, 0.0),
		Vector3(0.21, 0.24, 0.19),
		Color("#c69f7a")
	)
	_add_soldier_mesh(
		soldier_model,
		"Helmet",
		SphereMesh.new(),
		Vector3(0.0, 1.66, 0.0),
		Vector3(0.26, 0.17, 0.23),
		COLOR_HELMET
	)
	_add_soldier_mesh(
		soldier_model,
		"Backpack",
		BoxMesh.new(),
		Vector3(0.0, 1.02, 0.24),
		Vector3(0.34, 0.38, 0.2),
		Color("#705c3c")
	)

	left_arm = _build_limb("LeftArm", Vector3(-0.31, 1.23, 0.0), Vector3(0.11, 0.34, 0.12), COLOR_UNIFORM)
	right_arm = _build_limb("RightArm", Vector3(0.31, 1.23, 0.0), Vector3(0.11, 0.34, 0.12), COLOR_UNIFORM)
	left_leg = _build_limb("LeftLeg", Vector3(-0.14, 0.55, 0.0), Vector3(0.13, 0.34, 0.14), Color("#44513b"))
	right_leg = _build_limb("RightLeg", Vector3(0.14, 0.55, 0.0), Vector3(0.13, 0.34, 0.14), Color("#44513b"))
	soldier_model.add_child(left_arm)
	soldier_model.add_child(right_arm)
	soldier_model.add_child(left_leg)
	soldier_model.add_child(right_leg)

	_add_soldier_mesh(
		soldier_model,
		"LeftBoot",
		BoxMesh.new(),
		Vector3(-0.14, 0.17, -0.04),
		Vector3(0.17, 0.13, 0.3),
		Color("#302f27")
	)
	_add_soldier_mesh(
		soldier_model,
		"RightBoot",
		BoxMesh.new(),
		Vector3(0.14, 0.17, -0.04),
		Vector3(0.17, 0.13, 0.3),
		Color("#302f27")
	)
	sword = Node3D.new()
	sword.name = "Sword"
	sword.position = Vector3(0.35, 1.0, -0.02)
	soldier_model.add_child(sword)
	_add_soldier_mesh(
		sword,
		"Blade",
		BoxMesh.new(),
		Vector3(0.0, 0.28, 0.0),
		Vector3(0.055, 0.48, 0.07),
		Color("#c7d2cb")
	)
	_add_soldier_mesh(
		sword,
		"Grip",
		BoxMesh.new(),
		Vector3(0.0, -0.015, 0.0),
		Vector3(0.11, 0.12, 0.12),
		Color("#89683c")
	)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var start_county: Dictionary = counties[rng.randi_range(0, counties.size() - 1)]
	player.position = _map_to_world(Vector2(float(start_county["seat_x"]), float(start_county["seat_y"]))) \
		+ Vector3(0.0, TILE_HEIGHT, 0.0)


func _build_limb(limb_name: String, origin: Vector3, dimensions: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = limb_name
	pivot.position = origin
	_add_soldier_mesh(
		pivot,
		"Mesh",
		CapsuleMesh.new(),
		Vector3(0.0, -dimensions.y * 0.42, 0.0),
		dimensions,
		color
	)
	return pivot


func _add_soldier_mesh(
	parent: Node3D,
	mesh_name: String,
	mesh: PrimitiveMesh,
	origin: Vector3,
	dimensions: Vector3,
	color: Color
) -> void:
	if mesh is CapsuleMesh:
		mesh.radius = 0.5
		mesh.height = 1.0
	elif mesh is SphereMesh:
		mesh.radius = 0.5
		mesh.height = 1.0
	elif mesh is BoxMesh:
		mesh.size = Vector3.ONE
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = origin
	instance.scale = dimensions
	instance.material_override = _county_material(color)
	parent.add_child(instance)


func _build_camera_and_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47.0, -24.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	world_root.add_child(sun)

	var environment := WorldEnvironment.new()
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_SKY
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color("#bdd0c2")
	world_environment.ambient_light_energy = 0.45
	environment.environment = world_environment
	world_root.add_child(environment)

	camera = Camera3D.new()
	camera.name = "MapCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23.5
	camera.position = Vector3(0.0, 28.0, 16.0)
	camera.current = true
	world_root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(screen)

	var stats_panel := _make_panel(screen, Vector2(24.0, 22.0), Vector2(352.0, 174.0))
	var stats := _make_vbox(stats_panel)
	var title := _make_label("MEGYÉRŐL MEGYÉRE · JÁRŐRÖZÉS", 13, Color("#afc3ad"))
	stats.add_child(title)
	status_label = _make_label("Keresd meg a megadott vármegyét.", 18, Color("#f6f1dc"))
	stats.add_child(status_label)
	round_label = _make_label("ALAPKÖR · 01 / 19", 13, Color("#e8bc83"))
	stats.add_child(round_label)
	score_label = _make_label("0 pont", 12, Color("#c4d2c2"))
	stats.add_child(score_label)
	wrong_label = _make_label("Hiba: 0", 12, Color("#c4d2c2"))
	stats.add_child(wrong_label)
	lives_label = _make_label("Élet: 3 / 3", 12, Color("#f0c181"))
	stats.add_child(lives_label)

	var map_note := _make_panel(screen, Vector2.ZERO, Vector2(370.0, 88.0))
	map_note.anchor_left = 1.0
	map_note.anchor_right = 1.0
	map_note.offset_left = -394.0
	map_note.offset_right = -24.0
	map_note.offset_top = 22.0
	map_note.offset_bottom = 110.0
	var note_content := _make_vbox(map_note)
	note_content.add_child(_make_label("IRÁNYÍTÁS", 11, Color("#e8bc83")))
	help_label = _make_label("Nyilak / WASD: mozgás\nEnter: megye ellenőrzése és csata", 12, Color("#f6f1dc"))
	note_content.add_child(help_label)

	question_panel = PanelContainer.new()
	question_panel.name = "QuestionPanel"
	question_panel.anchor_left = 0.5
	question_panel.anchor_right = 0.5
	question_panel.anchor_top = 1.0
	question_panel.anchor_bottom = 1.0
	question_panel.offset_left = -244.0
	question_panel.offset_right = 244.0
	question_panel.offset_top = -210.0
	question_panel.offset_bottom = -22.0
	question_panel.visible = false
	_apply_panel_style(question_panel, Color("#173a35"), Color("#dfa65d"))
	screen.add_child(question_panel)

	var question_content := _make_vbox(question_panel)
	question_title = _make_label("Cél: vármegye neve", 22, Color("#fff9e8"))
	question_content.add_child(question_title)
	question_hint = _make_label("Vezesd a katonát a megnevezett vármegyébe.", 12, Color("#c4d2c2"))
	question_content.add_child(question_hint)
	feedback_label = _make_label("", 13, Color("#f0c181"))
	question_content.add_child(feedback_label)
	review_list = VBoxContainer.new()
	review_list.add_theme_constant_override("separation", 4)
	review_list.visible = false
	question_content.add_child(review_list)
	restart_button = Button.new()
	restart_button.text = "Új játékmenet"
	restart_button.custom_minimum_size = Vector2(0.0, 42.0)
	restart_button.visible = false
	restart_button.pressed.connect(_begin_game)
	question_content.add_child(restart_button)


func _make_panel(parent: Control, panel_position: Vector2, panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_style(panel, Color("#173a35"), Color("#668571"))
	parent.add_child(panel)
	return panel


func _apply_panel_style(panel: PanelContainer, background: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16.0
	style.content_margin_top = 13.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 13.0
	panel.add_theme_stylebox_override("panel", style)


func _make_vbox(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	parent.add_child(box)
	return box


func _make_label(label_text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _begin_game() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if is_instance_valid(battle_enemy):
		battle_enemy.queue_free()
		battle_enemy = null
	base_queue.clear()
	review_queue.clear()
	review_ids.clear()
	mastered.clear()
	mistakes.clear()
	for county: Dictionary in counties:
		base_queue.append(county["id"])
	base_queue.shuffle()
	current_county_id = ""
	phase = "base"
	phase_answered = 0
	phase_total = base_queue.size()
	score = 0
	total_wrong = 0
	lives_remaining = MAX_LIVES
	is_advancing = false
	game_finished = false
	game_over = false
	feedback_generation += 1
	question_panel.visible = false
	restart_button.visible = false
	review_list.visible = false
	feedback_label.text = ""
	if is_instance_valid(player):
		var starting_county: Dictionary = counties[rng.randi_range(0, counties.size() - 1)]
		player.position = _map_to_world(Vector2(float(starting_county["seat_x"]), float(starting_county["seat_y"])))
		last_player_county_id = starting_county["id"]
		player_county_id = starting_county["id"]
		soldier_model.rotation = Vector3.ZERO
		soldier_model.scale = Vector3.ONE
		soldier_model.position = Vector3.ZERO
		camera.size = 23.5
		camera.position = Vector3(0.0, 28.0, 16.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
	_update_county_labels()
	_advance_game()


func _advance_game() -> void:
	if game_over:
		return
	if base_queue.is_empty() and phase == "base":
		if review_queue.is_empty():
			_finish_game()
			return
		phase = "learning"
		base_queue = review_queue.duplicate()
		review_queue.clear()
		phase_answered = 0
		phase_total = base_queue.size()

	if base_queue.is_empty() and phase == "learning":
		_finish_game()
		return

	current_county_id = base_queue.pop_front()
	_update_county_colors()
	var county := _county_by_id(current_county_id)
	question_title.text = "Menj ide: %s" % county["name"]
	question_hint.text = "Vezesd a katonát a vármegyébe. Ha megérkeztél, nyomj Entert!"
	feedback_label.text = ""
	question_panel.visible = true
	_update_hud()


func _confirm_current_county() -> void:
	if is_advancing or game_finished or game_over or current_county_id.is_empty():
		return
	var entered_county_id := _county_at_player()
	if entered_county_id.is_empty():
		feedback_label.text = "Még nem állsz vármegyében. Lépj be egy területre!"
		return
	await _play_battle(entered_county_id == current_county_id)


func _play_battle(victory: bool) -> void:
	is_advancing = true
	feedback_generation += 1
	var generation := feedback_generation
	var enemy_definitions := [
		{"name": "árnylovag", "color": Color("#775960"), "kind": "knight"},
		{"name": "vadkan", "color": Color("#8f6748"), "kind": "boar"},
		{"name": "sárkány", "color": Color("#507d65"), "kind": "dragon"}
	]
	var enemy: Dictionary = enemy_definitions[battle_rng.randi_range(0, enemy_definitions.size() - 1)]
	var animation_variant := battle_rng.randi_range(0, 2)
	battle_enemy = _build_battle_enemy(enemy)
	await _focus_battle_camera()

	if victory:
		question_hint.text = "Győztes csata! A katona elfoglalta a vármegyét."
		feedback_label.text = "%s legyőzve · győzelmi mozdulat %d/3" % [enemy["name"], animation_variant + 1]
		feedback_label.add_theme_color_override("font_color", Color("#a8ddb6"))
		await _animate_battle_victory(animation_variant)
	else:
		total_wrong += 1
		lives_remaining -= 1
		mistakes[current_county_id] = int(mistakes.get(current_county_id, 0)) + 1
		if phase == "base" and not review_ids.has(current_county_id):
			review_ids[current_county_id] = true
			review_queue.append(current_county_id)
		question_hint.text = "Hibás megye! A csata elveszett, próbáld újra."
		if lives_remaining == 0:
			feedback_label.text = "%s csapása véget vetett a menetnek." % enemy["name"]
		else:
			feedback_label.text = "Sérülés: %d / %d élet maradt · vereségi jelenet %d/3" % [
				lives_remaining,
				MAX_LIVES,
				animation_variant + 1
			]
		feedback_label.add_theme_color_override("font_color", Color("#f0a184"))
		_update_hud()
		await _animate_battle_defeat(animation_variant, lives_remaining == 0)

	if generation != feedback_generation:
		return
	if is_instance_valid(battle_enemy):
		battle_enemy.queue_free()
		battle_enemy = null
	if victory:
		phase_answered += 1
		score += 1
		mastered[current_county_id] = true
		review_ids.erase(current_county_id)
		review_queue.erase(current_county_id)
		_update_county_colors()
		_update_hud()
		if lives_remaining <= 0:
			_game_over()
			return
		await get_tree().create_timer(0.25).timeout
		if generation != feedback_generation:
			return
		_advance_game()
	elif lives_remaining <= 0:
		_game_over()
	else:
		question_hint.text = "Vezesd a katonát a megadott vármegyébe, majd nyomj Entert!"
		feedback_label.text += " A cél ugyanaz marad."
		_update_hud()
	await _restore_battle_camera(generation)
	is_advancing = false


func _game_over() -> void:
	game_over = true
	is_advancing = false
	question_title.text = "JÁTÉK VÉGE"
	question_hint.text = "Elfogyott mindhárom életed. Kezdd újra a teljes játékmenetet!"
	feedback_label.text = "A következő próbánál már ismerős lesz a térkép."
	feedback_label.add_theme_color_override("font_color", Color("#f0a184"))
	_populate_review_list()
	restart_button.visible = true
	question_panel.visible = true
	_update_hud()


func _focus_battle_camera() -> void:
	if not is_instance_valid(battle_enemy):
		return
	var focus := player.position + Vector3(0.55, 0.9, 0.0)
	camera.position = player.position + Vector3(0.0, 10.0, 7.5)
	camera.look_at(focus, Vector3.UP)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(camera, "size", 8.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(battle_enemy, "position:x", player.position.x + 0.9, 0.4)
	await tween.finished


func _restore_battle_camera(generation: int) -> void:
	if generation != feedback_generation:
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(camera, "size", 23.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "position", Vector3(0.0, 28.0, 16.0), 0.45)
	await tween.finished
	if generation == feedback_generation:
		camera.look_at(Vector3.ZERO, Vector3.UP)
		soldier_model.rotation = Vector3.ZERO
		soldier_model.position = Vector3.ZERO
		soldier_model.scale = Vector3.ONE
		right_arm.rotation = Vector3.ZERO
		left_arm.rotation = Vector3.ZERO
		sword.rotation = Vector3.ZERO


func _animate_battle_victory(variant: int) -> void:
	var tween := create_tween()
	match variant:
		0:
			tween.tween_property(right_arm, "rotation:z", -1.45, 0.2)
			tween.tween_property(right_arm, "rotation:z", 1.4, 0.22)
			tween.tween_property(battle_enemy, "position:y", player.position.y + 1.2, 0.3)
		1:
			tween.tween_property(soldier_model, "position:y", 0.6, 0.24)
			tween.parallel().tween_property(right_arm, "rotation:z", -1.7, 0.25)
			tween.tween_property(soldier_model, "position:y", 0.0, 0.25)
			tween.parallel().tween_property(battle_enemy, "rotation:z", 1.5, 0.3)
		_:
			tween.tween_property(sword, "rotation:z", -1.8, 0.18)
			tween.tween_property(sword, "rotation:z", 1.8, 0.2)
			tween.parallel().tween_property(battle_enemy, "position:x", player.position.x + 2.2, 0.3)
			tween.tween_property(soldier_model, "position:y", 0.25, 0.12)
			tween.tween_property(soldier_model, "position:y", 0.0, 0.16)
	await tween.finished
	await get_tree().create_timer(BATTLE_DURATION - 0.7).timeout


func _animate_battle_defeat(variant: int, final_blow: bool) -> void:
	var tween := create_tween()
	match variant:
		0:
			tween.tween_property(battle_enemy, "position:x", player.position.x + 0.45, 0.2)
			tween.parallel().tween_property(soldier_model, "rotation:z", 0.65, 0.25)
			tween.tween_property(soldier_model, "position:y", 0.0, 0.2)
		1:
			tween.tween_property(right_arm, "rotation:z", -0.9, 0.2)
			tween.parallel().tween_property(soldier_model, "rotation:x", 0.35, 0.25)
			tween.tween_property(soldier_model, "rotation:z", -0.7, 0.25)
		_:
			tween.tween_property(battle_enemy, "position:x", player.position.x + 0.35, 0.28)
			tween.parallel().tween_property(sword, "rotation:z", 1.4, 0.25)
			tween.tween_property(soldier_model, "rotation:z", 0.85, 0.3)
	if final_blow:
		tween.tween_property(soldier_model, "position:y", -0.25, 0.35)
		tween.parallel().tween_property(soldier_model, "scale", Vector3(0.82, 0.82, 0.82), 0.35)
	else:
		tween.tween_property(soldier_model, "position:y", 0.12, 0.18)
		tween.tween_property(soldier_model, "rotation", Vector3.ZERO, 0.22)
	await tween.finished
	await get_tree().create_timer(BATTLE_DURATION - 0.7).timeout


func _build_battle_enemy(definition: Dictionary) -> Node3D:
	var enemy := Node3D.new()
	enemy.name = "BattleEnemy"
	enemy.position = player.position + Vector3(1.7, TILE_HEIGHT, 0.0)
	world_root.add_child(enemy)
	var kind: String = definition["kind"]
	var color: Color = definition["color"]
	var body := CapsuleMesh.new()
	_add_soldier_mesh(enemy, "EnemyBody", body, Vector3(0.0, 0.75, 0.0), Vector3(0.52, 0.7, 0.42), color)
	_add_soldier_mesh(
		enemy,
		"EnemyHead",
		SphereMesh.new(),
		Vector3(0.0, 1.4, -0.02),
		Vector3(0.48, 0.42, 0.42),
		color.lightened(0.18)
	)
	if kind == "dragon":
		_add_soldier_mesh(enemy, "LeftWing", BoxMesh.new(), Vector3(-0.45, 1.08, 0.2), Vector3(0.68, 0.12, 0.52), color.darkened(0.12))
		_add_soldier_mesh(enemy, "RightWing", BoxMesh.new(), Vector3(0.45, 1.08, 0.2), Vector3(0.68, 0.12, 0.52), color.darkened(0.12))
		_add_soldier_mesh(enemy, "Horn", _make_cone_mesh(), Vector3(0.0, 1.72, -0.02), Vector3(0.2, 0.35, 0.2), Color("#e3b45e"))
	elif kind == "boar":
		for side in [-1.0, 1.0]:
			_add_soldier_mesh(enemy, "Tusk%s" % side, _make_cone_mesh(), Vector3(side * 0.22, 1.35, -0.27), Vector3(0.14, 0.25, 0.14), Color("#e7d8b4"))
			_add_soldier_mesh(enemy, "Leg%s" % side, CapsuleMesh.new(), Vector3(side * 0.2, 0.2, 0.0), Vector3(0.15, 0.32, 0.15), color.darkened(0.2))
	else:
		_add_soldier_mesh(enemy, "Helmet", SphereMesh.new(), Vector3(0.0, 1.63, 0.0), Vector3(0.54, 0.19, 0.46), Color("#b38a52"))
		_add_soldier_mesh(enemy, "EnemyWeapon", BoxMesh.new(), Vector3(-0.42, 0.88, -0.1), Vector3(0.08, 0.75, 0.08), Color("#d3d8d0"))
	enemy.rotation.y = -PI * 0.5
	return enemy


func _make_cone_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	return mesh
	is_advancing = false
	_advance_game()


func _finish_game() -> void:
	game_finished = true
	is_advancing = false
	current_county_id = ""
	_update_county_colors()
	_update_hud()

	question_panel.visible = true
	question_title.text = "Járőrút teljesítve!"
	question_hint.text = "%d pont · %d hibás válasz" % [score, total_wrong]
	feedback_label.text = "Szép munka, katona. Minden vármegyét bejártál."
	feedback_label.add_theme_color_override("font_color", Color("#a8ddb6"))
	_populate_review_list()
	restart_button.visible = true


func _populate_review_list() -> void:
	for child in review_list.get_children():
		child.queue_free()
	if mistakes.is_empty():
		var no_mistakes := _make_label("Hibátlan menet — nincs mit ismételni.", 13, Color("#c4d2c2"))
		review_list.add_child(no_mistakes)
	else:
		review_list.add_child(_make_label("Ezeket a vármegyéket érdemes átismételni:", 13, Color("#e8bc83")))
		for county: Dictionary in counties:
			if not mistakes.has(county["id"]):
				continue
			var mistake_line := _make_label(
				"• %s — székhely: %s (%d hiba)" % [
					county["name"],
					county["seat"],
					mistakes[county["id"]]
				],
				12,
				Color("#f2d6c3")
			)
			review_list.add_child(mistake_line)
	review_list.visible = true


func _update_hud() -> void:
	score_label.text = "%d pont" % score
	wrong_label.text = "Hiba: %d" % total_wrong
	lives_label.text = "Élet: %d / %d" % [lives_remaining, MAX_LIVES]
	if game_finished:
		round_label.text = "MENET VÉGE"
		status_label.text = "Minden vármegye teljesítve."
	elif game_over:
		round_label.text = "JÁTÉK VÉGE"
		status_label.text = "Elfogyott mindhárom életed."
	elif phase == "learning":
		round_label.text = "TANULÓKÖR · %02d / %02d" % [phase_answered + 1, phase_total]
		status_label.text = "Csak a korábban elhibázott megyék következnek."
	else:
		round_label.text = "ALAPKÖR · %02d / %02d" % [phase_answered + 1, phase_total]
		status_label.text = "Vezesd a katonát a megadott vármegyébe."


func _update_county_colors() -> void:
	for county: Dictionary in counties:
		var county_id: String = county["id"]
		var tile: MeshInstance3D = county_tiles.get(county_id)
		if not is_instance_valid(tile):
			continue
		var color := COLOR_PENDING
		if mastered.has(county_id):
			color = COLOR_MASTERED
		if game_finished and mistakes.has(county_id):
			color = COLOR_REVIEW
		tile.material_override = _county_material(color)

	_update_county_labels()


func _update_county_labels() -> void:
	for county: Dictionary in counties:
		var county_id: String = county["id"]
		var name_label: Label3D = county_labels.get(county_id)
		if is_instance_valid(name_label):
			var completed := mastered.has(county_id) or (game_finished and mistakes.has(county_id))
			name_label.visible = completed and county_id != player_county_id


func _animate_soldier(speed_ratio: float, delta: float) -> void:
	if not is_instance_valid(soldier_model):
		return
	if speed_ratio > 0.05:
		walk_clock += delta * 2.0 * PI / WALK_TIME
		var swing := sin(walk_clock) * 0.52 * minf(speed_ratio, 1.0)
		left_arm.rotation.x = swing
		right_arm.rotation.x = -swing
		left_leg.rotation.x = -swing
		right_leg.rotation.x = swing
		soldier_model.position.y = absf(sin(walk_clock * 2.0)) * 0.035
		var facing := Vector3(player.velocity.x, 0.0, player.velocity.z)
		if facing.length_squared() > 0.01:
			soldier_model.rotation.y = lerp_angle(
				soldier_model.rotation.y,
				atan2(-facing.x, -facing.z),
				minf(delta * 12.0, 1.0)
			)
	else:
		left_arm.rotation.x = move_toward(left_arm.rotation.x, 0.0, delta * 4.0)
		right_arm.rotation.x = move_toward(right_arm.rotation.x, 0.0, delta * 4.0)
		left_leg.rotation.x = move_toward(left_leg.rotation.x, 0.0, delta * 4.0)
		right_leg.rotation.x = move_toward(right_leg.rotation.x, 0.0, delta * 4.0)
		soldier_model.position.y = move_toward(soldier_model.position.y, 0.0, delta * 0.12)


func _map_to_world(point: Vector2) -> Vector3:
	return Vector3((point.x - MAP_CENTER.x) * MAP_SCALE, 0.0, (point.y - MAP_CENTER.y) * MAP_SCALE)


func _county_by_id(county_id: String) -> Dictionary:
	for county: Dictionary in counties:
		if county["id"] == county_id:
			return county
	return {}


func _county_at_player() -> String:
	var map_point := Vector2(player.position.x / MAP_SCALE, player.position.z / MAP_SCALE) + MAP_CENTER
	for county: Dictionary in counties:
		var county_id: String = county["id"]
		if Geometry2D.is_point_in_polygon(map_point, polygons[county_id]):
			return county_id
	return ""


func _county_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material := _county_material(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
