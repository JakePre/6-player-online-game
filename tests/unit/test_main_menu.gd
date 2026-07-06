extends GutTest
## Main menu scene (M16-03 rebuild): validates the restyled scene keeps every
## node main_menu.gd depends on, plus the new backdrop and logo-lockup slots.
## The scene is inspected via SceneState rather than instantiated — its _ready
## fires a real update-check HTTP request, which a unit test must not do.

const SCENE_PATH := "res://src/client/screens/main_menu.tscn"

## Every node main_menu.gd reaches by unique name (%Name) — dropping any of
## these in a scene rebuild would crash the live menu.
const REQUIRED_NODES: Array[String] = [
	"NameEdit",
	"CodeEdit",
	"HostButton",
	"JoinButton",
	"RejoinButton",
	"SettingsButton",
	"CreditsButton",
	"QuitButton",
	"AdvancedToggle",
	"AdvancedBox",
	"AddressEdit",
	"PortEdit",
	"StatusLabel",
	"UpdateButton",
	"ServerStatus",
]


func _scene_node_names() -> Array[String]:
	var scene: PackedScene = load(SCENE_PATH)
	var state := scene.get_state()
	var names: Array[String] = []
	for i in state.get_node_count():
		names.append(state.get_node_name(i))
	return names


func test_scene_loads() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	assert_true(scene.can_instantiate(), "the rebuilt menu scene is valid")


func test_keeps_every_node_the_script_depends_on() -> void:
	var names := _scene_node_names()
	for required in REQUIRED_NODES:
		assert_true(required in names, "menu keeps %%%s (script depends on it)" % required)


func test_has_the_animated_backdrop_and_logo_lockup() -> void:
	var names := _scene_node_names()
	assert_true("Backdrop" in names, "the animated backdrop is behind the menu")
	assert_true("LogoText" in names, "the text logo lockup is the no-art fallback")
	assert_true("LogoImage" in names, "with a hidden slot for the real logo when it lands")
