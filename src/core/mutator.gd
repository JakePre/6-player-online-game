class_name Mutator
extends RefCounted
## One round modifier (M9-01, PHASE2.md $3). Mutators work on framework knobs
## only — award multiplier, pickup-cap scale, duration scale, speed scale, a
## server-side input transform, view flags, and a round-end coin transfer —
## never on per-minigame bespoke code. Anything a mutator needs beyond these
## knobs is a framework PR first.
##
## M9-02/03 wire the pool + per-round roll; M9-04/05 register the launch
## catalog (one MutatorCatalog.register line per mutator, like minigames).

enum InputTransform {
	NONE,
	## Server-side horizontal flip of move intent (Mirror Mode): fair and
	## cheat-proof because clients never see their own inputs untransformed.
	MIRROR,
}

var id: StringName
var display_name := ""
## One-liner for the intro card announcement (rule: no hidden modifiers).
var blurb := ""
var award_multiplier := 1.0
var pickup_cap_scale := 1.0
var duration_scale := 1.0
var speed_scale := 1.0
var input_transform := InputTransform.NONE
## Flags the views react to (e.g. &"blackout", &"hide_nameplates"); carried
## in the round_intro payload.
var view_flags: Array[StringName] = []
## Robin Hood knob: at round end, last place takes this many coins from
## first place. 0 = off.
var end_transfer_amount := 0


static func create(values: Dictionary) -> Mutator:
	var mutator := Mutator.new()
	mutator.id = values.id
	mutator.display_name = values.get("name", String(values.id))
	mutator.blurb = values.get("blurb", "")
	mutator.award_multiplier = values.get("award_multiplier", 1.0)
	mutator.pickup_cap_scale = values.get("pickup_cap_scale", 1.0)
	mutator.duration_scale = values.get("duration_scale", 1.0)
	mutator.speed_scale = values.get("speed_scale", 1.0)
	mutator.input_transform = values.get("input_transform", InputTransform.NONE)
	mutator.view_flags.assign(values.get("view_flags", []))
	mutator.end_transfer_amount = values.get("end_transfer", 0)
	return mutator


## Intro-card / replication payload (everything a client needs to announce
## and render the round; server-side knobs stay server-side).
func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"blurb": blurb,
		"view_flags": view_flags.duplicate(),
	}


# --- Knob application (server side) -------------------------------------------


## Scales every entry of an Economy award dict (slot -> coins), rounding to
## whole coins.
func apply_award_multiplier(awards: Dictionary) -> Dictionary:
	if is_equal_approx(award_multiplier, 1.0):
		return awards
	var scaled := {}
	for slot: int in awards:
		scaled[slot] = roundi(int(awards[slot]) * award_multiplier)
	return scaled


func scaled_pickup_cap(base_cap: int) -> int:
	return roundi(base_cap * pickup_cap_scale)


## Feeds the existing duration_override path (MatchController).
func scaled_duration(base_sec: float) -> float:
	return base_sec * duration_scale


## Overdrive: the server scales its tick delta so everything moves faster.
func scaled_tick_delta(delta: float) -> float:
	return delta * speed_scale


## Applied in the server's input relay to the shared move intent
## ({"mx": .., "my": ..}); bespoke keys (jump/dash/press) pass through.
func transform_input(input: Dictionary) -> Dictionary:
	if input_transform == InputTransform.NONE or not input.has("mx"):
		return input
	var transformed := input.duplicate()
	transformed.mx = -float(input.mx)
	return transformed


## Round-end coin transfer (Robin Hood): every first-place player pays
## `end_transfer_amount` (never going below zero) into a pot that is split
## evenly among last-place players, remainder to the lowest slot. A full tie
## (one placement group) is a no-op. Returns the adjusted totals.
func apply_end_transfer(totals: Dictionary, placements: Array) -> Dictionary:
	if end_transfer_amount <= 0 or placements.size() < 2:
		return totals
	var first: Array = placements[0]
	var last: Array = placements[placements.size() - 1]
	if first.is_empty() or last.is_empty():
		return totals
	var adjusted := totals.duplicate()
	var pot := 0
	for slot: int in first:
		var paid := mini(end_transfer_amount, int(adjusted.get(slot, 0)))
		adjusted[slot] = int(adjusted.get(slot, 0)) - paid
		pot += paid
	var receivers: Array = last.duplicate()
	receivers.sort()
	var share := pot / receivers.size()
	var remainder := pot % receivers.size()
	for i in receivers.size():
		var slot: int = receivers[i]
		adjusted[slot] = int(adjusted.get(slot, 0)) + share + (1 if i < remainder else 0)
	return adjusted
