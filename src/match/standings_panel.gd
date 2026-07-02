class_name StandingsPanel
extends PanelContainer
## Standings display (M3-05) shared by the every-5-rounds leaderboard
## interstitial and the final podium: rows reveal bottom-up (last place
## first) for the SPEC $4 dramatic reveal. Pure presentation — callers
## format lines with MatchFormat.

## Seconds between row reveals; callers may shorten it (tests, quick rounds).
var reveal_interval := 0.5

var _tween: Tween

@onready var _title: Label = %StandingsTitle
@onready var _subtitle: Label = %StandingsSubtitle
@onready var _list: VBoxContainer = %StandingsList


## Lines are ordered best-first (MatchFormat.standings_lines). With `reveal`
## the rows appear from last place up to the winner.
func show_lines(title: String, subtitle: String, lines: Array[String], reveal := true) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	if _tween != null:
		_tween.kill()
	for child in _list.get_children():
		child.queue_free()
	var rows: Array[Label] = []
	for line in lines:
		var row := Label.new()
		row.text = line
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.visible = not reveal
		_list.add_child(row)
		rows.append(row)
	if not reveal or rows.is_empty():
		return
	_tween = create_tween()
	for i in range(rows.size() - 1, -1, -1):
		var row := rows[i]
		_tween.tween_callback(func() -> void: row.visible = true)
		if i > 0:
			_tween.tween_interval(reveal_interval)


func revealed_count() -> int:
	var count := 0
	for child: Label in _list.get_children():
		if child.visible:
			count += 1
	return count
