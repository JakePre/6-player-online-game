class_name ServerStatusChip
extends PanelContainer
## Pre-connection server status chip for the main menu (#607): before the player
## commits to Host/Join, probe the configured default server and show whether
## it's up — SUCCESS "Online · 34 ms" / DANGER "Unreachable — check Settings →
## Network" / a neutral "Checking server…" while in flight — with a retry button.
##
## This is the pre-connection sibling of connection_status.gd (SPEC $11), which
## shows the same idea *during* a session. The probe (server_reachability_probe)
## uses a throwaway peer that never touches `multiplayer.multiplayer_peer`, so it
## can't disturb the real Host/Join flow.
##
## A loopback target has no server to reach until the player Hosts one, so the
## chip labels that case instead of crying "Unreachable" at a server that simply
## doesn't exist yet — the "graceful localhost/custom" degrade the issue asks for.

## Emitted whenever a probe (re)starts, so the menu can log it and tests can
## observe the retry without touching the network.
signal probe_requested

enum State { CHECKING, ONLINE, UNREACHABLE, LOCAL }

const CHECKING_TEXT := "Checking server…"
const UNREACHABLE_TEXT := "Unreachable — check Settings → Network"
## A loopback default: the "server" is whatever this machine hosts, so there is
## nothing to reach until the player presses Host.
const LOCAL_TEXT := "Local server — starts when you Host"

## Set false in tests so a probe never opens a real socket; the state machine is
## then driven directly through `_on_probe_finished`.
var live_probe := true

var _state := State.CHECKING
var _rtt_ms := -1
var _address := ""
var _port := 0
var _probe: ServerReachabilityProbe

var _label: Label
var _retry: Button


func _ready() -> void:
	theme_type_variation = &"CardPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	_label = Label.new()
	_label.name = "StatusText"
	_label.theme_type_variation = PartyTheme.SMALL_VARIATION
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_label)
	_retry = Button.new()
	_retry.name = "RetryButton"
	_retry.text = "Retry"
	_retry.visible = false
	_retry.pressed.connect(probe)
	row.add_child(_retry)
	_refresh()


## Point the chip at the server the menu would actually connect to, then probe.
## Loopback/empty targets are labelled rather than probed.
func configure(address: String, port: int) -> void:
	_address = address.strip_edges()
	_port = port
	if _is_local(_address):
		_set_state(State.LOCAL)
		return
	probe()


## (Re)start the reachability probe. Public so the Retry button and the menu can
## both trigger it; tests observe it via `probe_requested`.
func probe() -> void:
	_cancel_probe()
	_rtt_ms = -1
	_set_state(State.CHECKING)
	probe_requested.emit()
	if not live_probe or _is_local(_address) or _address.is_empty():
		return
	_probe = ServerReachabilityProbe.new()
	add_child(_probe)
	_probe.finished.connect(_on_probe_finished)
	_probe.start(_address, _port)


func _on_probe_finished(reachable: bool, rtt_ms: int) -> void:
	_rtt_ms = rtt_ms
	_set_state(State.ONLINE if reachable else State.UNREACHABLE)
	_cancel_probe()


func _set_state(state: State) -> void:
	_state = state
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	_label.text = _status_text()
	_label.add_theme_color_override(&"font_color", _status_color())
	# Retry only makes sense once a probe has failed; checking/online/local hide it.
	if _retry != null:
		_retry.visible = _state == State.UNREACHABLE


func _status_text() -> String:
	match _state:
		State.ONLINE:
			return "Online · %d ms" % _rtt_ms if _rtt_ms >= 0 else "Online"
		State.UNREACHABLE:
			return UNREACHABLE_TEXT
		State.LOCAL:
			return LOCAL_TEXT
		_:
			return CHECKING_TEXT


## SUCCESS when online, DANGER when unreachable; checking and local stay neutral
## dim text — neither good nor bad news yet (mirrors connection_status.gd).
func _status_color() -> Color:
	match _state:
		State.ONLINE:
			return PartyTheme.SUCCESS
		State.UNREACHABLE:
			return PartyTheme.DANGER
		_:
			return PartyTheme.TEXT_DIM


func _cancel_probe() -> void:
	if _probe != null:
		_probe.cancel()
		_probe.queue_free()
		_probe = null


func _is_local(address: String) -> bool:
	var host := address.strip_edges().to_lower()
	return host in ["", "localhost", "127.0.0.1", "::1", "0.0.0.0"]
