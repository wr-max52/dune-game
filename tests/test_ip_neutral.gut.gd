extends GutTest
## M0: IP-neutrality guard. Scans every source file for franchise names. None
## may appear in code, class names, file names, or the data layer. Generic
## terms only. This test failing is a hard block on the merge.

const BANNED := [
	"gadget",
	"star wars",
	"the mand",
	"jar jar",
	"yaddle",
	"tatoo",
	"besp",
	"mandalorian",
	"jarjar",
	"starwars",
	"x-wing",
	"tie fighter",
	"millennium falcon",
]

## This file is the list itself, so it is the one file not scanned.
const SELF := "res://tests/test_ip_neutral.gut.gd"

const SCAN_DIRS := [
	"res://content",
	"res://src",
	"res://scenes",
	"res://tests",
	"res://scripts",
]

var _files := PackedStringArray()


func before_each() -> void:
	_files.clear()
	for root in SCAN_DIRS:
		# A trailing slash matters: "res://scenes" + "main.gd" is not a path, which
		# silently skipped every file at the top of each scanned folder.
		_walk(root.trim_suffix("/") + "/", _files)


func _walk(dir: String, out: PackedStringArray) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not name.begins_with(".") and name != "addons":
			var full := dir + name
			if da.current_is_dir():
				_walk(full + "/", out)
			else:
				out.append(full)
		name = da.get_next()
	da.list_dir_end()


func test_no_franchise_names_in_any_source_file() -> void:
	var offenders := PackedStringArray()
	for path in _files:
		if not path.ends_with(".gd") and not path.ends_with(".json") and \
			not path.ends_with(".txt") and not path.ends_with(".tscn") and \
			not path.ends_with(".cfg"):
			continue
		if path == SELF or not FileAccess.file_exists(path):
			continue
		var text: String = FileAccess.get_file_as_string(path).to_lower()
		for banned in BANNED:
			if text.contains(banned):
				offenders.append(path + " :: " + banned)
	assert_eq(offenders.size(), 0, "franchise names found: " + str(offenders))


func test_content_files_match_manifest() -> void:
	# Every id in the manifest must resolve to a file on disk.
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	for id in content.weapons:
		var f := FileAccess.file_exists("res://content/core/weapons/" + str(id) + ".json")
		assert_true(f, "weapon file exists: " + str(id))
