class_name CreditsCatalog
extends RefCounted
## Parses assets/CREDITS.md into rows for the in-game credits screen (M7-04).
## The screen is generated from the ledger at runtime so the two can never
## drift; CREDITS.md ships in exports via the preset include_filter.

const CREDITS_PATH := "res://assets/CREDITS.md"


## Parses every markdown table in `text`. Returns rows as Dictionaries whose
## keys are the table's lower-cased column headers (e.g. asset, author,
## license, source).
static func parse(text: String) -> Array:
	var rows: Array = []
	var headers: Array = []
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("|"):
			headers = []
			continue
		var cells := _cells(line)
		if headers.is_empty():
			headers = cells.map(func(cell: String) -> String: return cell.to_lower())
			continue
		if _is_separator(cells):
			continue
		var row := {}
		for i in mini(headers.size(), cells.size()):
			row[headers[i]] = cells[i]
		rows.append(row)
	return rows


## Rows from the bundled CREDITS.md, or [] when the file is unavailable.
static func load_rows() -> Array:
	if not FileAccess.file_exists(CREDITS_PATH):
		return []
	return parse(FileAccess.get_file_as_string(CREDITS_PATH))


static func _cells(line: String) -> Array:
	var cells: Array = []
	for cell in line.trim_prefix("|").trim_suffix("|").split("|"):
		cells.append(cell.strip_edges())
	return cells


static func _is_separator(cells: Array) -> bool:
	for cell: String in cells:
		if cell.is_empty():
			continue
		for character in cell:
			if character != "-" and character != ":":
				return false
	return true
