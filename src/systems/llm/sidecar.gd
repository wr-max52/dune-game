class_name LLMSidecar
extends RefCounted
## The bundled llama-server (M12). The game starts it, reuses one that is
## already listening (including one still loading), and kills only the child it
## started on quit. A PID saved by another game process is not kill authority.
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
const PORT_PROBE_TIMEOUT_MS := 2000

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
var search := true                 ## false: only the configured path (tests)

var _stdio: FileAccess
var _stderr: FileAccess
var _log: FileAccess
var _port_probe: StreamPeerTCP


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
	if not search:
		return out
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
	var via_shell := _shell_lookup() if search else ""
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


## Begin startup without blocking a frame. A listening port means wait for the
## service's health check, not spawn a second server or kill a saved PID.
func start() -> bool:
	if state in [State.STARTING, State.READY, State.REUSED]:
		return true
	if find_bin() == "":
		push_warning("LLMSidecar: " + error)
		return false
	if find_model() == "":
		push_warning("LLMSidecar: " + error)
		return false
	var port := int(spec().get("port", 8088))
	if port < 1 or port > 65535:
		state = State.FAILED
		error = "invalid local server port: %d" % port
		return false
	error = ""
	reused = false
	state = State.STARTING
	started_ms = Time.get_ticks_msec()
	_port_probe = StreamPeerTCP.new()
	var err := _port_probe.connect_to_host("127.0.0.1", port)
	if err != OK:
		_close_probe()
		state = State.FAILED
		error = "could not check local server port: " + error_string(err)
		return false
	return true


func _poll_port() -> void:
	var err := _port_probe.poll()
	var status := _port_probe.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_close_probe()
		reused = true
		print("LLMSidecar: local port is occupied; waiting for existing server health (no second process)")
	elif status in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE] or err != OK:
		_close_probe()
		_launch()
	elif Time.get_ticks_msec() - started_ms > PORT_PROBE_TIMEOUT_MS:
		_close_probe()
		state = State.FAILED
		error = "local port check timed out; no duplicate server was started"


func _launch() -> bool:
	_close_pipes()
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
	if _port_probe != null:
		_poll_port()
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
			_remove_owned_pid_file(pid)
			pid = -1
			_close_pipes()
		elif reused and loading_seconds() > maxf(1.0, float(spec().get("startup_timeout_s", 180.0))):
			state = State.FAILED
			error = "local port is occupied but server health did not become ready; no duplicate server was started"


func mark_ready() -> void:
	if state == State.STARTING:
		# A health response can arrive while the TCP probe is still pending.
		if _port_probe != null:
			_close_probe()
			reused = true
		state = State.REUSED if reused else State.READY
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
	_close_probe()
	if pid > 0 and not reused:
		if OS.is_process_running(pid):
			OS.kill(pid)
		_remove_owned_pid_file(pid)
	pid = -1
	_close_pipes()
	reused = false
	state = State.IDLE


func _close_probe() -> void:
	if _port_probe != null:
		_port_probe.disconnect_from_host()
		_port_probe = null


## Do not delete a marker another game instance replaced while we were running.
func _remove_owned_pid_file(owned_pid: int) -> void:
	if FileAccess.file_exists(PID_PATH) and FileAccess.get_file_as_string(PID_PATH).strip_edges() == str(owned_pid):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_PATH))


func _close_pipes() -> void:
	for pipe in [_stdio, _stderr, _log]:
		if pipe != null:
			(pipe as FileAccess).close()
	_stdio = null
	_stderr = null
	_log = null
