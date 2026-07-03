class_name Updater
extends Node
## Downloads a release zip and stages it for a swap-on-relaunch (#144).
## Never silent: the caller prompts before download_and_stage() and again
## before apply_and_restart(). The swap itself runs as a detached shell
## script after the game quits, because a running executable cannot replace
## itself (notably on Windows).

signal staged(version: String)
signal failed(reason: String)

const UPDATE_DIR := "user://updates"

var _request: HTTPRequest
var _version := ""
var _zip_path := ""


func _ready() -> void:
	_request = HTTPRequest.new()
	add_child(_request)
	_request.request_completed.connect(_on_download_completed)


## Downloads the release asset into user://updates and unpacks it into a
## staging folder next to it. Emits staged(version) or failed(reason).
func download_and_stage(version: String, url: String) -> void:
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_version = version
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	_zip_path = "%s/%s" % [UPDATE_DIR, url.get_file()]
	_request.download_file = _zip_path
	if _request.request(url) != OK:
		failed.emit("Could not start the download.")


func _on_download_completed(
	result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		failed.emit("Download failed (HTTP %d)." % response_code)
		return
	var stage_dir := stage_dir_for(_version)
	if not _unpack(_zip_path, stage_dir):
		failed.emit("Could not unpack the update.")
		return
	staged.emit(_version)


## Launches the detached swap script and quits; the script waits for this
## process to exit, replaces the install, and relaunches the new build.
func apply_and_restart() -> void:
	if OS.has_feature("editor"):
		# A dev run's executable is the Godot editor itself — swapping that
		# would delete the editor. Exported builds only.
		failed.emit("Self-update only runs in exported builds.")
		return
	var script_path := _write_swap_script()
	if script_path.is_empty():
		failed.emit("Could not prepare the update script.")
		return
	var pid: int
	if OS.get_name() == "Windows":
		pid = OS.create_process("cmd.exe", ["/C", script_path])
	else:
		pid = OS.create_process("/bin/sh", [script_path])
	if pid <= 0:
		failed.emit("Could not launch the update script.")
		return
	get_tree().quit()


static func stage_dir_for(version: String) -> String:
	return "%s/staged-%s" % [UPDATE_DIR, version]


func _unpack(zip_path: String, dest_dir: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return false
	DirAccess.make_dir_recursive_absolute(dest_dir)
	for entry in reader.get_files():
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute("%s/%s" % [dest_dir, entry])
			continue
		DirAccess.make_dir_recursive_absolute("%s/%s" % [dest_dir, entry.get_base_dir()])
		var out := FileAccess.open("%s/%s" % [dest_dir, entry], FileAccess.WRITE)
		if out == null:
			reader.close()
			return false
		out.store_buffer(reader.read_file(entry))
		out.close()
	reader.close()
	return _unpack_nested_zip(dest_dir)


## Release assets wrap the build in a second zip (party-rush.zip inside
## party-rush-<platform>-<tag>.zip); when the staged dir holds only a zip,
## unpack that one in place too.
func _unpack_nested_zip(dest_dir: String) -> bool:
	var dirs := DirAccess.get_directories_at(dest_dir)
	var files := DirAccess.get_files_at(dest_dir)
	if not dirs.is_empty() or files.size() != 1 or not files[0].ends_with(".zip"):
		return true
	var inner := "%s/%s" % [dest_dir, files[0]]
	if not _unpack_flat(inner, dest_dir):
		return false
	DirAccess.remove_absolute(inner)
	return true


## _unpack minus the nested-zip pass, so two wrappers can't recurse forever.
func _unpack_flat(zip_path: String, dest_dir: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return false
	for entry in reader.get_files():
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute("%s/%s" % [dest_dir, entry])
			continue
		DirAccess.make_dir_recursive_absolute("%s/%s" % [dest_dir, entry.get_base_dir()])
		var out := FileAccess.open("%s/%s" % [dest_dir, entry], FileAccess.WRITE)
		if out == null:
			reader.close()
			return false
		out.store_buffer(reader.read_file(entry))
		out.close()
	reader.close()
	return true


## The swap script: wait for us to exit, replace the install with the staged
## build, clear macOS quarantine on files we created ourselves, relaunch.
func _write_swap_script() -> String:
	var staged_root := ProjectSettings.globalize_path(stage_dir_for(_version))
	var exe := OS.get_executable_path()
	var script_path := ProjectSettings.globalize_path("%s/apply-%s" % [UPDATE_DIR, _version])
	var body: String
	match OS.get_name():
		"macOS":
			# exe = <install>/<App>.app/Contents/MacOS/<bin>; swap the .app.
			var app_dir := exe.get_base_dir().get_base_dir().get_base_dir()
			var install_dir := app_dir.get_base_dir()
			var app_name := app_dir.get_file()
			script_path += ".sh"
			# Verify the staged app exists before touching the install; the
			# rm-then-mv order must never strand the user appless. ZIPReader
			# does not restore unix modes, so re-mark the binaries executable.
			body = (
				"#!/bin/sh\nsleep 2\n"
				+ '[ -d "%s/%s" ] || exit 1\n' % [staged_root, app_name]
				+ 'rm -rf "%s"\n' % app_dir
				+ 'mv "%s/%s" "%s/"\n' % [staged_root, app_name, install_dir]
				+ 'chmod -R +x "%s/%s/Contents/MacOS" 2>/dev/null\n' % [install_dir, app_name]
				+ 'xattr -dr com.apple.quarantine "%s/%s" 2>/dev/null\n' % [install_dir, app_name]
				+ 'open "%s/%s"\n' % [install_dir, app_name]
			)
		"Windows":
			var install_dir := exe.get_base_dir()
			script_path += ".bat"
			body = (
				"@echo off\r\ntimeout /t 2 /nobreak >nul\r\n"
				+ 'robocopy "%s" "%s" /E /MOVE >nul\r\n' % [staged_root, install_dir]
				+ 'start "" "%s"\r\n' % exe
			)
		_:
			var install_dir := exe.get_base_dir()
			script_path += ".sh"
			body = (
				"#!/bin/sh\nsleep 2\n"
				+ 'cp -Rf "%s/." "%s/"\n' % [staged_root, install_dir]
				+ 'chmod +x "%s"\n' % exe
				+ '"%s" &\n' % exe
			)
	var out := FileAccess.open(script_path, FileAccess.WRITE)
	if out == null:
		return ""
	out.store_string(body)
	out.close()
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", script_path])
	return script_path
