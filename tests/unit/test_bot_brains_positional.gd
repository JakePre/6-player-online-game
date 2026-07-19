extends GutTest
## Positional-dodger bot brains (#926): tilt_deck and meteor_shower — steering
## assertions on crafted snapshots. Split from test_bot_brains.gd per gdlint's
## public-method cap (same precedent as test_bot_brains_chase_tag.gd). These
## cover the render-audit degeneracies: tilt_deck's all-centre stalemate and
## meteor_shower dodging into a second telegraph / off the zone.


func _play_state(id: String, game: Dictionary) -> Dictionary:
	return {"state": MatchController.State.PLAY, "minigame": id, "game": game}


# --- tilt_deck: break the all-centre stalemate --------------------------------


## A balanced deck with a rim coin: the bot ventures out for it instead of
## camping the no-tilt centre (which used to freeze the whole deck flat).
func test_tilt_deck_brain_ventures_for_a_rim_coin_when_balanced() -> void:
	var game := {
		"players": {0: [0.0, 0.0, 0]},
		"tilt": [0.0, 0.0],
		"deck_radius": 8.0,
		"coins": [[7.0, 0.0]],
		"cargo": [],
		"fallen": [],
	}
	var intent := BotBrains.brain_for(&"tilt_deck", 0, 1).think(_play_state("tilt_deck", game), {})
	assert_gt(
		float(intent.get("mx", 0.0)), 0.3, "heads out for the rim coin, breaking the centre camp"
	)


## Riding the rim past the danger fraction: abandon coins and scramble back.
func test_tilt_deck_brain_scrambles_back_when_riding_the_rim() -> void:
	var game := {
		"players": {0: [6.0, 0.0, 0]},
		"tilt": [0.3, 0.0],
		"deck_radius": 8.0,
		"coins": [[7.5, 0.0]],
		"cargo": [],
		"fallen": [],
	}
	var intent := BotBrains.brain_for(&"tilt_deck", 0, 1).think(_play_state("tilt_deck", game), {})
	assert_lt(float(intent.get("mx", 0.0)), 0.0, "heads back toward centre, away from the rim")


## A hard lean shrinks the coin reach: the bot resists the tilt rather than
## chasing a rim coin off the low edge.
func test_tilt_deck_brain_wont_chase_a_rim_coin_while_leaning() -> void:
	var game := {
		"players": {0: [0.0, 0.0, 0]},
		"tilt": [1.2, 0.0],
		"deck_radius": 8.0,
		"coins": [[7.0, 0.0]],
		"cargo": [],
		"fallen": [],
	}
	var intent := BotBrains.brain_for(&"tilt_deck", 0, 1).think(_play_state("tilt_deck", game), {})
	assert_lte(
		float(intent.get("mx", 0.0)), 0.0, "leans against the tilt instead of chasing the rim coin"
	)


# --- meteor_shower: score dodges against ALL telegraphs -----------------------


## A meteor on each side: fleeing either one straight-line runs into the other,
## so the bot dodges perpendicular, into neither.
func test_meteor_shower_brain_dodges_between_two_telegraphs() -> void:
	var game := {
		"players": {0: [0.0, 0.0]},
		"zone": [0.0, 0.0, 10.0],
		"meteors": [[-1.6, 0.0, 0.3], [1.6, 0.0, 0.3]],
	}
	var intent := BotBrains.brain_for(&"meteor_shower", 0, 1).think(
		_play_state("meteor_shower", game), {}
	)
	assert_lt(absf(float(intent.get("mx", 0.0))), 0.4, "doesn't dodge into either side meteor")
	assert_gt(
		absf(float(intent.get("my", 0.0))), 0.6, "dodges perpendicular, out from between them"
	)


## A meteor between the bot and centre near the zone rim: the dodge must not
## flee further out past the shrinking zone edge.
func test_meteor_shower_brain_dodges_without_leaving_the_zone() -> void:
	var game := {"players": {0: [8.0, 0.0]}, "zone": [0.0, 0.0, 8.5], "meteors": [[6.6, 0.0, 0.3]]}
	var intent := BotBrains.brain_for(&"meteor_shower", 0, 1).think(
		_play_state("meteor_shower", game), {}
	)
	assert_lte(float(intent.get("mx", 0.0)), 0.05, "does not dodge further out past the zone rim")
