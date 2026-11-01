extends SceneTree
## M12 sidecar trace: the game's own code starts a REAL llama-server, waits for
## the model to load, and has a conversation turn through it. Optional in CI (it
## needs the binary and a .gguf); run it by hand on the Mac to prove her brain:
##
##   godot --headless --path . -s res://scenes/m12_sidecar_trace.gd -- \
##       bin=/opt/homebrew/bin/llama-server model=runtime/models/cantina_owner.gguf
##
## Without bin= it searches like the game does. Writes test_results/m12_sidecar_trace.txt.

const OUT := "res://test_results/m12_sidecar_trace.txt"
var lines := PackedStringArray()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v).replace("\n", " ")])
	printerr(lines[lines.size() - 1])


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var cfg := LLMConfig.new()
	cfg.user_path = "user://no_user_config_for_trace.json"
	cfg.load_all()
	cfg.set_ai_enabled(true)           # issue #328: off by default
	var port := int(args.get("port", "8099"))
	cfg.set_value("profiles/local/base_url", "http://127.0.0.1:%d/v1" % port)
	cfg.set_value("profiles/local/health_url", "http://127.0.0.1:%d/health" % port)
	cfg.set_value("profiles/local/sidecar/port", port)
	cfg.set_value("profiles/local/sidecar/ctx_size", int(args.get("ctx", "4096")))
	if args.has("bin"):
		cfg.set_value("profiles/local/sidecar/bin", args.bin)
	if args.has("model"):
		cfg.set_value("profiles/local/sidecar/model_path", args.model)
	if args.has("extra"):
		cfg.set_value("profiles/local/sidecar/extra_args", Array(str(args.extra).split(" ")))
	cfg.set_value("gen/first_token_timeout_ms/local", int(args.get("first_ms", "20000")))
	cfg.set_value("gen/total_timeout_ms", 120000)
	cfg.set_value("gen/give_up_ms", 120000)
	var svc := LLMService.new()
	get_root().add_child(svc)
	svc.configure(cfg)
	svc.set_mode("local")
	svc.start_sidecar()
	await process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await process_frame
		var st: int = svc.sidecar.state if svc.sidecar != null else -1
		if st in [LLMSidecar.State.READY, LLMSidecar.State.REUSED, LLMSidecar.State.NO_BINARY,
				LLMSidecar.State.NO_MODEL, LLMSidecar.State.CRASHED, LLMSidecar.State.FAILED]:
			break
	out("SIDECAR_STATE", LLMSidecar.State.keys()[svc.sidecar.state])
	out("SIDECAR_BIN", svc.sidecar.bin_found)
	out("SIDECAR_REASON", svc.sidecar.reason())
	out("LOAD_SECONDS", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1))
	out("REPORT", svc.brain_report().summary)
	if svc.sidecar.state == LLMSidecar.State.READY or svc.sidecar.state == LLMSidecar.State.REUSED:
		var b := NpcBrain.new(svc)
		b.log_transcripts = false
		WorldState.reset()
		WorldState.set_flag("gate_checkpoint_up")
		b.begin_visit()
		var deltas := [0]
		b.line_delta.connect(func(_t): deltas[0] += 1)
		b.say(str(args.get("say", "Evening. What's the word around the port?")))
		var t1 := Time.get_ticks_msec()
		while b.busy and Time.get_ticks_msec() - t1 < 120000:
			b.tick()
			await process_frame
		var t := b.last_turn
		out("TURN_SOURCE", t.get("source", ""))
		out("TURN_PROVIDER", t.get("provider", ""))
		out("TURN_ERROR", t.get("error", ""))
		out("TURN_FALLBACKS", t.get("fell_back_from", []))
		out("TURN_DELTAS", deltas[0])
		out("TURN_MS_FIRST", t.get("ms_first_token", -1))
		out("TURN_MS_TOTAL", t.get("ms_total", -1))
		out("TURN_REPAIRED", t.get("repaired", false))
		out("TURN_KEPT", t.get("kept", []))
		out("TURN_DROPPED", t.get("dropped", []))
		out("TURN_SAY", t.get("say", ""))
		out("TURN_RAW", str(t.get("raw", "")).substr(0, 600))
	if svc.sidecar != null:
		out("SERVER_LOG_TAIL", " | ".join(svc.sidecar.log_tail.slice(maxi(0, svc.sidecar.log_tail.size() - 3))))
		svc.sidecar.stop()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()
