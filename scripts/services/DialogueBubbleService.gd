extends RefCounted
class_name DialogueBubbleService

const COOLDOWN_S := 1.2

var _next_ok_ms_by_actor: Dictionary = {} # adv_id -> Dictionary[key->ms]
var _bubble_scene: PackedScene = preload("res://ui/DialogueBubble.tscn")


func show_for_actor(actor: Node2D, text: String, key: String) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	text = String(text).strip_edges()
	if text == "":
		return
	key = String(key)
	if key == "":
		key = "default"

	var aid := int(actor.get_instance_id())
	var now_ms := Time.get_ticks_msec()
	var per: Dictionary = _next_ok_ms_by_actor.get(aid, {}) as Dictionary
	var next_ok := int(per.get(key, 0))
	if now_ms < next_ok:
		return
	per[key] = now_ms + int(COOLDOWN_S * 1000.0)
	_next_ok_ms_by_actor[aid] = per

	DbgLog.throttle(
		"bubble:%d:%s" % [aid, key],
		0.75,
		"Bubble adv=%d key=%s text=%s" % [aid, key, text],
		"ui",
		DbgLog.Level.DEBUG
	)

	var bubble := _bubble_scene.instantiate() as Node2D
	actor.add_child(bubble)
	if bubble.has_method("show_text"):
		bubble.call("show_text", text)

