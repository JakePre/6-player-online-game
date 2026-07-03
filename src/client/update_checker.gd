class_name UpdateChecker
extends Node
## Asks the GitHub Releases API whether a newer client build exists (#144).
## Opt-in and quiet: callers decide when to check() and what to show; this
## node only reports. Parsing is static so it is unit-testable offline.

signal update_available(version: String, download_url: String)
signal up_to_date
signal check_failed

const REPO := "JakePre/6-player-online-game"
const RELEASES_LATEST_URL := "https://api.github.com/repos/" + REPO + "/releases/latest"

## The version releases are compared against; overridable for testing.
var current_version := AppVersion.VERSION
## Which release asset to look for: a platform id for clients, or "server"
## for the dedicated-server build (#145).
var asset_platform := platform_id()

var _request: HTTPRequest


func _ready() -> void:
	_request = HTTPRequest.new()
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)


## Fires one of the three signals when the API answers. No-op while a check
## is already in flight.
func check() -> void:
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	if _request.request(RELEASES_LATEST_URL) != OK:
		check_failed.emit()


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_failed.emit()
		return
	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	if payload == null or not payload is Dictionary:
		check_failed.emit()
		return
	var release := parse_release(payload, asset_platform)
	if release.is_empty():
		check_failed.emit()
		return
	if AppVersion.is_newer(release.version, current_version):
		update_available.emit(release.version, release.download_url)
	else:
		up_to_date.emit()


## Extracts {version, download_url} for `platform` from a releases/latest
## payload; {} when the payload has no tag or no matching platform asset.
static func parse_release(payload: Dictionary, platform: String) -> Dictionary:
	var tag := String(payload.get("tag_name", "")).strip_edges()
	if tag.is_empty():
		return {}
	var wanted := asset_name(platform, tag)
	for asset: Dictionary in payload.get("assets", []):
		if String(asset.get("name", "")) == wanted:
			return {
				"version": tag.trim_prefix("v"),
				"download_url": String(asset.get("browser_download_url", "")),
			}
	return {}


## Release assets follow party-rush-<platform>-v<semver>.zip (see release.yml).
static func asset_name(platform: String, tag: String) -> String:
	var tagged := tag if tag.begins_with("v") else "v" + tag
	return "party-rush-%s-%s.zip" % [platform, tagged]


static func platform_id() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		_:
			return "linux"


## The dedicated-server build ships per-OS assets: `server` is the Linux
## build, `server-windows` the #171 Windows app. Picking by OS here keeps
## ServerUpdater from installing a Linux zip over a Windows install.
static func server_platform_id() -> String:
	return "server-windows" if OS.get_name() == "Windows" else "server"
