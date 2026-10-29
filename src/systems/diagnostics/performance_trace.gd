extends RefCounted
## Compact, comparable frame-time telemetry for the rendered and headless route traces.
## GPU frame time is deliberately null: Godot's built-in monitors used here do not expose it.

const SCHEMA_VERSION := 1

var _frame_ms: Array[float] = []
var _process_cpu_ms: Array[float] = []
var _physics_cpu_ms: Array[float] = []
var _phase_frames: Dictionary = {}


func sample(delta_seconds: float, phase: String) -> void:
	if delta_seconds <= 0.0:
		return
	_frame_ms.append(delta_seconds * 1000.0)
	_process_cpu_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	_physics_cpu_ms.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	var samples: Array = _phase_frames.get(phase, [])
	samples.append(delta_seconds * 1000.0)
	_phase_frames[phase] = samples


func report(scenario: String, metadata: Dictionary = {}) -> Dictionary:
	var phases := {}
	for phase in _phase_frames:
		phases[phase] = percentiles(_phase_frames[phase])
	var display_server := DisplayServer.get_name()
	return {
		"schema_version": SCHEMA_VERSION,
		"scenario": scenario,
		"captured_at_unix": Time.get_unix_time_from_system(),
		"godot_version": Engine.get_version_info(),
		"os": OS.get_name(),
		"display_server": display_server,
		"measurement_mode": "headless_logic" if display_server == "headless" else "rendered_window",
		"frame_time_ms": percentiles(_frame_ms),
		"main_thread_process_ms": percentiles(_process_cpu_ms),
		"physics_process_ms": percentiles(_physics_cpu_ms),
		"gpu_frame_ms": null,
		"gpu_timing_note": "Not exposed by the built-in monitors sampled by this trace.",
		"phase_frame_time_ms": phases,
		"metadata": metadata
	}


func write_json(path: String, payload: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.close()
	return OK


static func percentiles(values: Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted: Array = values.duplicate()
	sorted.sort()
	return {
		"count": sorted.size(),
		"p50": _nearest_rank(sorted, 0.50),
		"p95": _nearest_rank(sorted, 0.95),
		"p99": _nearest_rank(sorted, 0.99),
		"max": float(sorted.back())
	}


static func _nearest_rank(sorted: Array, percentile: float) -> float:
	var index := clampi(ceili(percentile * sorted.size()) - 1, 0, sorted.size() - 1)
	return float(sorted[index])
