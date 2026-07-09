class_name BotGate
extends RefCounted
## Shared "don't wait on bots" gate (#819). Server-owned bots never
## explicitly ready up, vote, or lock in the way a real player does, so a
## naive "wait for everyone" check blocks the whole room until a bot's own
## (sometimes fallible) brain gets around to acting, or the phase times out.
## Everywhere that gates on the full roster acting — the intro skip vote,
## per-minigame lock-ins — should gate on humans_or_everyone() instead.


## `candidate_slots` filtered down to the non-bot subset, or `candidate_slots`
## itself unfiltered if that subset would be empty. An all-bot room (debug
## harnesses, CI render-pipeline clips) has nobody to wait FOR, so it falls
## back to requiring everyone — keeping those rooms playing out a normal
## round instead of resolving every gate instantly.
static func humans_or_everyone(candidate_slots: Array[int], bot_slots: Array[int]) -> Array[int]:
	var humans: Array[int] = []
	for slot in candidate_slots:
		if slot not in bot_slots:
			humans.append(slot)
	return humans if not humans.is_empty() else candidate_slots
