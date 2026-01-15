extends RefCounted
class_name Room

var id: int = 0
var type_id: String = ""
var kind: String = ""

var pos: Vector2i = Vector2i.ZERO
var size: Vector2i = Vector2i.ONE

var known: bool = true
var slots: Array = []


static func from_dict(d: Dictionary) -> Room:
	var r := Room.new()
	r.id = d.get("id", 0)
	r.type_id = d.get("type_id", "")
	r.kind = d.get("kind", "")
	r.pos = d.get("pos", Vector2i.ZERO)
	r.size = d.get("size", Vector2i.ONE)
	r.known = d.get("known", true)
	r.slots = d.get("slots", [])
	return r


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type_id": type_id,
		"kind": kind,
		"pos": pos,
		"size": size,
		"known": known,
		"slots": slots,
	}



