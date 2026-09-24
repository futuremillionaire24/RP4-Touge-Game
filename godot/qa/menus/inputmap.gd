extends SceneTree

func _init() -> void:
	for a in ["ui_accept", "ui_cancel", "ui_select", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next"]:
		var s := []
		for e in InputMap.action_get_events(a):
			s.append(e.as_text() + "(" + e.get_class() + ")")
		print("QA| ", a, " -> ", ", ".join(s))
	print("QA| version ", Engine.get_version_info().string)
	quit()
