extends GutTest
## ResultsPresenter (#943 part 2): the results panel's ranked-line rendering
## and the "+N" coin flights, extracted from match_screen. Driven directly
## against stub nodes so the presentation is verifiable without a whole match.

var _root: Control
var _title: Label
var _list: VBoxContainer
var _totals_row: Control
var _presenter: ResultsPresenter


func before_each() -> void:
	MinigameCatalog.register_builtins()
	_root = Control.new()
	_root.size = Vector2(1152, 648)
	add_child_autofree(_root)
	_title = Label.new()
	_list = VBoxContainer.new()
	_totals_row = Control.new()
	_root.add_child(_title)
	_root.add_child(_list)
	_root.add_child(_totals_row)
	_presenter = ResultsPresenter.new(_title, _list, _root, _totals_row)


func after_each() -> void:
	MinigameCatalog.clear()


# --- ranked-line rendering ---------------------------------------------------


func test_render_sets_the_title_and_fills_the_list() -> void:
	_presenter.render(3, [[0], [1]], {0: 30, 1: 20}, {0: "Alice", 1: "Bob"})
	assert_eq(_title.text, "Round 3 results")
	assert_gt(_list.get_child_count(), 0, "the ranked lines fill the list")


## Results pack into at most RESULTS_MAX_ROWS rows for large lobbies; small
## lobbies are unchanged (one entry per row).
func test_results_condense_for_large_lobbies() -> void:
	var many: Array[String] = []
	for i in 24:
		many.append("place %d" % i)
	var packed: Array[String] = _presenter._fit_result_lines(many)
	assert_true(packed.size() <= 12, "24 players pack into <=12 rows, got %d" % packed.size())
	var few: Array[String] = ["1st", "2nd", "3rd"]
	assert_eq(_presenter._fit_result_lines(few), few, "small lobbies unchanged")


# --- coin flights ------------------------------------------------------------


## Coin chips fly to a grid that stays within the screen width at any count.
func test_coin_grid_stays_within_screen_width() -> void:
	var width := 1152.0
	for i in 24:
		var offset: Vector2 = _presenter._coin_grid_offset(i, 24, width)
		assert_between(offset.x, 0.0, width - float(_presenter.COIN_GRID_SPACING.x))


## A small lobby's coins stay on one row (no needless wrapping).
func test_coin_grid_single_row_for_small_lobbies() -> void:
	for i in 6:
		assert_almost_eq(float(_presenter._coin_grid_offset(i, 6, 1152.0).y), 0.0, 0.001)


## Each earner gets a "+N" chip parented to the root (so match_screen's
## get_node("CoinFly<slot>") still resolves), labeled with the award.
func test_fly_coins_spawns_a_labeled_chip_per_earner() -> void:
	var saved := ArenaFX.reduced_motion
	ArenaFX.reduced_motion = false
	_presenter.fly_coins({0: 30, 1: 20, 2: 0})
	var alice: Label = _root.get_node_or_null("CoinFly0")
	var bob: Label = _root.get_node_or_null("CoinFly1")
	assert_not_null(alice)
	assert_not_null(bob)
	assert_eq(alice.text, "+30")
	assert_eq(bob.text, "+20")
	assert_null(_root.get_node_or_null("CoinFly2"), "a zero award earns no chip")
	ArenaFX.reduced_motion = saved


## Reduced motion (M12-03) skips the decoration entirely — totals are already
## correct, so there is nothing to show at rest.
func test_reduced_motion_skips_the_coin_flight() -> void:
	var saved := ArenaFX.reduced_motion
	ArenaFX.reduced_motion = true
	_presenter.fly_coins({0: 30})
	assert_null(_root.get_node_or_null("CoinFly0"), "no chips fly under reduced motion")
	ArenaFX.reduced_motion = saved
