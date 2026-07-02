extends GutTest
## Credits ledger parser (M7-04): markdown tables in assets/CREDITS.md
## become the in-game credits rows.

const SAMPLE := """
# Asset credits

Prose that is not a table.

| Asset | Path | Author | License | Source |
|---|---|---|---|---|
| Pack One | `assets/one/` | Alice | CC0 1.0 | https://example.com/one |
| Pack Two | `assets/two/` | Bob | CC-BY 4.0 | https://example.com/two |

More prose.

| Tool | Path | License |
|---|---|---|
| GUT 9.4.0 | `addons/gut/` | MIT |
"""


func test_parses_all_tables_with_lowercased_headers() -> void:
	var rows := CreditsCatalog.parse(SAMPLE)
	assert_eq(rows.size(), 3)
	assert_eq(rows[0].asset, "Pack One")
	assert_eq(rows[0].author, "Alice")
	assert_eq(rows[0].license, "CC0 1.0")
	assert_eq(rows[0].source, "https://example.com/one")
	assert_eq(rows[1].asset, "Pack Two")
	assert_eq(rows[2].tool, "GUT 9.4.0")
	assert_eq(rows[2].license, "MIT")
	assert_false(rows[2].has("author"))


func test_separator_and_prose_lines_are_not_rows() -> void:
	for row: Dictionary in CreditsCatalog.parse(SAMPLE):
		for value: String in row.values():
			assert_false(value.begins_with("---"))
			assert_false(value.contains("prose"))


func test_empty_and_tableless_text() -> void:
	assert_eq(CreditsCatalog.parse(""), [])
	assert_eq(CreditsCatalog.parse("just words\nno tables here"), [])


func test_bundled_credits_file_parses_with_expected_columns() -> void:
	var rows := CreditsCatalog.load_rows()
	assert_gt(rows.size(), 0, "repo CREDITS.md must yield rows")
	var kaykit_found := false
	for row: Dictionary in rows:
		if String(row.get("asset", "")).contains("KayKit"):
			kaykit_found = true
			assert_true(String(row.license).contains("CC0"))
			assert_true(row.has("author"))
	assert_true(kaykit_found, "KayKit packs must be credited")
