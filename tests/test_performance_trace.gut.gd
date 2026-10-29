extends GutTest

const PerfTrace := preload("res://src/systems/diagnostics/performance_trace.gd")


func test_percentiles_use_nearest_rank_for_repeatable_frame_summaries() -> void:
	var stats := PerfTrace.percentiles([10.0, 20.0, 30.0, 40.0, 100.0])
	assert_eq(stats.get("count"), 5)
	assert_eq(stats.get("p50"), 30.0)
	assert_eq(stats.get("p95"), 100.0)
	assert_eq(stats.get("p99"), 100.0)
	assert_eq(stats.get("max"), 100.0)


func test_percentiles_are_empty_without_samples() -> void:
	assert_true(PerfTrace.percentiles([]).is_empty())
