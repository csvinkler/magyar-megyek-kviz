extends Node

const MainGame = preload("res://scripts/main.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MainGame.new()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	assert(game.counties.size() == 19, "The map should contain all 19 counties.")
	assert(game.county_tiles.size() == 19, "All county meshes should be created.")
	assert(game.world_root.find_child("TargetBeacon", true, false) == null, "The map must not mark the target.")
	assert(game.lives_remaining == 3, "A new game should start with three lives.")

	game.base_queue.clear()
	game.base_queue.append("fejer")
	game.review_queue.clear()
	game.review_ids.clear()
	game.mastered.clear()
	game.mistakes.clear()
	game.phase = "base"
	game.phase_answered = 0
	game.phase_total = 2
	game.current_county_id = "pest"
	_set_player_county(game, "pest")
	game.question_title.text = "Menj ide: Pest"
	game._update_county_colors()
	assert(not game.mastered.has("pest"), "Standing in the target should not automatically complete it.")
	assert(not game.county_labels["pest"].visible, "The county under the soldier should not show its name.")

	await game._confirm_current_county()
	assert(game.mastered.has("pest"), "Enter should confirm a correct county after the battle.")
	assert(game.score == 1, "A confirmed correct county should award one point.")
	assert(game.lives_remaining == 3, "A win should not consume a life.")
	assert(game.county_tiles["pest"].material_override.albedo_color == game.COLOR_MASTERED, "A won battle should turn the county green.")
	assert(not game.county_labels["pest"].visible, "The mastered county name should stay hidden beneath the soldier.")
	assert(game.current_county_id == "fejer", "The next target should be displayed after winning.")

	_set_player_county(game, "pest")
	assert(game.lives_remaining == 3, "Entering a wrong county should not count until Enter is pressed.")
	await game._confirm_current_county()
	assert(game.lives_remaining == 2, "A wrong confirmed county should cost one life.")
	assert(game.total_wrong == 1, "A wrong confirmed county should increment the mistake counter.")
	assert(not game.mastered.has("fejer"), "A wrong county should not turn the target green.")
	await game._confirm_current_county()
	assert(game.lives_remaining == 1, "The second mistake should leave one life.")
	await game._confirm_current_county()
	assert(game.game_over, "The third mistake should end the game.")
	assert(game.lives_remaining == 0, "Game over should happen when all three lives are used.")
	assert(game.restart_button.visible, "Game over should offer a restart.")

	game.restart_button.pressed.emit()
	assert(not game.game_over, "Restart should begin a new game.")
	assert(game.lives_remaining == 3, "Restart should restore all three lives.")
	assert(game.score == 0, "Restart should reset the score.")
	print("Godot smoke test passed: Enter confirmation, labels, battles, three lives, game over, and restart.")
	get_tree().quit(0)


func _set_player_county(game: Node, county_id: String) -> void:
	var county: Dictionary = game._county_by_id(county_id)
	game.player.position = game._map_to_world(Vector2(float(county["seat_x"]), float(county["seat_y"])))
	game.player_county_id = county_id
	game.last_player_county_id = county_id
	game._update_county_labels()
