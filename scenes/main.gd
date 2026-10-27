extends Node3D
## M0 boot scene. Proves the core data layer loads at runtime and is queryable
## by id, before any gameplay exists. This is the first "how I can see it" for
## M0: running the game prints what it loaded.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var _content: CoreContent


func _ready() -> void:
	_content = CoreContent.new()
	var ok := _content.load_from()
	print("DataLayer: load %s" % ("OK" if ok else "FAILED"))
	print("DataLayer: npcs=", _content.npcs.size(),
		" weapons=", _content.weapons.size(),
		" factions=", _content.factions.size(),
		" dialogues=", _content.dialogues.size(),
		" missions=", _content.missions.size())

	var cantina_owner: Dictionary = _content.get_npc("cantina_owner")
	print("DataLayer: cantina owner kind=", str(cantina_owner.get("kind", "MISSING")),
		" tools=", str(cantina_owner.get("tools", [])))
	if _content.get_persona("cantina_owner").length() == 0:
		push_error("DataLayer: cantina owner persona prompt is empty")
