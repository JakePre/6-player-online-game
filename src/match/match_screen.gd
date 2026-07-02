extends Control
## In-match chrome (M3-04): intro card with ready-skip, phase timer, running
## coin totals, and the round results panel. A pure renderer of match events
## and snapshots — the only thing it ever sends is the intro skip vote.
## The minigame view itself mounts into %PlayArea (M3-06); leaderboard and
## podium get dedicated scenes (M3-05), rendered here as simple lists so the
## full loop is visible meanwhile.

var _names := {}
var _totals := {}
var _minigame_id := ""
var _minigame_view: MinigameView

@onready var _round_label: Label = %RoundLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _totals_row: HBoxContainer = %TotalsRow
@onready var _play_area: Control = %PlayArea
@onready var _play_placeholder: Label = %PlayPlaceholder
@onready var _intro_card: PanelContainer = %IntroCard
@onready var _intro_title: Label = %IntroTitle
@onready var _intro_category: Label = %IntroCategory
@onready var _intro_rules: Label = %IntroRules
@onready var _skip_button: Button = %SkipButton
@onready var _skip_votes_label: Label = %SkipVotesLabel
@onready var _results_panel: PanelContainer = %ResultsPanel
@onready var _results_title: Label = %ResultsTitle
@onready var _results_list: VBoxContainer = %ResultsList
@onready var _interstitial_panel: PanelContainer = %InterstitialPanel
@onready var _interstitial_title: Label = %InterstitialTitle
@onready var _interstitial_list: VBoxContainer = %InterstitialList


func _ready() -> void:
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.match_event_received.connect(_on_match_event)
	NetManager.snapshot_received.connect(_on_snapshot)
	_skip_button.pressed.connect(_on_skip_pressed)
	# Waiting for the first event (or, for a mid-match rejoiner, a snapshot).
	_show_panel(null)
	if NetManager.my_room_state.has("members"):
		_on_room_updated(NetManager.my_room_state)


func _on_room_updated(state: Dictionary) -> void:
	_names.clear()
	for member: Dictionary in state.members:
		_names[member.slot] = member.name
	_rebuild_totals_row()


func _on_match_event(event: Dictionary) -> void:
	match String(event.type):
		"match_started":
			_totals.clear()
			_rebuild_totals_row()
		"round_intro":
			_unmount_view()
			_minigame_id = event.minigame.id
			_show_intro(event)
		"skip_votes":
			_skip_votes_label.text = "Skip votes: %d/%d" % [event.votes, event.needed]
		"round_started":
			_mount_view(_minigame_id)
			_show_panel(null)
		"round_results":
			_unmount_view()
			_show_results(event)
		"leaderboard":
			_show_standings("Leaderboard", event.totals)
		"match_ended":
			_unmount_view()
			_show_podium(event.standings)


func _on_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("match"):
		return
	var match_state: Dictionary = snapshot.match
	_timer_label.text = MatchFormat.clock(float(match_state.time_left))
	if int(match_state.state) != MatchController.State.PLAY:
		return
	# A rejoiner (or a client that raced the skip) may reach PLAY without the
	# round_started event; the replicated state is authoritative.
	if _intro_card.visible:
		_show_panel(null)
	if _minigame_view == null and match_state.has("minigame"):
		_mount_view(match_state.minigame)
	if _minigame_view != null and match_state.has("game"):
		_minigame_view.render(match_state.game)


func _on_skip_pressed() -> void:
	NetManager.request_skip_intro()
	_skip_button.disabled = true
	_skip_button.text = "Waiting for others..."


func _show_intro(event: Dictionary) -> void:
	var minigame: Dictionary = event.minigame
	_round_label.text = "Round %d/%d" % [event.round, event.rounds]
	_intro_title.text = minigame.name
	_intro_category.text = MatchFormat.category_name(int(minigame.category))
	_intro_rules.text = minigame.rules
	_skip_button.disabled = false
	_skip_button.text = "Skip intro"
	_skip_votes_label.text = ""
	_show_panel(_intro_card)


func _show_results(event: Dictionary) -> void:
	_totals = event.totals
	_rebuild_totals_row()
	_results_title.text = "Round %d results" % event.round
	_fill_list(_results_list, MatchFormat.result_lines(event.placements, event.awards, _names))
	_show_panel(_results_panel)


func _show_standings(title: String, totals: Dictionary) -> void:
	_interstitial_title.text = title
	_fill_list(_interstitial_list, MatchFormat.standings_lines(totals, _names))
	_show_panel(_interstitial_panel)


func _show_podium(standings: Array) -> void:
	var totals := {}
	for row: Dictionary in standings:
		totals[row.slot] = row.score
		_names[row.slot] = row.name
	_show_standings("Final standings", totals)


## Shows one center panel (or none, during play). The play area placeholder
## is only visible while a round runs so the chrome reads as distinct phases.
func _show_panel(panel: PanelContainer) -> void:
	for candidate: PanelContainer in [_intro_card, _results_panel, _interstitial_panel]:
		candidate.visible = candidate == panel
	_play_area.visible = panel == null


## Mounts the minigame's view scene (MinigameCatalog convention path) into the
## play area; games without a view yet keep the placeholder label.
func _mount_view(id: String) -> void:
	_unmount_view()
	if id.is_empty():
		return
	var path := MinigameCatalog.view_scene_path(id)
	if not ResourceLoader.exists(path):
		return
	_minigame_view = (load(path) as PackedScene).instantiate()
	_minigame_view.setup(_names, NetManager.my_slot)
	_play_area.add_child(_minigame_view)
	_play_placeholder.visible = false


func _unmount_view() -> void:
	if _minigame_view != null:
		_minigame_view.queue_free()
		_minigame_view = null
	_play_placeholder.visible = true


func _rebuild_totals_row() -> void:
	for child in _totals_row.get_children():
		child.queue_free()
	var slots: Array = _names.keys()
	slots.sort()
	for slot: int in slots:
		var chip := Label.new()
		chip.text = "%s %d" % [MatchFormat.player_name(_names, slot), int(_totals.get(slot, 0))]
		chip.add_theme_color_override("font_color", PlayerPalette.color_for_slot(slot))
		_totals_row.add_child(chip)


func _fill_list(list: VBoxContainer, lines: Array[String]) -> void:
	for child in list.get_children():
		child.queue_free()
	for line in lines:
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(label)
