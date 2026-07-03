extends GutTest
## Client self-update (#144): semver comparison and releases/latest payload
## parsing. Network and swap behavior are exercised manually — these cover
## every decision the flow makes offline.

const PAYLOAD := {
	"tag_name": "v0.4.0",
	"assets":
	[
		{
			"name": "party-rush-linux-v0.4.0.zip",
			"browser_download_url": "https://example.com/linux.zip",
		},
		{
			"name": "party-rush-macos-v0.4.0.zip",
			"browser_download_url": "https://example.com/macos.zip",
		},
		{
			"name": "party-rush-server-v0.4.0.zip",
			"browser_download_url": "https://example.com/server.zip",
		},
	],
}


func test_is_newer_semver() -> void:
	assert_true(AppVersion.is_newer("v0.4.0", "0.3.0"))
	assert_true(AppVersion.is_newer("1.0.0", "0.9.9"))
	assert_true(AppVersion.is_newer("v0.3.1", "0.3.0"))
	assert_false(AppVersion.is_newer("v0.3.0", "0.3.0"))
	assert_false(AppVersion.is_newer("0.2.9", "0.3.0"))
	assert_false(AppVersion.is_newer("v0.3", "0.3.0"), "missing parts pad to zero")


func test_parse_release_picks_platform_asset() -> void:
	var release := UpdateChecker.parse_release(PAYLOAD, "macos")
	assert_eq(release.version, "0.4.0")
	assert_eq(release.download_url, "https://example.com/macos.zip")
	assert_eq(
		UpdateChecker.parse_release(PAYLOAD, "linux").download_url, "https://example.com/linux.zip"
	)


func test_parse_release_rejects_unusable_payloads() -> void:
	assert_eq(UpdateChecker.parse_release({}, "macos"), {})
	assert_eq(UpdateChecker.parse_release({"tag_name": "v0.4.0", "assets": []}, "windows"), {})
	assert_eq(
		UpdateChecker.parse_release(PAYLOAD, "windows"), {}, "no windows asset in this payload"
	)


func test_asset_name_normalizes_tag() -> void:
	assert_eq(UpdateChecker.asset_name("macos", "v0.4.0"), "party-rush-macos-v0.4.0.zip")
	assert_eq(UpdateChecker.asset_name("windows", "0.4.0"), "party-rush-windows-v0.4.0.zip")


## #145: the dedicated server reuses the same flow with the "server" asset.
func test_parse_release_finds_the_server_asset() -> void:
	var release := UpdateChecker.parse_release(PAYLOAD, "server")
	assert_eq(release.version, "0.4.0")
	assert_eq(release.download_url, "https://example.com/server.zip")


## #172: the Windows server app must update from its own asset, never the
## Linux `server` zip — `server` would match first if selection were fuzzy.
func test_parse_release_picks_the_per_os_server_asset() -> void:
	var payload := {
		"tag_name": "v0.5.0",
		"assets":
		[
			{
				"name": "party-rush-server-v0.5.0.zip",
				"browser_download_url": "https://example.com/server-linux.zip",
			},
			{
				"name": "party-rush-server-windows-v0.5.0.zip",
				"browser_download_url": "https://example.com/server-windows.zip",
			},
		],
	}
	assert_eq(
		UpdateChecker.parse_release(payload, "server").download_url,
		"https://example.com/server-linux.zip"
	)
	assert_eq(
		UpdateChecker.parse_release(payload, "server-windows").download_url,
		"https://example.com/server-windows.zip"
	)
	var expected := "server-windows" if OS.get_name() == "Windows" else "server"
	assert_eq(UpdateChecker.server_platform_id(), expected)
