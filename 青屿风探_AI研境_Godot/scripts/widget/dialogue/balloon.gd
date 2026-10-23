extends CanvasLayer
## 与对话管理器一起使用的基本对话气泡。


## 对话资源
@export var dialogue_resource: DialogueResource

## 使用气泡作为场景中的[节点]时，从给定的提示开始。
@export var start_from_cue: String = ""

## 如果在场景中作为[节点]运行，则自动启动对话。
@export var auto_start: bool = false

## 如果只要显示对话，所有其他输入都被阻止。
@export var will_block_other_input: bool = true

## 用于推进对话的动作
@export var next_action: StringName = &"ui_accept"

## 用于跳过输入对话的操作
@export var skip_action: StringName = &"ui_cancel"

## 语音线路的声音播放器（如果存在）。
@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer

## 对话气泡的画板
@onready var panel: PanelContainer = %PanelContainer
## 对话气泡的边距面板
@onready var margin_container: MarginContainer = $Balloon/MarginContainer


## 对话标记
var marker: DialogueMarker2D
## 动效播放器
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 临时游戏状态
var temporary_game_states: Array = []

## 看看我们是否在等待玩家
var is_waiting_for_input: bool = false

## 看看我们是否正在运行长突变并且应该隐藏气泡
var will_hide_balloon: bool = false

## 用于存储任何临时变量的字典
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## 当前行
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# 对话已经结束，离气泡很近
			if owner == null:
				# 退场动效
				animation_player.play_backwards("show_hide")
				await animation_player.animation_finished

				queue_free()
			else:
				# 退场动效
				animation_player.play_backwards("show_hide")
				await animation_player.animation_finished

				hide()
	get:
		return dialogue_line

## 一个冷却计时器，用于在遇到突变时延迟气泡隐藏。
var mutation_cooldown: Timer = Timer.new()

## 底座气泡锚
@onready var balloon: Control = %Balloon

## 显示当前对话的标签
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## 回复菜单
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu



func _ready() -> void:
	balloon.hide()


	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	# 如果响应菜单没有设置下一个操作，请使用此操作
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)

	if auto_start:
		if not is_instance_valid(dialogue_resource):
			assert(false, DMConstants.get_error_message(DMConstants.ERR_MISSING_RESOURCE_FOR_AUTOSTART))
		start()



func _unhandled_input(_event: InputEvent) -> void:
	# 仅允许气泡在显示时处理输入
	if will_block_other_input:
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	## 检测区域设置的更改并更新当前对话行以显示新语言
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio: float = dialogue_label.visible_ratio
		await dialogue_line.refresh()
		if visible_ratio < 1:
			dialogue_label.skip_typing()


## 开始一些对话
func start(with_dialogue_resource: DialogueResource = null, cue: String = "", extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	if is_instance_valid(with_dialogue_resource):
		dialogue_resource = with_dialogue_resource
	if not cue.is_empty():
		start_from_cue = cue
	dialogue_line = await dialogue_resource.get_next_dialogue_line(start_from_cue, temporary_game_states)

	show()


## 将任何更改应用于给定新的 [DialogueLine] 的气泡。
func apply_dialogue_line() -> void:
	
	marker = _get_marker(dialogue_line.character)
	# ... 下面保持现有 balloon.gd 的全部逻辑不变

	mutation_cooldown.stop()

	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()


	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	# 展示我们的气泡
	balloon.show()
	# 出现动效
	animation_player.play("show_hide")

	will_hide_balloon = false

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	# 等待下一行
	if dialogue_line.has_tag("voice"):
		audio_stream_player.stream = load(dialogue_line.get_tag_value("voice"))
		audio_stream_player.play()
		await audio_stream_player.finished
		next(dialogue_line.next_id)
	elif dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time: float = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


## 转到下一行
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


#区域信号


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false

		# 退场动效
		animation_player.play_backwards("show_hide")
		await animation_player.animation_finished

		balloon.hide()


func _on_mutated(mutation: Dictionary) -> void:
	if not mutation.is_inline:
		is_waiting_for_input = false
		will_hide_balloon = true
		mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	# 看看我们是否需要跳过对话的输入
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	# 当没有响应选项时，气泡本身就是可点击的东西
	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		next(dialogue_line.next_id)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


## 查找场景中给定角色名称的标记。
func _get_marker(character: String) -> DialogueMarker2D:
	return DialogueMarker2D.find_for_character(character)


func _process(_delta: float) -> void:
	if not is_instance_valid(marker): return
	# 设置新位置
	var new_pos: Vector2 = marker.get_position_in_viewport()
	transform = Transform2D(0, new_pos)
