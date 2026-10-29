class_name LLMService
extends Node
## The LLM pipe (M12). Async, streaming, never blocks a frame, never shows the
## player an error.
##
##   var id := llm.chat(messages, { "schema": schema })
##   llm.delta.connect(func(turn, text): ...)        # raw reply text as it streams
##   llm.finished.connect(func(turn, result): ...)   # { ok, text, provider, model,
##                                                   #   ms_first_token, ms_total, usage,
##                                                   #   fell_back_from, stalled, error }
##
## Providers are tried in chain order (config). A provider is skipped when its
## health check says it is down or its circuit is open (3 failures in 60 s opens it
## for 2 minutes). A provider that cannot connect, answers with an error, or does
## not produce a first token in time is abandoned for the next one (`fallback` is
## emitted so the cantina owner can do a "thinking" beat). A stream that stalls after
## it started keeps what it said. When everything fails, finished() reports
## ok = false and the caller uses its canned lines.
##
## Streaming uses HTTPClient polled in _process, because HTTPRequest buffers the
## whole body and the point is to get the first words on screen fast.

signal delta(turn_id: int, text: String)
signal finished(turn_id: int, result: Dictionary)
signal fallback(turn_id: int, from_provider: String, reason: String)
signal status_changed

var config: LLMConfig
var providers: Dictionary = {}       ## id -> LLMProvider
var mode := "auto"                   ## auto | local | ollama | cloud | scripted
var health: Dictionary = {}          ## id -> { up: bool, checked_ms, error }
var sidecar: LLMSidecar
var last_result: Dictionary = {}

var _fail_times: Dictionary = {}     ## id -> [ms]
var _open_until: Dictionary = {}     ## id -> ms
var _turns: Dictionary = {}          ## turn id -> state
var _next_id := 1
var _recheck_left := 0.0
var _health_reqs: Dictionary = {}    ## id -> HTTPRequest
var _sidecar_start_pending := false


func _ready() -> void:
	name = "LLM" if name == "" or name.begins_with("@") else name
	set_process(true)


## Load config and build providers. `scripted` (a ScriptedProvider, or an Array
## of them for a fallback chain) forces the CI providers.
var scripted_chain: Array = []

func configure(cfg: LLMConfig, scripted = null) -> void:
	config = cfg
	providers.clear()
	for id in cfg.data.get("profiles", {}):
		providers[id] = make_provider(id, cfg.profile(id), cfg.api_key(id))
	if scripted != null:
		scripted_chain.clear()
		for sp in (scripted if scripted is Array else [scripted]):
			providers[sp.id] = sp
			scripted_chain.append(sp.id)
		mode = "scripted"
	_recheck_left = 0.0


static func make_provider(id: String, prof: Dictionary, key: String) -> LLMProvider:
	match str(prof.get("type", "openai_compat")):
		"anthropic":
			return AnthropicProvider.new(id, prof, key)
	return OpenAICompatProvider.new(id, prof, key)


## Start the bundled llama-server if the local profile wants one (reusing a
## healthy server that is already up).
func start_sidecar() -> void:
	if config == null or _sidecar_start_pending:
		return
	if sidecar != null and sidecar.state in [LLMSidecar.State.STARTING, LLMSidecar.State.READY, LLMSidecar.State.REUSED]:
		return
	var prof := config.profile("local")
	if not bool(prof.get("sidecar", {}).get("enabled", false)):
		return
	if sidecar != null:
		sidecar.stop()
	sidecar = LLMSidecar.new(prof)
	_sidecar_start_pending = true
	_check_health("local", func(ok: bool):
		_sidecar_start_pending = false
		if ok:
			sidecar.reused = true
			sidecar.state = LLMSidecar.State.REUSED
		elif sidecar.start():
			# Loading a big model takes a while; do not count it as down meanwhile.
			health.erase("local")
		status_changed.emit())


## The chain for the current mode, minus anything down or tripped.
func active_chain() -> Array:
	var base: Array
	match mode:
		"scripted":
			return scripted_chain.filter(func(id): return Time.get_ticks_msec() >= int(_open_until.get(id, 0)))
		"auto":
			base = config.chain() if config != null else []
		_:
			base = [mode]
	var out: Array = []
	var now := Time.get_ticks_msec()
	for id in base:
		if not providers.has(id) or not config.usable(id):
			continue
		if now < int(_open_until.get(id, 0)):
			continue
		if health.has(id) and not bool(health[id].get("up", true)):
			continue
		out.append(id)
	return out


func set_mode(m: String) -> void:
	mode = m
	status_changed.emit()


## Cycle auto -> local -> cloud -> auto (Shift+F10 at the bar, for A/B tests).
func cycle_mode() -> String:
	var order := ["auto", "local", "cloud"]
	set_mode(order[(order.find(mode) + 1) % order.size()])
	return mode


func chat(messages: Array, opts: Dictionary = {}) -> int:
	var id := _next_id
	_next_id += 1
	var chain := active_chain()
	var t := {
		"id": id, "messages": messages, "opts": opts, "chain": chain, "idx": -1,
		"started": Time.get_ticks_msec(), "fell_back_from": [], "a": {},
	}
	_turns[id] = t
	_next_attempt(t, "")
	return id


func cancel(turn_id: int) -> void:
	var t: Dictionary = _turns.get(turn_id, {})
	if t.is_empty():
		return
	_close(t)
	_turns.erase(turn_id)


func busy() -> bool:
	return not _turns.is_empty()


## Why each provider is or is not answering, in plain words, plus a summary line.
## { lines: [..], summary: String, any_up: bool }
func brain_report() -> Dictionary:
	var lines: PackedStringArray = []
	var chain := active_chain()
	var order: Array = scripted_chain if mode == "scripted" else (config.chain() if mode == "auto" and config != null else [mode])
	for id in order:
		var why := ""
		if scripted_chain.has(id):
			why = "scripted (tests)"
		elif not providers.has(id):
			why = "no such profile"
		elif config != null and not bool(config.profile(id).get("enabled", true)):
			why = "off" + (" (no key)" if config.api_key(id) == "" else "") + ". F10 to turn it on"
		elif config != null and not config.usable(id):
			why = "needs an API key. F10 or the DUNE_LLM_KEY env var"
		elif circuit_open(id):
			why = "paused after repeated failures (retrying in under 2 min)"
		elif id == "local" and sidecar != null and sidecar.state != LLMSidecar.State.READY and sidecar.state != LLMSidecar.State.REUSED:
			why = sidecar.reason()
		elif health.has(id) and not bool(health[id].get("up", true)):
			why = "not running at " + str(config.profile(id).get("base_url", "")) if id != "local" else "not answering at " + str(config.profile(id).get("base_url", ""))
		elif chain.has(id):
			why = "ready (%s)" % providers[id].model() if health.has(id) else "not checked yet"
		lines.append("%s: %s" % [id, why])
	var any_up := not chain.is_empty()
	var loading := sidecar != null and sidecar.state == LLMSidecar.State.STARTING
	var summary := ""
	if loading:
		summary = "Her brain is loading (%s). Canned lines until then." % sidecar.reason()
	elif not any_up:
		summary = "No brain: canned lines only. " + (lines[0] if not lines.is_empty() else "")
	else:
		summary = "Brain: " + str(chain[0])
	return { "lines": Array(lines), "summary": summary, "any_up": any_up and not (loading and chain == ["local"]) }


func status() -> Dictionary:
	var out := {}
	var now := Time.get_ticks_msec()
	for id in providers:
		var h: Dictionary = health.get(id, {})
		out[id] = {
			"usable": scripted_chain.has(id) or (config != null and config.usable(id)),
			"up": bool(h.get("up", true)), "checked": h.has("up"),
			"circuit_open": now < int(_open_until.get(id, 0)),
			"model": providers[id].model(), "error": str(h.get("error", "")),
		}
	return out


# ------------------------------------------------------------------ attempts

func _next_attempt(t: Dictionary, reason: String) -> void:
	if t.idx >= 0 and reason != "":
		var from: String = t.chain[t.idx]
		t.fell_back_from.append({ "provider": from, "reason": reason })
		_record_failure(from)
		fallback.emit(t.id, from, reason)
	_close(t)
	t.idx += 1
	if t.idx >= t.chain.size():
		_finish(t, false, reason if reason != "" else "no provider")
		return
	var pid: String = t.chain[t.idx]
	var prov: LLMProvider = providers[pid]
	var a := {
		"provider": pid, "phase": "start", "t0": Time.get_ticks_msec(), "first_at": -1,
		"last_data": -1, "text": "", "usage": {}, "sse": SSEStream.new(), "body": PackedByteArray(),
		"timeout": config.first_token_timeout_ms(pid) if config != null else 2500,
	}
	t.a = a
	if prov is ScriptedProvider:
		a.phase = "scripted"
		a.script = (prov as ScriptedProvider).next_reply()
		(prov as ScriptedProvider).requests.append(t.messages)
		a.sent = 0
		return
	var req := prov.build_request(t.messages, _gen_opts(t.opts))
	var u := parse_url(str(req.get("url", "")))
	if u.is_empty():
		_next_attempt(t, "bad url")
		return
	a.req = req
	a.url = u
	var c := HTTPClient.new()
	var err := c.connect_to_host(u.host, u.port, TLSOptions.client() if u.tls else null)
	if err != OK:
		_next_attempt(t, "connect")
		return
	a.client = c
	a.phase = "connecting"


func _gen_opts(opts: Dictionary) -> Dictionary:
	var g: Dictionary = config.gen() if config != null else {}
	var o := opts.duplicate()
	if not o.has("temperature"):
		o.temperature = float(g.get("temperature", 0.8))
	if not o.has("max_tokens"):
		o.max_tokens = int(g.get("max_tokens", 220))
	return o


func _process(dt: float) -> void:
	for id in _turns.keys():
		if _turns.has(id):
			_step(_turns[id])
	if sidecar != null:
		sidecar.poll()
		if sidecar.state == LLMSidecar.State.STARTING and not _health_reqs.has("local"):
			_check_health("local", func(ok: bool):
				if ok:
					sidecar.mark_ready()
					status_changed.emit())
	_recheck_left -= dt
	if _recheck_left <= 0.0 and config != null:
		_recheck_left = float(config.data.get("health_recheck_s", 30))
		for pid in providers:
			if not scripted_chain.has(pid) and config.usable(pid):
				_check_health(pid)


func _step(t: Dictionary) -> void:
	var a: Dictionary = t.a
	var now := Time.get_ticks_msec()
	var g: Dictionary = config.gen() if config != null else {}
	if now - int(t.started) > int(g.get("total_timeout_ms", 20000)):
		if str(a.get("text", "")) != "":
			_finish(t, true, "", true)
		else:
			_next_attempt(t, "total timeout")
		return
	if a.get("first_at", -1) < 0 and now - int(a.t0) > int(a.timeout):
		_next_attempt(t, "timeout")
		return
	if a.get("first_at", -1) >= 0 and now - int(a.last_data) > int(g.get("stall_ms", 3000)):
		_finish(t, true, "", true)
		return
	match str(a.phase):
		"scripted":
			_step_scripted(t, a, now)
		"connecting":
			var c: HTTPClient = a.client
			c.poll()
			match c.get_status():
				HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
					pass
				HTTPClient.STATUS_CONNECTED:
					var err := c.request(HTTPClient.METHOD_POST if str(a.req.method) == "POST" else HTTPClient.METHOD_GET,
						a.url.path, a.req.headers, str(a.req.get("body", "")))
					if err != OK:
						_next_attempt(t, "request")
						return
					a.phase = "requesting"
				_:
					_next_attempt(t, "connect")
		"requesting":
			var c: HTTPClient = a.client
			c.poll()
			var st := c.get_status()
			if st == HTTPClient.STATUS_REQUESTING:
				return
			if st == HTTPClient.STATUS_BODY or st == HTTPClient.STATUS_CONNECTED:
				var code := c.get_response_code()
				if code != 200:
					a.phase = "error_body"
					a.code = code
					return
				a.phase = "body"
				return
			_next_attempt(t, "connection lost")
		"error_body":
			var c: HTTPClient = a.client
			c.poll()
			if c.get_status() == HTTPClient.STATUS_BODY:
				a.body.append_array(c.read_response_body_chunk())
				return
			var msg := (a.body as PackedByteArray).get_string_from_utf8().substr(0, 200)
			_next_attempt(t, "http %d %s" % [int(a.code), msg])
		"body":
			var c: HTTPClient = a.client
			c.poll()
			var prov: LLMProvider = providers[a.provider]
			var st := c.get_status()
			if st == HTTPClient.STATUS_BODY:
				var chunk := c.read_response_body_chunk()
				if chunk.size() > 0:
					for ev in (a.sse as SSEStream).feed(chunk):
						if _consume(t, a, prov, ev, now):
							return
				return
			for ev in (a.sse as SSEStream).flush():
				if _consume(t, a, prov, ev, now):
					return
			if str(a.text) != "":
				_finish(t, true, "")
			else:
				_next_attempt(t, "empty")


## Returns true if the turn ended.
func _consume(t: Dictionary, a: Dictionary, prov: LLMProvider, ev: Dictionary, now: int) -> bool:
	var u := prov.parse_usage(ev)
	for k in u:
		a.usage[k] = u[k]
	if bool(ev.get("done", false)):
		if str(a.text) != "":
			_finish(t, true, "")
		else:
			_next_attempt(t, "empty")
		return true
	var j = ev.get("json")
	if j is Dictionary and j.has("error"):
		_next_attempt(t, "stream error " + str(j.error).substr(0, 120))
		return true
	var d := prov.parse_stream_delta(ev)
	if d != "":
		if int(a.first_at) < 0:
			a.first_at = now
		a.last_data = now
		a.text = str(a.text) + d
		delta.emit(t.id, d)
	return false


func _step_scripted(t: Dictionary, a: Dictionary, now: int) -> void:
	var s: Dictionary = a.script
	if s.has("fail"):
		match str(s.fail):
			"timeout":
				pass                  # wait for the first-token timeout to fire
			"stall":
				if int(a.first_at) < 0:
					a.first_at = now
					a.last_data = now
					a.text = "{\"say\": \"Well, the thing about"
					delta.emit(t.id, a.text)
			_:
				_next_attempt(t, str(s.fail))
		return
	var text := str(s.get("text", ""))
	var ms_first := int(s.get("ms_first", 0))
	var ms_per := int(s.get("ms_per_chunk", 0))
	var chunk := maxi(1, int(s.get("chunk", 12)))
	var since := now - int(a.t0)
	if since < ms_first:
		return
	# How many chunks are due by now (at least one per frame so CI is quick).
	var due := 1 if ms_per <= 0 else int((since - ms_first) / ms_per) + 1
	var target := mini(text.length(), maxi(int(a.sent) + chunk, due * chunk))
	if target > int(a.sent):
		var piece := text.substr(int(a.sent), target - int(a.sent))
		a.sent = target
		if int(a.first_at) < 0:
			a.first_at = now
		a.last_data = now
		a.text = str(a.text) + piece
		delta.emit(t.id, piece)
	if int(a.sent) >= text.length():
		a.usage = s.get("usage", { "in": 0, "out": text.length() / 4 })
		_finish(t, true, "")


func _finish(t: Dictionary, ok: bool, error: String, stalled: bool = false) -> void:
	var a: Dictionary = t.a
	var now := Time.get_ticks_msec()
	var pid := str(a.get("provider", ""))
	var r := {
		"ok": ok, "text": str(a.get("text", "")), "provider": pid,
		"model": providers[pid].model() if providers.has(pid) else "",
		"ms_first_token": int(a.first_at) - int(t.started) if int(a.get("first_at", -1)) >= 0 else -1,
		"ms_total": now - int(t.started), "usage": a.get("usage", {}),
		"fell_back_from": t.fell_back_from, "stalled": stalled, "error": error,
	}
	_close(t)
	_turns.erase(t.id)
	last_result = r
	finished.emit(t.id, r)


func _close(t: Dictionary) -> void:
	var a: Dictionary = t.get("a", {})
	if a.get("client") is HTTPClient:
		(a.client as HTTPClient).close()
		a.erase("client")


func _record_failure(pid: String) -> void:
	var c: Dictionary = config.data.get("circuit", {}) if config != null else {}
	var now := Time.get_ticks_msec()
	var times: Array = _fail_times.get(pid, [])
	times.append(now)
	var window := int(float(c.get("window_s", 60)) * 1000.0)
	times = times.filter(func(x): return now - int(x) <= window)
	_fail_times[pid] = times
	if times.size() >= int(c.get("failures", 3)):
		_open_until[pid] = now + int(float(c.get("open_s", 120)) * 1000.0)
		_fail_times[pid] = []
		status_changed.emit()


func circuit_open(pid: String) -> bool:
	return Time.get_ticks_msec() < int(_open_until.get(pid, 0))


# ------------------------------------------------------------------ health

var _health_cbs: Dictionary = {}     ## id -> [Callable] waiting on the in-flight check

func _check_health(pid: String, done: Callable = Callable()) -> void:
	if not providers.has(pid):
		if done.is_valid():
			done.call(false)
		return
	# A check already in flight: wait for it instead of dropping the callback
	# (dropping it here once meant the sidecar was never started).
	if _health_reqs.has(pid):
		if done.is_valid():
			_health_cbs[pid].append(done)
		return
	if not is_inside_tree():
		call_deferred("_check_health", pid, done)
		return
	var hr: Dictionary = providers[pid].health_request()
	if hr.is_empty():
		health[pid] = { "up": true, "checked_ms": Time.get_ticks_msec() }
		if done.is_valid():
			done.call(true)
		return
	var req := HTTPRequest.new()
	req.timeout = 2.0
	add_child(req)
	_health_reqs[pid] = req
	_health_cbs[pid] = [done] if done.is_valid() else []
	req.request_completed.connect(func(result: int, code: int, _h, _b):
		_health_done(pid, req, result == HTTPRequest.RESULT_SUCCESS and code == 200, "health %d/%d" % [result, code]))
	if req.request(str(hr.url)) != OK:
		_health_done(pid, req, false, "health request")


func _health_done(pid: String, req: HTTPRequest, ok: bool, err: String) -> void:
	var was: bool = bool(health.get(pid, {}).get("up", true))
	health[pid] = { "up": ok, "checked_ms": Time.get_ticks_msec(), "error": "" if ok else err }
	_health_reqs.erase(pid)
	req.queue_free()
	var cbs: Array = _health_cbs.get(pid, [])
	_health_cbs.erase(pid)
	if was != ok:
		status_changed.emit()
	for cb in cbs:
		(cb as Callable).call(ok)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if sidecar != null and not sidecar.reused:
			sidecar.stop()


# ------------------------------------------------------------------ helpers

## "https://host:port/a/b" -> { host, port, tls, path }  ({} if unparseable)
static func parse_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0:
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	if host == "":
		return {}
	return { "host": ("https://" if tls else "http://") + host, "port": port, "tls": tls, "path": path }
