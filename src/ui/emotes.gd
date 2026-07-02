class_name Emotes
extends RefCounted
## The six quick emotes (M3-07, SPEC $9 social layer). Indices are what goes
## over the wire; keep order stable — reordering is a protocol change.

const EMOTES: Array[String] = ["👍", "😂", "😱", "😡", "❤", "GG"]


static func is_valid(index: int) -> bool:
	return index >= 0 and index < EMOTES.size()


static func text(index: int) -> String:
	return EMOTES[index] if is_valid(index) else "?"
