class_name StatsStore
extends RefCounted
## Local stats & match history (M20-03, #712 — v1, local-only per the owner's
## approved scope; unlocks/cosmetics/anything server-side are explicitly out).
## Persisted to user://stats.json. Mirrors SettingsStore's file pattern: pure
## load/save/sanitize/record functions, unit-tested without touching a live
## match. Recorded client-side from the podium standings and this session's
## own round history — no protocol change.

const PATH := "user://stats.json"
## Newest-first cap on the recent-match list.
const MAX_RECENT := 10

const DEFAULTS := {
	"matches": 0,
	"wins": 0,
	"podiums": 0,
	## game_id (String) -> {"plays": int, "wins": int}.
	"games": {},
	## Lifetime end-of-match superlatives (#934): award_id (String) -> count.
	"awards": {},
	## Persistent coin wallet (#935): banked match earnings, spent on hats.
	"coins": 0,
	## Newest first: {date (unix seconds), placement (1-based), player_count,
	## standout_game (String, "" if no round completed), standout_placement}.
	"recent": [],
}


static func load_stats() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return defaults()
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return defaults()
	return sanitize(parsed)


static func save_stats(stats: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(sanitize(stats)))
	file.close()


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## Clamps and type-coerces every field; unknown keys are dropped and missing
## keys fall back to DEFAULTS, so a hand-edited or corrupt file cannot poison
## the client (mirrors SettingsStore.sanitize's contract).
static func sanitize(raw: Dictionary) -> Dictionary:
	var clean := defaults()
	clean.matches = maxi(0, int(raw.get("matches", 0)))
	clean.wins = maxi(0, int(raw.get("wins", 0)))
	clean.podiums = maxi(0, int(raw.get("podiums", 0)))
	var raw_games: Variant = raw.get("games", {})
	if raw_games is Dictionary:
		for game_id: String in raw_games:
			var entry: Variant = raw_games[game_id]
			if entry is Dictionary:
				clean.games[game_id] = {
					"plays": maxi(0, int(entry.get("plays", 0))),
					"wins": maxi(0, int(entry.get("wins", 0))),
				}
	clean.coins = maxi(0, int(raw.get("coins", 0)))
	var raw_awards: Variant = raw.get("awards", {})
	if raw_awards is Dictionary:
		for award_id: String in raw_awards:
			clean.awards[award_id] = maxi(0, int(raw_awards[award_id]))
	var raw_recent: Variant = raw.get("recent", [])
	if raw_recent is Array:
		for entry: Variant in raw_recent:
			if entry is Dictionary and entry.has("date") and entry.has("placement"):
				(
					clean
					. recent
					. append(
						{
							"date": int(entry.date),
							"placement": maxi(1, int(entry.placement)),
							"player_count": maxi(1, int(entry.get("player_count", 1))),
							"standout_game": String(entry.get("standout_game", "")),
							"standout_placement": maxi(0, int(entry.get("standout_placement", 0))),
						}
					)
				)
	clean.recent = clean.recent.slice(0, MAX_RECENT)
	return clean


## Pure transform: folds one completed match's outcome into `stats`, returning
## the updated copy. `result` = {date: int (unix seconds), placement: int
## (1-based, this client's final rank), player_count: int, rounds: [{game_id,
## placement}, ...] (this client's rank in each ordinary round it finished;
## the finale is out of v1 scope, same as unlocks)}.
static func record_match(stats: Dictionary, result: Dictionary) -> Dictionary:
	var clean := sanitize(stats)
	clean.matches += 1
	# Bank this match's coins into the wallet (#935).
	clean.coins += maxi(0, int(result.get("coins_earned", 0)))
	# Lifetime superlative tally (#934): the award ids this client took home.
	for award_id: Variant in result.get("my_awards", []):
		var key := String(award_id)
		clean.awards[key] = int(clean.awards.get(key, 0)) + 1
	var placement := int(result.get("placement", 0))
	if placement == 1:
		clean.wins += 1
	if placement in [1, 2, 3]:
		clean.podiums += 1
	var standout_game := ""
	var standout_placement := 0
	var rounds: Array = result.get("rounds", [])
	for round: Dictionary in rounds:
		var game_id := String(round.get("game_id", ""))
		if game_id.is_empty():
			continue
		if not clean.games.has(game_id):
			clean.games[game_id] = {"plays": 0, "wins": 0}
		clean.games[game_id].plays += 1
		var round_placement := int(round.get("placement", 0))
		if round_placement == 1:
			clean.games[game_id].wins += 1
		# Best (lowest) placement across the match's rounds; a 0 (didn't
		# finish that round) never wins the comparison.
		if (
			round_placement > 0
			and (standout_placement == 0 or round_placement < standout_placement)
		):
			standout_placement = round_placement
			standout_game = game_id
	(
		clean
		. recent
		. push_front(
			{
				"date": int(result.get("date", 0)),
				"placement": placement,
				"player_count": maxi(1, int(result.get("player_count", 1))),
				"standout_game": standout_game,
				"standout_placement": standout_placement,
			}
		)
	)
	clean.recent = clean.recent.slice(0, MAX_RECENT)
	return clean


## Wardrobe purchase (#935): deducts `amount` from the wallet and returns the
## updated stats, or the unchanged stats if it can't be afforded. Pure.
static func spend(stats: Dictionary, amount: int) -> Dictionary:
	var clean := sanitize(stats)
	if amount <= 0 or amount > int(clean.coins):
		return clean
	clean.coins = int(clean.coins) - amount
	return clean
