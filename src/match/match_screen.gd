extends Control
## In-match chrome (M3-04): intro card with ready-skip, phase timer, running
## coin totals, and the round results panel. A pure renderer of match events
## and snapshots — the only thing it ever sends is the intro skip vote.
## M16-08: the always-on HUD (timer, game name, score-strip pills, emote feed)
## is themed via PartyTheme; the results/standings surface is M16-09's.
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
## Large-room UI (M15-06): coin chips fly to a grid that fits the screen width,
## and the results list packs several entries per row past this many players,
## so nothing runs off-screen at up to 24 players.
const COIN_GRID_SPACING := Vector2(80.0, 30.0)
const RESULTS_MAX_ROWS := 12
## In-match HUD score strip (#571): the totals row scrolls instead of growing
## the HUD panel past two chip-rows, and past this many players chips pack
## several players together (SmallLabel keeps each pill compact too) so most
## room sizes fit without ever needing the scrollbar; the scroll is the hard
## safety net for whatever still doesn't fit at extreme name lengths. Height
## is two chip rows (chip label's font size plus its pill padding) plus one
## row of separation, all from PartyTheme tokens — no invented pixels.
const TOTALS_MAX_CHIPS := 8
const TOTALS_CHIP_ROW_HEIGHT := (
	PartyTheme.SIZE_SMALL + PartyTheme.SPACE_XS * 2 + PartyTheme.SPACE_SM
)
const TOTALS_ROW_MAX_HEIGHT := TOTALS_CHIP_ROW_HEIGHT * 2 + PartyTheme.SPACE_SM
## Intro-card key art (M16-07): the styled text fallback shows until a file
## lands here for the round's minigame. M16-12 batches these image requests;
## dropping `<id>.png` in this dir lights the slot up with no code change.
const KEY_ART_DIR := "res://assets/generated/keyart/"
## The inter-round wipe covers this fraction of the screen width as a band.
const WIPE_BAND_FRACTION := 0.4
## Newest match-log lines kept for the hold-Tab overlay (#814) — older lines
## scroll off so a long match never grows the feed unbounded.
const MATCH_LOG_MAX := 40

## Seconds an emote stays in the feed; tests shorten it.
var emote_lifetime := 3.0

var _names := {}
var _totals := {}
var _minigame_id := ""
var _minigame_name := ""
## This client's rank per ordinary round completed this match (#712): {
## game_id, placement}, in play order. Recorded to StatsStore at match_ended;
## the finale is out of v1 scope. A fresh match_screen per match, so this
## never needs an explicit reset.
var _round_history: Array[Dictionary] = []
## Current intro card's device-aware hint segments (#608) and the plain-prose
## fallback, kept so a live device change can re-render without the event.
var _intro_hint_segments: Array = []
var _intro_controls_fallback := ""
## Current intro card's structured control rows (#832) and the chip container
## they render into (built in _ready above the legacy label). Rows win over
## hint segments, which win over the prose fallback.
var _intro_spec_rows: Array = []
var _intro_chips: VBoxContainer
var _round_view_flags: Array = []
var _minigame_view: MinigameView
## In-match pause/options overlay (M18-03), mounted on top in _ready.
var _pause_overlay: PauseOverlay
## Hold-Tab match-log overlay (#814) and its accumulating feed of match events
## (round intros/results, leaderboards, the winner) — built client-side from the
## events already received, capped so a long match never grows unbounded.
var _log_overlay: MatchLogOverlay
var _match_log: Array[String] = []
## Controller emote wheel (#608 part 3), mounted below the pause overlay.
var _emote_radial: EmoteRadial
## Device-aware "how to react" hint under the emote bar (#608).
var _emote_hint: Label
var _shake_tween: Tween
var _shake_origin := Vector2.ZERO
var _countdown_digit := 0

@onready var _countdown_label: Label = %CountdownLabel
@onready var _round_label: Label = %RoundLabel
@onready var _game_name_label: Label = %GameNameLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _totals_scroll: ScrollContainer = %TotalsScroll
@onready var _totals_row: HFlowContainer = %TotalsRow
@onready var _play_area: Control = %PlayArea
@onready var _play_placeholder: Label = %PlayPlaceholder
@onready var _intro_card: PanelContainer = %IntroCard
@onready var _intro_key_art: TextureRect = %IntroKeyArt
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
@onready var _shop_panel: ShopPanel = %ShopPanel
@onready var _emote_bar: HBoxContainer = %EmoteBar
@onready var _emote_feed: VBoxContainer = %EmoteFeed
@onready var _transition_wipe: ColorRect = %TransitionWipe


func _ready() -> void:
	NetManager.room_updated.connect(_on_room_updated)
	NetManager.match_event_received.connect(_on_match_event)
	NetManager.snapshot_received.connect(_on_snapshot)
	NetManager.emote_received.connect(_on_emote_received)
	_skip_button.pressed.connect(_on_skip_pressed)
	# Intro hints and the emote hint re-render live on a device switch (#608)
	# and on a keyboard/pad rebind (#832) — a remap shows immediately.
	InputGlyphs.device_changed.connect(
		func(_device: InputGlyphs.Device) -> void:
			_refresh_intro_controls()
			_refresh_emote_hint()
	)
	InputGlyphs.bindings_changed.connect(
		func() -> void:
			_refresh_intro_controls()
			_refresh_emote_hint()
	)
	_build_intro_chips()
	_build_emote_bar()
	# Controller emote wheel (#608 part 3): mounted before the pause overlay so
	# pause draws on top of it. The right stick aims it; see _process.
	_emote_radial = EmoteRadial.new()
	add_child(_emote_radial)
	set_process(true)
	# Match-log overlay (#814) sits below the pause overlay so pause draws on top;
	# both leave the live match running behind them.
	_log_overlay = MatchLogOverlay.new()
	add_child(_log_overlay)
	# Pause overlay (M18-03) sits above the HUD; the match keeps running behind.
	_pause_overlay = PauseOverlay.new()
	add_child(_pause_overlay)
	# Hard cap (#571): whatever _pack_total_chips can't keep to two rows at the
	# current width scrolls instead of stretching the HUD panel over the arena.
	_totals_scroll.custom_minimum_size.y = TOTALS_ROW_MAX_HEIGHT
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
			_match_log.clear()
			_log_line("▶ Match started")
			_rebuild_totals_row()
		"round_intro":
			_log_line("Round %d — %s" % [int(event.round), String(event.minigame.name)])
			# Rotate the round music from round 2 on (#711): round 1 keeps the
			# loop the match mount started, later intros crossfade to the next
			# loop in the pool so rounds stop all sharing one track.
			if int(event.get("round", 1)) > 1:
				AudioManager.advance_round_music()
			# A wipe punctuates the move into each round (M16-07).
			_play_transition_wipe()
			_unmount_view()
			_minigame_id = event.minigame.id
			_round_view_flags = event.get("mutator", {}).get("view_flags", [])
			_show_intro(event)
		"skip_votes":
			_skip_votes_label.text = "Skip votes: %d/%d" % [event.votes, event.needed]
		"round_countdown":
			# 3-2-1 over the visible arena and starting positions (#182); the
			# digits themselves track the replicated countdown clock.
			_mount_view(_minigame_id)
			_show_panel(null)
			_countdown_label.text = str(MatchController.COUNTDOWN_STEPS)
			_countdown_label.visible = true
		"round_started":
			AudioManager.play_sfx(&"round_start")
			_hide_countdown()
			if _minigame_view == null:
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
			_record_round_history(event.placements)
			_log_round_result(event)
		"leaderboard":
			AudioManager.play_sfx(&"leaderboard")
			_unmount_view()
			_show_standings("Leaderboard", event.totals)
		"finale_shop":
			# The buy-in phase (SPEC $6, #554): the wipe punctuates the shift
			# into the endgame the same way it does each round.
			AudioManager.play_music(&"finale")
			AudioManager.play_sfx(&"leaderboard")
			_play_transition_wipe()
			_unmount_view()
			_minigame_id = ""
			_show_panel(_shop_panel)
		"finale_started":
			AudioManager.play_sfx(&"round_start")
			_minigame_id = "gauntlet"
			_mount_view(_minigame_id)
			_show_panel(null)
		"match_ended":
			AudioManager.play_music(&"finale")
			AudioManager.play_sfx(&"podium")
			_unmount_view()
			_show_podium(event.standings, event.get("series", {}))
			_record_match_stats(event.standings)
			var standings: Array = event.standings
			if not standings.is_empty():
				_log_line(
					"🏆 %s wins the match!" % MatchFormat.player_name(_names, int(standings[0].slot))
				)
	# The log overlay refreshes live if it's being held open as the event lands.
	if _log_overlay != null and _log_overlay.is_open():
		_open_log()


func _on_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("match"):
		return
	var match_state: Dictionary = snapshot.match
	_timer_label.text = MatchFormat.clock(float(match_state.time_left))
	var state := int(match_state.state)
	if state == MatchController.State.FINALE_SHOP:
		# Rejoiners and event-racers land here from the snapshot alone (#554).
		if not _shop_panel.visible:
			_unmount_view()
			_show_panel(_shop_panel)
		_shop_panel.render(
			match_state.get("shop", {}), NetManager.my_slot, float(match_state.time_left)
		)
		return
	if (
		state
		not in [
			MatchController.State.COUNTDOWN,
			MatchController.State.PLAY,
			MatchController.State.FINALE_PLAY,
		]
	):
		return
	# A rejoiner (or a client that raced the skip) may reach this state
	# without the event; the replicated state is authoritative.
	if _intro_card.visible or _shop_panel.visible:
		_show_panel(null)
	if _minigame_view == null and match_state.has("minigame"):
		_round_view_flags = match_state.get("mutator", {}).get("view_flags", [])
		_mount_view(match_state.minigame)
	if _minigame_view != null and match_state.has("game"):
		# This client's private per-player state (#254), if the round's game
		# sent any; a sibling of "match", present only for the relevant slot.
		_minigame_view.private_state = snapshot.get("private", {})
		_minigame_view.render(match_state.game)
	if state == MatchController.State.COUNTDOWN:
		_update_countdown(float(match_state.time_left))
	else:
		_hide_countdown()


func _on_skip_pressed() -> void:
	NetManager.request_skip_intro()
	_skip_button.disabled = true
	_skip_button.text = "Waiting for others..."


## Number keys 1-6 mirror the emote bar buttons.
## Esc / pad Start toggles the pause overlay (M18-03). The server sim is never
## paused — this just overlays local controls while the round runs on.
func _unhandled_input(event: InputEvent) -> void:
	if _handle_emote_input(event):
		return
	if _handle_match_log_input(event):
		return
	var toggles := event.is_action_pressed(&"ui_cancel")
	if not toggles and event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		toggles = pad.pressed and pad.button_index == JOY_BUTTON_START
	if not toggles or _pause_overlay == null:
		return
	if _pause_overlay.is_open():
		_pause_overlay.close()
	else:
		_emote_radial.close()  # pause takes over; drop any open wheel
		_pause_overlay.open()
	get_viewport().set_input_as_handled()


## Hold the match-log button (Tab / pad Select) to overlay the roster + event
## feed; release to return (#814). Muted while the pause menu owns input — the
## server sim keeps running behind either overlay. Returns true when consumed.
func _handle_match_log_input(event: InputEvent) -> bool:
	if _log_overlay == null:
		return false
	var paused := _pause_overlay != null and _pause_overlay.is_open()
	if event.is_action_pressed(&"match_log") and not paused:
		_open_log()
		get_viewport().set_input_as_handled()
		return true
	if event.is_action_released(&"match_log") and _log_overlay.is_open():
		_log_overlay.close()
		get_viewport().set_input_as_handled()
		return true
	return false


func _open_log() -> void:
	if _log_overlay == null:
		return
	_log_overlay.open_with(MatchFormat.standings_lines(_totals, _names), _match_log)


## Append a feed line, capping the history so a long match never grows unbounded.
func _log_line(line: String) -> void:
	_match_log.append(line)
	if _match_log.size() > MATCH_LOG_MAX:
		_match_log = _match_log.slice(_match_log.size() - MATCH_LOG_MAX)


## A concise winner line per round for the feed — the results panel already
## showed the full breakdown, so the log just records who took it.
func _log_round_result(event: Dictionary) -> void:
	var placements: Array = event.placements
	if placements.is_empty():
		return
	var winners: Array[String] = []
	for slot: int in placements[0]:
		winners.append(MatchFormat.player_name(_names, int(slot)))
	_log_line("   🥇 %s" % ", ".join(winners))


## Controller emote wheel (#608 part 3): hold the emote button to open, release
## to send the aimed slot (or cancel). Pad-only; keyboard keeps the 1–6 keys.
## Returns true when the event was consumed.
func _handle_emote_input(event: InputEvent) -> bool:
	if _emote_radial.is_open() and event.is_action_released(&"emote"):
		var index := _emote_radial.selected_index()
		_emote_radial.close()
		if Emotes.is_valid(index):
			NetManager.request_send_emote(index)
		get_viewport().set_input_as_handled()
		return true
	var paused := _pause_overlay != null and _pause_overlay.is_open()
	if (
		event.is_action_pressed(&"emote")
		and InputGlyphs.active_device == InputGlyphs.Device.GAMEPAD
		and not paused
		and not _emote_radial.is_open()
	):
		_emote_radial.open()
		get_viewport().set_input_as_handled()
		return true
	return false


## While the wheel is open, aim it with the right stick every frame (the left
## stick keeps driving movement).
func _process(_delta: float) -> void:
	if _emote_radial != null and _emote_radial.is_open():
		_emote_radial.aim(_right_stick())


func _right_stick() -> Vector2:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return Vector2.ZERO
	var device: int = pads[0]
	return Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
	)


func _unhandled_key_input(event: InputEvent) -> void:
	# Emotes are muted while the pause menu owns input.
	if _pause_overlay != null and _pause_overlay.is_open():
		return
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
	# Each toast fades in as it drops into the feed (M16-08); reduced motion
	# (M12-03) shows it at rest.
	if not ArenaFX.reduced_motion:
		toast.modulate.a = 0.0
		var tween := toast.create_tween()
		tween.set_trans(PartyTheme.TRANS_DEFAULT).set_ease(PartyTheme.EASE_DEFAULT)
		tween.tween_property(toast, "modulate:a", 1.0, PartyTheme.DUR_FAST)
	get_tree().create_timer(emote_lifetime).timeout.connect(toast.queue_free)


func _build_emote_bar() -> void:
	for i in Emotes.EMOTES.size():
		var button := Button.new()
		button.text = Emotes.EMOTES[i]
		button.tooltip_text = "Send emote (%d)" % (i + 1)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: NetManager.request_send_emote(i))
		_emote_bar.add_child(button)
		ButtonMotion.attach(button)
	# Device-aware "how to react" hint (#608): keys on keyboard, the wheel on a
	# pad. Lives in the bar so it sits with the emotes it explains.
	_emote_hint = Label.new()
	_emote_hint.name = "EmoteHint"
	_emote_hint.theme_type_variation = PartyTheme.SMALL_VARIATION
	_emote_bar.add_child(_emote_hint)
	_refresh_emote_hint()


## Swaps the emote hint for the active device: the 1–6 shortcuts on keyboard,
## the hold-to-open wheel on a pad (the emote button's glyph per pad layout).
func _refresh_emote_hint() -> void:
	if _emote_hint == null:
		return
	if InputGlyphs.active_device == InputGlyphs.Device.GAMEPAD:
		var glyph := InputGlyphs.glyph_for(&"emote")
		_emote_hint.text = "Hold %s + stick to react" % (glyph if not glyph.is_empty() else "pad")
	else:
		_emote_hint.text = "1–6 to react"


func _show_intro(event: Dictionary) -> void:
	var minigame: Dictionary = event.minigame
	_round_label.text = "Round %d/%d" % [event.round, event.rounds]
	_minigame_name = String(minigame.name)
	_game_name_label.text = _minigame_name
	_intro_title.text = minigame.name
	_apply_key_art(String(minigame.id))
	_intro_category.text = MatchFormat.category_name(int(minigame.category))
	_intro_rules.text = minigame.rules
	# Control hints (M6-04); older servers may not send the key yet. When the
	# local catalog has device-aware hints (#608) they win over the prose.
	_intro_controls_fallback = String(minigame.get("controls", ""))
	_intro_hint_segments = _control_hints_for(String(minigame.id))
	_intro_spec_rows = _control_spec_for(String(minigame.id))
	_refresh_intro_controls()
	# Mutator announcement (M9-03) — no hidden modifiers.
	var mutator: Dictionary = event.get("mutator", {})
	_intro_mutator.visible = not mutator.is_empty()
	if not mutator.is_empty():
		_intro_mutator.text = "MUTATOR — %s: %s" % [mutator.name, mutator.blurb]
	_skip_button.disabled = false
	_skip_button.text = "Skip intro"
	_skip_votes_label.text = ""
	_show_panel(_intro_card)


## The local catalog's device-aware hint segments for this game, or [] to fall
## back to the server-sent prose. The client already registers the catalog
## (net_manager), so this needs no protocol change.
func _control_hints_for(id: String) -> Array:
	if not MinigameCatalog.is_registered(StringName(id)):
		return []
	return MinigameCatalog.meta_of(StringName(id)).control_hints


## The local catalog's structured control rows (#832), or [] to fall back to
## hint segments / prose. Client-derived like _control_hints_for.
func _control_spec_for(id: String) -> Array:
	if not MinigameCatalog.is_registered(StringName(id)):
		return []
	return MinigameCatalog.meta_of(StringName(id)).control_spec


## The chip rows live in the intro column right where the legacy label sits,
## so games with a structured spec show chips and everything else keeps the
## one-line hint — batches of the #844 fan-out are zero-risk per game.
func _build_intro_chips() -> void:
	_intro_chips = VBoxContainer.new()
	_intro_chips.name = "IntroControlChips"
	_intro_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_intro_chips.add_theme_constant_override(&"separation", PartyTheme.SPACE_XS)
	_intro_chips.visible = false
	var column := _intro_controls.get_parent()
	column.add_child(_intro_chips)
	column.move_child(_intro_chips, _intro_controls.get_index())


## Renders the intro controls for the active device, re-callable on device
## change and rebind (#832). Structured rows render as verb + key-pill chips;
## device-aware segments are the legacy one-line form; the plain-prose
## fallback shows when a game declares neither.
func _refresh_intro_controls() -> void:
	if not _intro_spec_rows.is_empty():
		_render_control_chips()
		_intro_controls.visible = false
		_intro_chips.visible = true
		return
	if _intro_chips != null:
		_intro_chips.visible = false
	var text := (
		InputGlyphs.hint_for(_intro_hint_segments)
		if not _intro_hint_segments.is_empty()
		else _intro_controls_fallback
	)
	_intro_controls.text = text
	_intro_controls.visible = not text.is_empty()


## One centered row per spec entry: the verb, then the ACTIVE device's binding
## in a key pill (with optional hold/modifier prefix, keyboard-only literal
## alternative, and a dim trailing note). Note-only rows render as a dim line.
func _render_control_chips() -> void:
	# Remove synchronously (not just queue_free) so a same-frame re-render —
	# device swap or rebind — never shows stale chips next to fresh ones.
	for child in _intro_chips.get_children():
		_intro_chips.remove_child(child)
		child.queue_free()
	for row: Dictionary in _intro_spec_rows:
		_intro_chips.add_child(_control_chip_row(row))


func _control_chip_row(row: Dictionary) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_theme_constant_override(&"separation", PartyTheme.SPACE_SM)
	var verb := String(row.get("verb", ""))
	if not verb.is_empty():
		var verb_label := Label.new()
		verb_label.name = "Verb"
		verb_label.text = verb
		chip.add_child(verb_label)
	var input := StringName(String(row.get("input", "")))
	if not String(input).is_empty():
		var modifier := String(row.get("modifier", "hold" if row.get("hold", false) else ""))
		if not modifier.is_empty():
			var modifier_label := Label.new()
			modifier_label.text = modifier
			modifier_label.theme_type_variation = PartyTheme.DIM_VARIATION
			chip.add_child(modifier_label)
		var pill := Label.new()
		pill.name = "Binding"
		pill.text = InputGlyphs.binding_label(input)
		pill.add_theme_stylebox_override(&"normal", PartyTheme.key_pill())
		chip.add_child(pill)
		var alt := String(row.get("alt", ""))
		if not alt.is_empty() and InputGlyphs.active_device == InputGlyphs.Device.KEYBOARD:
			var alt_label := Label.new()
			alt_label.text = alt
			alt_label.theme_type_variation = PartyTheme.DIM_VARIATION
			chip.add_child(alt_label)
	var note := String(row.get("note", ""))
	if not note.is_empty():
		var note_label := Label.new()
		note_label.name = "Note"
		note_label.text = note
		note_label.theme_type_variation = PartyTheme.DIM_VARIATION
		chip.add_child(note_label)
	return chip


## The digit tracks the replicated countdown clock (600 ms per step, #182),
## ticking audibly on each change.
func _update_countdown(time_left: float) -> void:
	_countdown_label.visible = true
	var digit := clampi(
		int(ceilf(time_left / MatchController.COUNTDOWN_STEP_SEC)),
		1,
		MatchController.COUNTDOWN_STEPS
	)
	if digit != _countdown_digit:
		_countdown_digit = digit
		_countdown_label.text = str(digit)
		_pop_countdown()
		AudioManager.play_sfx(&"tick")


func _hide_countdown() -> void:
	_countdown_label.visible = false
	_countdown_digit = 0


## Each countdown digit punches in (M16-07). Reduced-motion (M12-03) shows the
## digit at rest instead of scaling it.
func _pop_countdown() -> void:
	if ArenaFX.reduced_motion:
		return
	_countdown_label.pivot_offset = _countdown_label.size / 2.0
	_countdown_label.scale = Vector2(1.35, 1.35)
	var tween := create_tween()
	tween.set_trans(PartyTheme.TRANS_OVERSHOOT).set_ease(PartyTheme.EASE_DEFAULT)
	tween.tween_property(_countdown_label, "scale", Vector2.ONE, PartyTheme.DUR_MED)


## A coin-gold band sweeps across between rounds (M16-07). Reduced-motion
## (M12-03) skips it — no cover, no sweep.
func _play_transition_wipe() -> void:
	if ArenaFX.reduced_motion:
		return
	var band_w := size.x * WIPE_BAND_FRACTION
	_transition_wipe.size = Vector2(band_w, size.y)
	_transition_wipe.position = Vector2(-band_w, 0.0)
	_transition_wipe.visible = true
	var tween := create_tween()
	tween.set_trans(PartyTheme.TRANS_DEFAULT).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_transition_wipe, "position:x", size.x, PartyTheme.DUR_SLOW)
	tween.tween_callback(func() -> void: _transition_wipe.visible = false)


## The intro card's key-art slot (M16-07): shows `<id>.png` from KEY_ART_DIR if
## one has been delivered (M16-12), otherwise stays hidden so the styled text
## lockup is the fallback.
func _apply_key_art(id: String) -> void:
	var path := KEY_ART_DIR + id + ".png"
	if not id.is_empty() and ResourceLoader.exists(path):
		_intro_key_art.texture = load(path)
		_intro_key_art.visible = true
	else:
		_intro_key_art.texture = null
		_intro_key_art.visible = false


## Winners hear the win jingle; everyone else the consolation one.
func _result_sfx(event: Dictionary) -> StringName:
	var placements: Array = event.placements
	if not placements.is_empty() and NetManager.my_slot in placements[0]:
		return &"round_win"
	return &"round_lose"


## This client's 1-based rank in a round's tie-grouped placements, or 0 if
## our slot isn't in any group (a mid-round rejoin, say) — #712's standout-
## round math skips those rather than guessing.
func _my_round_rank(placements: Array) -> int:
	for i in placements.size():
		if NetManager.my_slot in (placements[i] as Array):
			return i + 1
	return 0


func _record_round_history(placements: Array) -> void:
	var rank := _my_round_rank(placements)
	if rank > 0 and not _minigame_id.is_empty():
		_round_history.append({"game_id": _minigame_id, "placement": rank})


## Records this match's outcome locally (#712) — client-side only, from the
## podium standings the client already receives plus this session's own round
## history. Zero protocol change; skipped if our slot never lands in
## `standings` (e.g. a very late join that never got tracked server-side).
func _record_match_stats(standings: Array) -> void:
	var placement := 0
	for i in standings.size():
		if int(standings[i].slot) == NetManager.my_slot:
			placement = i + 1
			break
	if placement == 0:
		return
	var result := {
		"date": Time.get_unix_time_from_system(),
		"placement": placement,
		"player_count": standings.size(),
		"rounds": _round_history,
	}
	StatsStore.save_stats(StatsStore.record_match(StatsStore.load_stats(), result))


func _show_results(event: Dictionary) -> void:
	_totals = event.totals
	_rebuild_totals_row()
	_results_title.text = "Round %d results" % event.round
	_fill_list(
		_results_list,
		_fit_result_lines(MatchFormat.result_lines(event.placements, event.awards, _names))
	)
	_show_panel(_results_panel, _minigame_view != null)
	_fly_coins(event.awards)


func _show_standings(title: String, totals: Dictionary, subtitle := "") -> void:
	_standings_panel.show_lines(title, subtitle, MatchFormat.standings_lines(totals, _names))
	_show_panel(_standings_panel)


func _show_podium(standings: Array, series: Dictionary = {}) -> void:
	var totals := {}
	for row: Dictionary in standings:
		totals[row.slot] = row.score
		_names[row.slot] = row.name
	var subtitle := ""
	if not standings.is_empty():
		# Through the identity funnel so the banner carries the player number
		# like every other line (M15-02).
		subtitle = "%s wins the match!" % MatchFormat.player_name(_names, int(standings[0].slot))
	# Series context (M11-02): champion banner on the final match, running
	# series score otherwise.
	if int(series.get("length", 1)) > 1:
		var rows: Array = series.get("standings", [])
		if bool(series.get("complete", false)) and not rows.is_empty():
			subtitle = "🏆 SERIES CHAMPION: %s!" % MatchFormat.player_name(_names, int(rows[0].slot))
		elif not rows.is_empty():
			subtitle += (
				"  ·  series: " + " / ".join(MatchFormat.series_lines(rows, _names).slice(0, 3))
			)
	_show_standings("Final standings", totals, subtitle)


## Shows one center panel (or none, during play). The play area placeholder
## is only visible while a round runs so the chrome reads as distinct phases;
## `keep_play_area` leaves the arena visible behind the panel (round results,
## so celebrations stay on screen — M6-02).
func _show_panel(panel: PanelContainer, keep_play_area := false) -> void:
	for candidate: PanelContainer in [_intro_card, _results_panel, _standings_panel, _shop_panel]:
		candidate.visible = candidate == panel
	_play_area.visible = panel == null or keep_play_area
	# Pad navigation (M17-04): interactive panels take focus so a controller
	# can act immediately; entering play releases it so no lingering focused
	# control eats Space/pad-A (ui_accept) meant for action_primary.
	if panel == _intro_card:
		_skip_button.grab_focus()
	elif panel == _shop_panel:
		_shop_panel.grab_initial_focus()
	elif panel == null:
		get_viewport().gui_release_focus()


## Mounts the minigame's view scene (MinigameCatalog convention path) into the
## play area; games without a view yet keep the placeholder label. The finale
## is the one non-catalog mount: its view lives in src/finale/ (#554).
func _mount_view(id: String) -> void:
	_unmount_view()
	if id.is_empty():
		return
	# The name stays on the HUD through the whole round (#181, for playtest
	# notes); the catalog lookup covers rejoiners who never saw the intro,
	# with the intro's own name as the fallback.
	if id == "gauntlet":
		_minigame_name = "The Gauntlet"
	elif MinigameCatalog.is_registered(StringName(id)):
		_minigame_name = MinigameCatalog.meta_of(StringName(id)).display_name
	_game_name_label.text = _minigame_name
	var path := (
		"res://src/finale/gauntlet_view.tscn"
		if id == "gauntlet"
		else MinigameCatalog.view_scene_path(id)
	)
	if not ResourceLoader.exists(path):
		return
	_minigame_view = (load(path) as PackedScene).instantiate()
	# Flags must land before setup() so _setup() can react to them (M9-05).
	_minigame_view.view_flags = _round_view_flags
	_minigame_view.setup(_names, NetManager.my_slot)
	_minigame_view.shake_requested.connect(_on_shake_requested)
	_play_area.add_child(_minigame_view)
	_play_placeholder.visible = false
	DiagnosticsLog.event(&"match", &"view_mount", {"game": id})


func _unmount_view() -> void:
	# Restore personal identity synchronously (#820): a team round's colors
	# must be gone before the leaderboard/podium chips this same handler builds
	# next read color_for_slot — the view's own _exit_tree clear rides a deferred
	# queue_free and would land a frame too late.
	PlayerPalette.clear_team_assignments()
	if _minigame_view != null:
		DiagnosticsLog.event(&"match", &"view_unmount", {"game": _minigame_id})
		_minigame_view.queue_free()
		_minigame_view = null
	_game_name_label.text = ""
	_hide_countdown()
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
## Pure decoration: totals are already correct before the flight starts, so
## reduced motion (M12-03) skips the flight outright — nothing to show at rest.
func _fly_coins(awards: Dictionary) -> void:
	if ArenaFX.reduced_motion:
		return
	var slots: Array = awards.keys()
	slots.sort()
	var earners := slots.filter(func(s: int) -> bool: return int(awards.get(s, 0)) > 0)
	var placed := 0
	for slot: int in earners:
		var coin := Label.new()
		coin.name = "CoinFly%d" % slot
		coin.text = "+%d" % int(awards[slot])
		# The chunky display face makes the +N read as it flies (M16-08).
		coin.theme_type_variation = &"HeaderLabel"
		coin.add_theme_color_override("font_color", PlayerPalette.color_for_slot(slot))
		add_child(coin)
		var offset := _coin_grid_offset(placed, earners.size(), size.x)
		coin.position = size / 2.0 + offset - Vector2(size.x * 0.25, 0.0)
		# global_position (not local .position) so the target stays correct no
		# matter how many containers now sit between TotalsRow and this root
		# (#571 added a ScrollContainer wrapper to cap the HUD's height).
		var target := _totals_row.global_position - global_position + offset
		var tween := create_tween()
		# EASE_IN is deliberate — chips accelerate away; the curve stays on-token.
		tween.set_ease(Tween.EASE_IN).set_trans(PartyTheme.TRANS_DEFAULT)
		tween.tween_property(coin, "position", target, COIN_FLY_SEC)
		tween.tween_callback(coin.queue_free)
		placed += 1


## Grid slot for coin chip `index` of `count`, packed into as many columns as
## fit `width` so no chip flies off-screen at large player counts (M15-06).
## Offset is relative to the totals row's left edge.
func _coin_grid_offset(index: int, count: int, width: float) -> Vector2:
	var cols := maxi(1, mini(count, int((width - 48.0) / COIN_GRID_SPACING.x)))
	return Vector2(
		24.0 + (index % cols) * COIN_GRID_SPACING.x, (index / cols) * COIN_GRID_SPACING.y
	)


## Packs ranked result lines into at most RESULTS_MAX_ROWS rows (several entries
## per row for large lobbies) so the list never overflows the panel; small
## lobbies keep one entry per row (M15-06).
func _fit_result_lines(lines: Array[String]) -> Array[String]:
	if lines.size() <= RESULTS_MAX_ROWS:
		return lines
	var per_row := int(ceil(float(lines.size()) / float(RESULTS_MAX_ROWS)))
	var packed: Array[String] = []
	for i in range(0, lines.size(), per_row):
		packed.append("     ".join(lines.slice(i, i + per_row)))
	return packed


## Groups sorted slots into at most TOTALS_MAX_CHIPS pill-groups (several
## players sharing one pill past that many), the same multi-per-row trick
## _fit_result_lines uses for the results panel (#571): the HUD's chip *count*
## stays bounded so two rows is always enough, instead of letting the
## HFlowContainer wrap into as many rows as it needs. No player's name/score
## is ever dropped, only grouped — and a group of one keeps its own color.
func _pack_total_chips(slots: Array) -> Array:
	if slots.size() <= TOTALS_MAX_CHIPS:
		return slots.map(func(s: int) -> Array: return [s])
	var per_chip := int(ceil(float(slots.size()) / float(TOTALS_MAX_CHIPS)))
	var groups := []
	for i in range(0, slots.size(), per_chip):
		groups.append(slots.slice(i, i + per_chip))
	return groups


func _rebuild_totals_row() -> void:
	for child in _totals_row.get_children():
		child.queue_free()
	var slots: Array = _names.keys()
	slots.sort()
	for group: Array in _pack_total_chips(slots):
		_totals_row.add_child(_make_total_chip(group))


## A compact themed score pill (M16-08): "P# N" in the player's color on a
## small raised background, so running totals stay scannable at a glance. Once
## _pack_total_chips groups several players into one pill (24-player rooms,
## #571) the shared pill lists each "P# N" in the default text color instead —
## same trade the results panel already makes when it condenses rows.
func _make_total_chip(group: Array) -> PanelContainer:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PartyTheme.BG_RAISED
	style.set_corner_radius_all(PartyTheme.RADIUS_SM)
	style.content_margin_left = PartyTheme.SPACE_SM
	style.content_margin_right = PartyTheme.SPACE_SM
	style.content_margin_top = PartyTheme.SPACE_XS
	style.content_margin_bottom = PartyTheme.SPACE_XS
	pill.add_theme_stylebox_override(&"panel", style)
	var chip := Label.new()
	# SmallLabel keeps pills compact (M16-01 token) so more fit per row before
	# _pack_total_chips ever needs to group players together (#571).
	chip.theme_type_variation = PartyTheme.SMALL_VARIATION
	var texts: Array[String] = []
	for slot: int in group:
		texts.append("%s %d" % [MatchFormat.player_name(_names, slot), int(_totals.get(slot, 0))])
	chip.text = "   ".join(texts)
	if group.size() == 1:
		chip.add_theme_color_override(&"font_color", PlayerPalette.color_for_slot(group[0]))
	pill.add_child(chip)
	return pill


func _fill_list(list: VBoxContainer, lines: Array[String]) -> void:
	for child in list.get_children():
		child.queue_free()
	for line in lines:
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(label)
