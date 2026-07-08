extends GutTest
## Load-soak server-tick telemetry (#710): _record_tick_time keeps a rolling
## window of broadcast-tick durations for the multi-room soak's p95/max print.
## The one correctness risk on a server that runs for days is the window growing
## unbounded — this pins it to TICK_SAMPLE_CAP.


func after_each() -> void:
	NetManager._tick_samples = []


func test_the_sample_window_stays_capped() -> void:
	# Feed far more than the cap; the ring must not grow without bound.
	for i in NetManager.TICK_SAMPLE_CAP + 500:
		NetManager._record_tick_time(1000 + i)
	assert_lte(
		NetManager._tick_samples.size(),
		NetManager.TICK_SAMPLE_CAP,
		"tick window is bounded so a long-lived server can't leak it"
	)


func test_it_keeps_the_most_recent_samples() -> void:
	for i in NetManager.TICK_SAMPLE_CAP + 10:
		NetManager._record_tick_time(i)
	# The oldest (0..9) should have been evicted; the newest is retained.
	assert_true(
		NetManager._tick_samples.has(NetManager.TICK_SAMPLE_CAP + 9), "the latest sample survives"
	)
	assert_false(NetManager._tick_samples.has(0), "the oldest sample was evicted")
