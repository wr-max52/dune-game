extends GutTest
## Issue #113: the save remembers which planet you were on and where on it, and a
## run opened from that save resumes there (once).

const SaveSystemT := preload("res://src/systems/save/save_system.gd")
const PATH := "user://test_save_where.json"


func after_each() -> void:
	GameFlow.reset()
	GameFlow.resumed = false
	GameFlow.resume_pos = Vector3.INF
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _write(planet: String, pos, has_pos := true) -> void:
	var s := SaveSystemT.new()
	s.new_game()
	s.set_where(planet, pos, has_pos)
	s.save_to(PATH)


func test_round_trip() -> void:
	_write("grit_station", Vector3(12.5, 3.0, -40.0))
	var w := SaveSystemT.where_in(PATH)
	assert_eq(str(w.planet), "grit_station")
	assert_eq(w.pos, [12.5, 3.0, -40.0])


func test_resumes_on_the_saved_planet_and_spot_once() -> void:
	_write("grit_station", Vector3(12.5, 3.0, -40.0))
	assert_true(GameFlow.resume_from_save(PATH))
	assert_eq(GameFlow.current_planet_id(), "grit_station")
	assert_eq(GameFlow.take_resume_pos(), Vector3(12.5, 3.0, -40.0))
	assert_eq(GameFlow.take_resume_pos(), Vector3.INF, "the spot is taken once")
	GameFlow.planet_id = ""
	assert_false(GameFlow.resume_from_save(PATH), "once per run")
	assert_eq(GameFlow.current_planet_id(), PlanetGen.home_id())


func test_home_planet_and_planet_without_a_spot() -> void:
	_write(PlanetGen.home_id(), Vector3.ZERO, false)
	assert_true(GameFlow.resume_from_save(PATH))
	assert_eq(GameFlow.planet_id, "", "the home planet is the default")
	assert_eq(GameFlow.take_resume_pos(), Vector3.INF, "no spot saved: the spawn")


func test_old_save_or_unknown_planet_changes_nothing() -> void:
	var s := SaveSystemT.new()
	s.new_game()
	s.save_to(PATH)
	assert_false(GameFlow.resume_from_save(PATH))
	GameFlow.resumed = false
	_write("no_such_planet", Vector3.ONE)
	assert_false(GameFlow.resume_from_save(PATH))
	assert_eq(GameFlow.current_planet_id(), PlanetGen.home_id())
