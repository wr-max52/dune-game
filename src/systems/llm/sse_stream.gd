class_name SSEStream
extends RefCounted
## Server-sent events parser (M12). Pure: feed it raw body bytes as they arrive
## (any split, including mid-line and mid-UTF-8-character) and it returns the
## complete events. Bytes are only decoded once an event is whole, so a multibyte
## character cut across two network chunks is never mangled.
##
## Each event: { "event": <name or "">, "data": <String>, "json": <parsed or null>,
## "done": <true for the OpenAI "[DONE]" sentinel> }

var _buf := PackedByteArray()
var done := false


func feed(bytes: PackedByteArray) -> Array:
	_buf.append_array(bytes)
	var out: Array = []
	while true:
		var cut := _find_boundary()
		if cut.x < 0:
			break
		var raw := _buf.slice(0, cut.x).get_string_from_utf8()
		_buf = _buf.slice(cut.x + cut.y)
		var ev := _parse_event(raw)
		if not ev.is_empty():
			out.append(ev)
	return out


## Whatever is left when the connection closes (a server that forgot the final
## blank line).
func flush() -> Array:
	if _buf.is_empty():
		return []
	var raw := _buf.get_string_from_utf8()
	_buf = PackedByteArray()
	var ev := _parse_event(raw)
	return [ev] if not ev.is_empty() else []


## Find the first blank line: returns Vector2i(index, separator length) or (-1, 0).
func _find_boundary() -> Vector2i:
	var n := _buf.size()
	for i in n:
		if _buf[i] == 10:   # \n
			if i + 1 < n and _buf[i + 1] == 10:
				return Vector2i(i, 2)
			if i + 2 < n and _buf[i + 1] == 13 and _buf[i + 2] == 10:
				return Vector2i(i, 3)
	return Vector2i(-1, 0)


func _parse_event(raw: String) -> Dictionary:
	var name := ""
	var data_lines: PackedStringArray = []
	for line in raw.replace("\r", "").split("\n"):
		if line.begins_with(":") or line == "":
			continue
		if line.begins_with("data:"):
			data_lines.append(line.substr(5).trim_prefix(" "))
		elif line.begins_with("event:"):
			name = line.substr(6).strip_edges()
	if data_lines.is_empty():
		return {}
	var data := "\n".join(data_lines)
	if data.strip_edges() == "[DONE]":
		done = true
		return { "event": name, "data": data, "json": null, "done": true }
	var parsed = JSON.parse_string(data)
	return { "event": name, "data": data, "json": parsed, "done": false }
