class_name LLMSidecar
extends RefCounted
## The bundled llama-server (M12). The game starts it, reuses a healthy one that
## is already running, and kills what it started on quit. Its pid goes in
## user://llm/sidecar.pid so the next boot can kill an orphan left by a crash.
##
## For the product owner on macOS: `brew install llama.cpp` gives
## /opt/homebrew/bin/llama-server; tools/llm/fetch_runtime.sh fetches the model.

const PID_PATH := "user://llm/sidecar.pid"

var profile: Dictionary
var pid := -1
var reused := false
var error := ""


func _init(prof: Dictionary) -> void:
	profile = prof


func spec() -> Dictionary:
	return profile.get("sidecar", {})


func bin_path() -> String:
	return str(spec().get("bin", "llama-server"))


## The model path: absolute, res://, or relative to the project folder.
func model_path() -> String:
	var p := str(spec().get("model_path", ""))
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p)


func args() -> PackedStringArray:
	var s := spec()
	var a := PackedStringArray([
		"--model", model_path(),
		"--host", "127.0.0.1",
		"--port", str(int(s.get("port", 8088))),
		"--ctx-size", str(int(s.get("ctx_size", 8192))),
	])
	for x in s.get("extra_args", []):
		a.append(str(x))
	return a


## Start the server. Returns true if a process was launched.
func start() -> bool:
	kill_orphan()
	if not FileAccess.file_exists(bin_path()):
		error = "llama-server not found at " + bin_path()
		push_warning("LLMSidecar: " + error)
		return false
	if not FileAccess.file_exists(model_path()):
		error = "model not found at " + model_path() + " (run tools/llm/fetch_runtime.sh)"
		push_warning("LLMSidecar: " + error)
		return false
	pid = OS.create_process(bin_path(), args())
	if pid <= 0:
		error = "could not start llama-server"
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PID_PATH.get_base_dir()))
	var f := FileAccess.open(PID_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(str(pid))
	return true


func stop() -> void:
	if pid > 0:
		OS.kill(pid)
		pid = -1
	if FileAccess.file_exists(PID_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_PATH))


## A pid file from a previous run means that server outlived its game.
func kill_orphan() -> void:
	if not FileAccess.file_exists(PID_PATH):
		return
	var old := int(FileAccess.get_file_as_string(PID_PATH).strip_edges())
	if old > 0 and OS.is_process_running(old):
		OS.kill(old)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_PATH))
