extends RefCounted
## Reads the KEY=value traces the M11/M12 trace scenes write.

static func read(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var i := line.find("=")
		if i > 0:
			out[line.substr(0, i)] = line.substr(i + 1)
	return out
