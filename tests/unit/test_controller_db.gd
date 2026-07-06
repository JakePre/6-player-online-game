extends GutTest
## Controller compatibility layer (M17-01, #569): the bundled community SDL
## DB parses per platform, ships non-trivially large for every desktop OS,
## and installs into the Input singleton without error.

const SAMPLE := """
# comment line

aaaa,Pad One,a:b0,platform:Windows,
bbbb,Pad Two,a:b0,platform:Mac OS X,
cccc,Pad Three,a:b0,platform:Linux,
dddd,Pad Four,a:b0,platform:Windows,
"""


func test_mappings_filter_by_exact_platform() -> void:
	assert_eq(ControllerDb.mappings_for(SAMPLE, "Windows").size(), 2)
	assert_eq(ControllerDb.mappings_for(SAMPLE, "Mac OS X").size(), 1)
	assert_eq(ControllerDb.mappings_for(SAMPLE, "Linux").size(), 1)
	assert_eq(ControllerDb.mappings_for(SAMPLE, "").size(), 0, "no platform, no mappings")


func test_comments_and_blanks_are_skipped() -> void:
	for mapping in ControllerDb.mappings_for(SAMPLE, "Windows"):
		assert_false(mapping.begins_with("#"))
		assert_false(mapping.is_empty())


func test_bundled_db_covers_every_desktop_platform_generously() -> void:
	var text := FileAccess.get_file_as_string(ControllerDb.DB_PATH)
	assert_false(text.is_empty(), "the DB ships in the project")
	# Floors well under the current counts (860/317/727) so routine upstream
	# refreshes never trip this, while a truncated or wrong file still fails.
	assert_gt(ControllerDb.mappings_for(text, "Windows").size(), 500)
	assert_gt(ControllerDb.mappings_for(text, "Mac OS X").size(), 200)
	assert_gt(ControllerDb.mappings_for(text, "Linux").size(), 400)


func test_install_loads_mappings_on_desktop() -> void:
	if ControllerDb.platform_tag().is_empty():
		pass_test("non-desktop platform: install is a documented no-op")
		return
	assert_gt(ControllerDb.install(), 500, "boot install loads the real DB")
