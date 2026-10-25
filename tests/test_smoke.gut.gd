extends GutTest
## M0 smoke test: GUT runs headless at all, and the CI gate can be trusted.

func test_gut_is_running() -> void:
	assert_true(true)


func test_string_helpers() -> void:
	var parts: Array = "res://content/core".split("/")
	assert_eq(parts[parts.size() - 1], "core")
