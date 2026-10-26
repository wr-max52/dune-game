extends GutTest
## A REAL llama-server started by the game's sidecar code, one turn through it
## (scenes/m12_sidecar_trace.gd). ci.sh runs it when LLAMA_SERVER and TEST_GGUF
## are set; otherwise these tests are pending.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/m12_sidecar_trace.txt")


func _have() -> bool:
	if t.is_empty() or str(t.get("SIDECAR_STATE", "")) in ["NO_BINARY", "NO_MODEL"]:
		pending("no llama-server + model here (set LLAMA_SERVER and TEST_GGUF)")
		return false
	return true


func test_sidecar_starts_and_loads() -> void:
	if not _have():
		return
	assert_eq(t.get("SIDECAR_STATE"), "READY")


func test_a_turn_comes_from_the_model_streamed() -> void:
	if not _have():
		return
	assert_eq(t.get("TURN_SOURCE"), "model", "error: " + str(t.get("TURN_ERROR")))
	assert_eq(t.get("TURN_FALLBACKS"), "[]")
	assert_gt(int(t.get("TURN_DELTAS", 0)), 3)
	var raw := str(t.get("TURN_RAW")).replace(" ", "").replace("\t", "").replace("\n", "")
	assert_true(raw.begins_with("{\"say\":"), "say streams first: " + raw.substr(0, 40))
