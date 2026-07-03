extends Control
## In-match chrome (M3-04): intro card with ready-skip, phase timer, running
## coin totals, and the round results panel. A pure renderer of match events
## and snapshots — the only thing it ever sends is the intro skip vote.
## The minigame view itself mounts into %PlayArea (M3-06); leaderboard and
## podium get dedicated scenes (M3-05), rendered here as simple lists so the
## full loop is visible meanwhile.

## Fixed jiggle pattern scaled by the requested strength (M6-02); a fixed
## pattern keeps the shake deterministic and cheap.
const SHAKE_PATTERN: Array[Vector2] = [
	Vector2(1.0, -0.6),
	Vector2(-0.8, 0.4),
	Vector2(0.5, 0.7),
	Vector2(-0.3, -0.4),
]
const SHAKE_STEP_SEC := 0.04
const COIN_FLY_SEC := 0.6

## Seconds an emote stays in the feed; tests shorten it.
var emote_lifetime := 3.0

var _names := {}
var _totals := {}
var _minigame_id := ""
var _round_view_flags: Array = []
var _minigame_view: MinigameView
var _shake_tween: Tween
var _shake_origin := Vector2.ZERO

@onready var _round_label: Label = %RoundLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _totals_row: HBoxContainer = %TotalsRow
@onready var _play_area: Control = %PlayArea
@onready var _play_placeholder: Label = %PlayPlaceholder
@onready var _intro_card: PanelContainer = %IntroCard
@onready var _intro_title: Label = %IntroTitle
@onready var _intro_category: Label = %IntroCategory
@onready var _intro_rules: Label = %IntroRules
@onready var _intro_controls: Label = %IntroControls
@onready var _intro_mutator: Label = %IntroMutator
@onready var _skip_button: Button = %SkipButton
@onready var _skip_votes_label: Label = %SkipVotesLabel
@onready var _results_panel: PanelContainer = %ResultsPanel
@onready var _results_title: Label = %ResultsTitle
@onready var _results_list: VBoxContainer = %ResultsList
@onready var _standings_panel: StandingsPanel = %StandingsPanel
@onready var _emote_bar: HBoxContainer = %EmoteBar
@onready var _emote_feed: VBoxContainer = %EmoteFeed


func _ready() -> void:
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.match_event_received.connect(_on_match_event)
	NetManager.snapshot_received.connect(_on_snapshot)
	NetManager.emote_received.connect(_on_emote_received)
	_skip_button.pressed.connect(_on_skip_pressed)
	_build_emote_bar()
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
			_round_view_flags = event.get("mutator", {}).get("view_flags", [])
			_show_intro(event)
		"skip_votes":
			_skip_votes_label.text = "Skip votes: %d/%d" % [event.votes, event.needed]
		"round_started":
			AudioManager.play_sfx(&"round_start")
			_mount_view(_minigame_id)
			_show_panel(null)
		"round_results":
			# The arena stays mounted and visible behind the results panel so
			# the winners' victory dance plays out (M6-02); it unmounts on the
			# next phase event instead.
			if _minigame_view != null:
				_minigame_view.celebrate(event.placements)
			AudioManager.play_sfx(_result_sfx(event))
			_show_results(event)
		"leaderboard":
			AudioManager.play_sfx(&"leaderboard")
			_unmount_view()
			_show_standings("Leaderboard", event.totals)
		"match_ended":
			AudioManager.play_music(&"finale")
			AudioManager.play_sfx(&"podium")
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
		_round_view_flags = match_state.get("mutator", {}).get("view_flags", [])
		_mount_view(match_state.minigame)
	if _minigame_view != null and match_state.has("game"):
		_minigame_view.render(match_state.game)


func _on_skip_pressed() -> void:
	NetManager.request_skip_intro()
	_skip_button.disabled = true
	_skip_button.text = "Waiting for others..."


## Number keys 1-6 mirror the emote bar buttons.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var index := key.keycode - KEY_1
	if Emotes.is_valid(index):
		NetManager.request_send_emote(index)


func _on_emote_received(slot: int, emote: int) -> void:
	var toast := Label.new()
	toast.text = "%s %s" % [MatchFormat.player_name(_names, slot), Emotes.text(emote)]
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toast.add_theme_color_override("font_color", PlayerPalette.color_for_slot(slot))
	_emote_feed.add_child(toast)
	get_tree().create_timer(emote_lifetime).timeout.connect(toast.queue_free)


func _build_emote_bar() -> void:
	for i in Emotes.EMOTES.size():
		var button := Button.new()
		button.text = Emotes.EMOTES[i]
		button.tooltip_text = "Send emote (%d)" % (i + 1)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: NetManager.request_send_emote(i))
		_emote_bar.add_child(button)


func _show_intro(event: Dictionary) -> void:
	var minigame: Dictionary = event.minigame
	_round_label.text = "Round %d/%d" % [event.round, event.rounds]
	_intro_title.text = minigame.name
	_intro_category.text = MatchFormat.category_name(int(minigame.category))
	_intro_rules.text = minigame.rules
	# Control hints (M6-04); older servers may not send the key yet.
	_intro_controls.text = String(minigame.get("controls", ""))
	_intro_controls.visible = not _intro_controls.text.is_empty()
	# Mutator announcement (M9-03) — no hidden modifiers.
	var mutator: Dictionary = event.get("mutator", {})
	_intro_mutator.visible = not mutator.is_empty()
	if not mutator.is_empty():
		_intro_mutator.text = "MUTATOR — %s: %s" % [mutator.name, mutator.blurb]
	_skip_button.disabled = false
	_skip_button.text = "Skip intro"
	_skip_votes_label.text = ""
	_show_panel(_intro_card)


## Winners hear the win jingle; everyone else the consolation one.
func _result_sfx(event: Dictionary) -> StringName:
	var placements: Array = event.placements
	if not placements.is_empty() and NetManager.my_slot in placements[0]:
		return &"round_win"
	return &"round_lose"


func _show_results(event: Dictionary) -> void:
	_totals = event.totals
	_rebuild_totals_row()
	_results_title.text = "Round %d results" % event.round
	_fill_list(_results_list, MatchFormat.result_lines(event.placements, event.awards, _names))
	_show_panel(_results_panel, _minigame_view != null)
	_fly_coins(event.awards)


func _show_standings(title: String, totals: Dictionary, subtitle := "") -> void:
	_standings_panel.show_lines(title, subtitle, MatchFormat.standings_lines(totals, _names))
	_show_panel(_standings_panel)


func _show_podium(standings: Array) -> void:
	var totals := {}
	for row: Dictionary in standings:
		totals[row.slot] = row.score
		_names[row.slot] = row.name
	var subtitle := ""
	if not standings.is_empty():
		subtitle = "%s wins the match!" % standings[0].name
	_show_standings("Final standings", totals, subtitle)


## Shows one center panel (or none, during play). The play area placeholder
## is only visible while a round runs so the chrome reads as distinct phases;
## `keep_play_area` leaves the arena visible behind the panel (round results,
## so celebrations stay on screen — M6-02).
func _show_panel(panel: PanelContainer, keep_play_area := false) -> void:
	for candidate: PanelContainer in [_intro_card, _results_panel, _standings_panel]:
		candidate.visible = candidate == panel
	_play_area.visible = panel == null or keep_play_area


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
	# Flags must land before setup() so _setup() can react to them (M9-05).
	_minigame_view.view_flags = _round_view_flags
	_minigame_view.setup(_names, NetManager.my_slot)
	_minigame_view.shake_requested.connect(_on_shake_requested)
	_play_area.add_child(_minigame_view)
	_play_placeholder.visible = false


func _unmount_view() -> void:
	if _minigame_view != null:
		_minigame_view.queue_free()
		_minigame_view = null
	_play_placeholder.visible = true


## Decaying positional shake on the play area (M6-02). Impacts come from the
## mounted view's shake_requested signal. A shake landing mid-shake reuses the
## first shake's rest position so the play area never drifts.
func _on_shake_requested(strength: float) -> void:
	var origin := _play_area.position
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		origin = _shake_origin
	_shake_origin = origin
	_shake_tween = create_tween()
	for i in SHAKE_PATTERN.size():
		var falloff := 1.0 - float(i) / SHAKE_PATTERN.size()
		_shake_tween.tween_property(
			_play_area, "position", origin + SHAKE_PATTERN[i] * strength * falloff, SHAKE_STEP_SEC
		)
	_shake_tween.tween_property(_play_area, "position", origin, SHAKE_STEP_SEC)


## "+N" coin chips fly from mid-screen to the running-total row (M6-02).
## Pure decoration: totals are already correct before the flight starts.
func _fly_coins(awards: Dictionary) -> void:
	var slots: Array = awards.keys()
	slots.sort()
	for i in slots.size():
		var slot: int = slots[i]
		var amount := int(awards.get(slot, 0))
		if amount <= 0:
			continue
		var coin := Label.new()
		coin.name = "CoinFly%d" % slot
		coin.text = "+%d" % amount
		coin.add_theme_color_override("font_color", PlayerPalette.color_for_slot(slot))
		add_child(coin)
		coin.position = size / 2.0 + Vector2((i - slots.size() / 2.0) * 40.0, 0.0)
		var target := _totals_row.position + Vector2(24.0 + i * 80.0, 0.0)
		var tween := create_tween()
		tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(coin, "position", target, COIN_FLY_SEC)
		tween.tween_callback(coin.queue_free)


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
