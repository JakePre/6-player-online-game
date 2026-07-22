class_name AppVersion
## Single source of truth for the client build version (#144), compared
## against GitHub release tags by UpdateChecker. Bumped as part of the release
## checklist; stamping it automatically from the release workflow is the
## [INFRA] follow-up tracked on the claim issue.

const VERSION := "0.6.7"


## True when `tag` (a release tag like "v0.4.1" or "0.4.1") is a newer
## semantic version than `current`.
static func is_newer(tag: String, current: String = VERSION) -> bool:
	return _compare(_parts(tag), _parts(current)) > 0


static func _parts(version: String) -> Array[int]:
	var out: Array[int] = []
	for piece in version.strip_edges().trim_prefix("v").split("."):
		out.append(int(piece))
	while out.size() < 3:
		out.append(0)
	return out


static func _compare(a: Array[int], b: Array[int]) -> int:
	for i in 3:
		if a[i] != b[i]:
			return signi(a[i] - b[i])
	return 0
