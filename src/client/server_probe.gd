class_name ServerProbe
extends RefCounted
## Pre-connection reachability status for the main menu (#607): before the
## player commits to Host/Join, a lightweight probe reports whether the
## configured server (celestrum.com by default) is reachable. This is the pure
## state + chip formatting so it is unit-testable without a live server;
## main_menu owns the connect/ping/timeout orchestration, which — like the
## on-load update check — is not exercised by instantiation tests.

enum Status { CHECKING, ONLINE, UNREACHABLE }

var status := Status.CHECKING
var rtt_ms := -1


func mark_checking() -> void:
	status = Status.CHECKING
	rtt_ms = -1


func mark_online(rtt: int) -> void:
	status = Status.ONLINE
	rtt_ms = maxi(0, rtt)


func mark_unreachable() -> void:
	status = Status.UNREACHABLE
	rtt_ms = -1


## Chip text for `state` against a display address ("celestrum.com",
## "127.0.0.1", ...). Static + pure so tests drive it without the menu.
static func chip_text(state: Status, rtt: int, address: String) -> String:
	match state:
		Status.ONLINE:
			return "%s · online · %d ms" % [address, rtt]
		Status.UNREACHABLE:
			return "%s · unreachable — check Settings → Network" % address
		_:
			return "Checking %s…" % address


## Semantic color: green online, red unreachable, dim while checking.
static func chip_color(state: Status) -> Color:
	match state:
		Status.ONLINE:
			return PartyTheme.SUCCESS
		Status.UNREACHABLE:
			return PartyTheme.DANGER
		_:
			return PartyTheme.TEXT_DIM


## The Retry affordance shows only once a check has failed.
static func retry_visible(state: Status) -> bool:
	return state == Status.UNREACHABLE
