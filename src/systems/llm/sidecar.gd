class_name LLMSidecar
extends RefCounted
## The bundled llama-server (M12). The game starts it, reuses a healthy one that
## is already running, and kills what it started on quit. Its pid goes in
## user://llm/sidecar.pid so the next boot can kill an orphan left by a crash.
##
## Finding the binary: the configured path first, then $LLAMA_SERVER, then the
## project's runtime/bin, the usual install folders (Homebrew on Apple Silicon and
## Intel, ~/.local/bin, a llama.cpp build in your home folder), then your login
## shell's PATH (an app started from the Dock or the editor does not see the PATH
## your terminal has). Whatever happens, `state` and `reason()` say why, in words.
##
## The server's own output goes to user://logs/llama-server.log (the place to look
## when it starts and then dies: wrong flags, not enough memory, a bad model file).

const PID_PATH := "user://llm/sidecar.pid"
const LOG_PATH := "user://logs/llama-server.log"

enum State { IDLE, NO_BINARY, NO_MODEL, STARTING, READY, REUSED, CRASHED, FAILED }

var profile: Dictionary
var pid := -1
var reused := false
var error := ""
var state := State.IDLE
var bin_found := ""
var model_found := ""
var searched: PackedStringArray = []
var started_ms := 0
var log_tail: PackedStringArray = []

var _stdio: FileAccess
var _stderr: FileAccess
var _log: FileAccess


func _init(prof: Dictionary) -> void:
	profile = prof


func spec() -> Dictionary:
	return profile.get("sidecar", {})


func exe_name() -> String:
	return "llama-server.exe" if OS.get_name() == "Windows" else "llama-server"


## Every place we will look, in order (the login-shell lookup comes after these).
func candidates() -> PackedStringArray:
	var home := OS.get_environment("HOME") if OS.has_environment("HOME") else OS.get_environment("USERPROFILE")
	var out := PackedStringArray()
	var configured := str(spec().get("bin", ""))
	if configured != "":
		out.append(configured)
	if OS.has_environment("LLAMA_SERVER"):
		out.append(OS.get_environment("LLAMA_SERVER"))
	out.append(ProjectSettings.globalize_path("res://").path_join("runtime/bin/" + exe_name()))
	for d in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home.path_join(".local/bin"),
			home.path_join("llama.cpp/build/bin"), home.path_join("src/llama.cpp/build/bin")]:
		var p: String = d.path_join(exe_name())
		if not out.has(p):
			out.append(p)
	return out


## Find llama-server. Returns "" (and sets state NO_BINARY) when it is nowhere.
func find_bin() -> String:
	searched = candidates()
	for p in searched:
		if p != "" and FileAccess.file_exists(p):
			bin_found = p
			return p
	var via_shell := _shell_lookup()
	if via_shell != "":
		bin_found = via_shell
		return via_shell
	state = State.NO_BINARY
	error = "llama-server is not installed (looked in %s and your PATH)" % ", ".join(searched)
	return ""


func _shell_lookup() -> String:
	var out: Array = []
	if OS.get_name() == "Windows":
		OS.execute("where", [exe_name()], out)
	else:
		for sh in ["/bin/zsh", "/bin/bash", "/bin/sh"]:
			if FileAccess.file_exists(sh):
				OS.execute(sh, ["-lc", "command -v " + exe_name()], out)
				break
	var line := (str(out[0]) if not out.is_empty() else "").strip_edges().split("\n")[0].strip_edges()
	return line if line != "" and FileAccess.file_exists(line) else ""


## The model: the configured path, or any .gguf in runtime/models/.
func configured_model() -> String:
	var p := str(spec().get("model_path", ""))
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p == "" or p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p)


func find_model() -> String:
	var p := str(spec().get("model_path", ""))
	var full := configured_model()
	if p != "" and FileAccess.file_exists(full):
		model_found = full
		return full
	var dir := ProjectSettings.globalize_path("res://").path_join("runtime/models")
	var da := DirAccess.open(dir)
	if da != null:
		for f in da.get_files():
			if f.ends_with(".gguf"):
				model_found = dir.path_join(f)
				return model_found
	state = State.NO_MODEL
	error = "no model file at %s (run tools/llm/fetch_runtime.sh)" % full
	return ""


func model_path() -> String:
	return model_found if model_found != "" else configured_model()


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
	if find_bin() == "":
		push_warning("LLMSidecar: " + error)
		return false
	if find_model() == "":
		push_warning("LLMSidecar: " + error)
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH.get_base_dir()))
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	var r: Dictionary = OS.execute_with_pipe(bin_found, args(), false)
	if r.is_empty() or int(r.get("pid", -1)) <= 0:
		# Fall back to a plain process (no log capture).
		pid = OS.create_process(bin_found, args())
	else:
		pid = int(r.pid)
		_stdio = r.get("stdio")
		_stderr = r.get("stderr")
	if pid <= 0:
		state = State.FAILED
		error = "could not start " + bin_found
		return false
	state = State.STARTING
	started_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PID_PATH.get_base_dir()))
	var f := FileAccess.open(PID_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(str(pid))
	print("LLMSidecar: started %s (pid %d) with %s" % [bin_found, pid, model_found.get_file()])
	return true


## Call every frame or so: drains the server's output into the log and notices a
## server that died.
func poll() -> void:
	for pipe in [_stdio, _stderr]:
		if pipe == null:
			continue
		var chunk: PackedByteArray = (pipe as FileAccess).get_buffer(65536)
		if chunk.size() > 0:
			var text := chunk.get_string_from_utf8()
			if _log != null:
				_log.store_string(text)
				_log.flush()
			for line in text.split("\n"):
				if line.strip_edges() != "":
					log_tail.append(line.strip_edges())
			while log_tail.size() > 20:
				log_tail.remove_at(0)
	if state == State.STARTING or state == State.READY:
		if pid > 0 and not OS.is_process_running(pid):
			state = State.CRASHED
			var last := log_tail[log_tail.size() - 1] if not log_tail.is_empty() else "no output"
			error = "llama-server exited (%s). Full log: %s" % [last, ProjectSettings.globalize_path(LOG_PATH)]
			push_warning("LLMSidecar: " + error)
			pid = -1


func mark_ready() -> void:
	if state == State.STARTING:
		state = State.READY
		print("LLMSidecar: ready after %.1f s" % ((Time.get_ticks_msec() - started_ms) / 1000.0))


func loading_seconds() -> float:
	return (Time.get_ticks_msec() - started_ms) / 1000.0 if state == State.STARTING else 0.0


## One line for players and the debug overlay.
func reason() -> String:
	match state:
		State.NO_BINARY:
			return "llama-server not installed. Mac: brew install llama.cpp"
		State.NO_MODEL:
			return "no model file. Run tools/llm/fetch_runtime.sh"
		State.STARTING:
			return "loading %s (%.0f s)" % [model_found.get_file(), loading_seconds()]
		State.READY:
			return "ready (%s)" % model_found.get_file()
		State.REUSED:
			return "ready (a server that was already running)"
		State.CRASHED, State.FAILED:
			return error
	return "not started"


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
