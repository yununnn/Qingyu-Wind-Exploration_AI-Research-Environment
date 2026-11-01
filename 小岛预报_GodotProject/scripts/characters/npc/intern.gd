extends Npc
class_name Intern
## 实习生：玩家收集完三处天气数据后，可以找他上交，换回"三天后还有暴雨"的情报。

## 上交数据需要的最小步骤（第 6 步 = 已收集完天气数据）
const SUBMIT_STEP := 6


func _try_start_dialogue() -> void:
	# 数据还没集齐，不触发上交流程
	if GameState.step < SUBMIT_STEP:
		return
	# 已经交过了，不再重复
	if GameState.step > SUBMIT_STEP:
		return

	DialogueManager.show_dialogue_balloon_scene(
		"res://scenes/widget/dialogue/balloon.tscn",
		load("res://dialogues/laboratory/intern_submit.dialogue"),
		"start"
	)
	await DialogueManager.dialogue_ended

	# 交完数据，进入下一步
	GameState.step = SUBMIT_STEP + 1
	TaskPanel._change_task("回到农场提前采集成熟的胡萝卜，放入箱子")
	TipAction._change_tip("互动：E")
