@icon("uid://s0s1348tpm6d")

@tool

## 专门用于[b]对话管理器[/b]对话的 RichTextLabel。
class_name DialogueLabel extends RichTextLabel


## 每打出一个字母就会发出一次。
signal spoke(letter: String, letter_index: int, speed: float)

## 当玩家跳过对话输入时发出。
signal skipped_typing()

## 开始打字时发出
signal started_typing()

## 键入完成时发出。
signal finished_typing()


## 按下可跳过打字的操作。
@export var skip_action: StringName = &"ui_cancel"

## 文本输入的速度。
@export var seconds_per_step: float = 0.02

## 遇到这些字符时自动短暂停顿。
@export var pause_at_characters: String = ".?!"

## 如果暂停后的字符是其中之一，则不要自动暂停。
@export var skip_pause_at_character_if_followed_by: String = ")\""

## 不要在这些缩写后自动暂停（仅当“.”位于 `pause_at_characters` 中时）。[br]
## 缩写长度限制为 5 个字符 [br]
## 不支持多句点缩写（例如“p.m.”）
@export var skip_pause_at_abbreviations: PackedStringArray = ["Mr", "Mrs", "Ms", "Dr", "etc", "eg", "ex"]

## 暴露“pause_at_characters”中存在的字符时暂停的时间量。
@export var seconds_per_pause_step: float = 0.3

var _already_mutated_indices: PackedInt32Array = []


## 当前的对话内容。
var dialogue_line: Variant:
	set(value):
		if value != dialogue_line:
			dialogue_line = value
			_update_text()
	get:
		return dialogue_line

## 标签当前是否正在自行输入。
var is_typing: bool = false:
	set(value):
		var did_just_finish: bool = _is_typing != value and value == false and visible_characters == get_total_character_count()
		_is_typing = value
		if did_just_finish:
			finished_typing.emit()
	get:
		return _is_typing and not _is_awaiting_mutation
var _is_typing: bool = false

var _last_wait_index: int = -1
var _last_mutation_index: int = -1
var _waiting_seconds: float = 0
var _is_awaiting_mutation: bool = false
var _is_skipping_mutations: bool = false


func _process(delta: float) -> void:
	if _is_typing:
		# 输入文本
		if visible_ratio < 1:
			# 看看我们是否在等待
			if _waiting_seconds > 0:
				_waiting_seconds = _waiting_seconds - delta
			# 如果我们不再等待，请继续输入
			if _waiting_seconds <= 0:
				_type_next(delta, _waiting_seconds)
		else:
			# 确保行末尾的任何突变都能运行
			_mutate_inline_mutations(get_total_character_count())
			is_typing = false


## 设置当前对话行中的标签文本。如果您愿意，可以覆盖
## 在你的子类中做一些更有趣的事情。
func _update_text() -> void:
	if is_instance_valid(dialogue_line):
		text = dialogue_line.text
	else:
		text = ""


## 开始输入文字
func type_out() -> void:
	_update_text()
	visible_characters = 0
	visible_ratio = 0
	_waiting_seconds = 0
	_last_wait_index = -1
	_last_mutation_index = -1
	_already_mutated_indices.clear()

	is_typing = true
	started_typing.emit()

	# 允许打字听众有机会连接
	await get_tree().process_frame

	if get_total_character_count() == 0:
		is_typing = false
	elif seconds_per_step == 0:
		_mutate_remaining_mutations()
		visible_characters = get_total_character_count()
		is_typing = false


## 停止输入文本并直接跳至末尾
func skip_typing() -> void:
	_mutate_remaining_mutations()
	visible_characters = get_total_character_count()
	is_typing = false
	skipped_typing.emit()


# 键入下一个字符
func _type_next(delta: float, seconds_needed: float) -> void:
	if _is_awaiting_mutation: return

	if visible_characters == get_total_character_count():
		return

	if _last_mutation_index != visible_characters:
		_last_mutation_index = visible_characters
		_mutate_inline_mutations(visible_characters)
		if _is_awaiting_mutation: return

	# 在“.”等字符上暂停。
	var waiting_seconds: float = seconds_per_pause_step if _should_auto_pause() else 0.0
	if _last_wait_index != visible_characters and waiting_seconds > 0:
		_last_wait_index = visible_characters
		_waiting_seconds += waiting_seconds
	else:
		visible_characters += 1
		if visible_characters <= get_total_character_count():
			spoke.emit(get_parsed_text()[visible_characters - 1], visible_characters - 1, _get_speed(visible_characters))
		# 看看是否有时间在此框架中输入更多内容
		seconds_needed += seconds_per_step * (1.0 / _get_speed(visible_characters))
		if seconds_needed > delta:
			_waiting_seconds += seconds_needed
		else:
			_type_next(delta, seconds_needed)


# 获取当前打字位置的速度
func _get_speed(at_index: int) -> float:
	var speed: float = 1
	for index: int in dialogue_line.speeds:
		if index > at_index:
			return speed
		speed = dialogue_line.speeds[index]
	return speed


# 运行任何尚未运行的内联突变
func _mutate_remaining_mutations() -> void:
	_is_skipping_mutations = true
	for i: int in range(visible_characters, get_total_character_count() + 1):
		_mutate_inline_mutations(i)
	_is_skipping_mutations = false


# 在当前打字位置运行任何突变
func _mutate_inline_mutations(index: int) -> void:
	for inline_mutation: Array in dialogue_line.inline_mutations:
		# 内联突变是数组的数组，其形式为[字符索引，可解析函数]
		if inline_mutation[0] > index:
			return
		if inline_mutation[0] == index and not _already_mutated_indices.has(index):
			if _is_skipping_mutations:
				Engine.get_singleton("DialogueManager")._mutate(inline_mutation[1], dialogue_line.extra_game_states, true)
			else:
				_is_awaiting_mutation = true
				# 这里不能直接引用DialogueManager，所以我们需要通过它的路径来获取它
				await Engine.get_singleton("DialogueManager")._mutate(inline_mutation[1], dialogue_line.extra_game_states, true)
				_is_awaiting_mutation = false

	_already_mutated_indices.append(index)


# 确定光标处的当前自动暂停字符是否有资格暂停键入。
func _should_auto_pause() -> bool:
	if visible_characters == 0: return false

	var parsed_text: String = get_parsed_text()

	# 当标签自动翻译并且打字时文本变短时，避免越界
	# 注意：翻译事件后可见字符可能大于 parsed_text
	if visible_characters >= parsed_text.length(): return false

	# 如果暂停字符位于非暂停字符旁边，则忽略它们
	if parsed_text[visible_characters] in skip_pause_at_character_if_followed_by.split():
		return false

	# 忽略 ”。”如果它在两个数字之间
	if visible_characters > 3 and parsed_text[visible_characters - 1] == ".":
		var possible_number: String = parsed_text.substr(visible_characters - 2, 3)
		if str(float(possible_number)).pad_decimals(1) == possible_number:
			return false

	# 忽略 ”。”如果它用在缩写中
	# 注意：不支持多句点缩写（例如 p.m.）
	if "." in pause_at_characters and parsed_text[visible_characters - 1] == ".":
		for abbreviation: String in skip_pause_at_abbreviations:
			if visible_characters >= abbreviation.length():
				var previous_characters: String = parsed_text.substr(visible_characters - abbreviation.length() - 1, abbreviation.length())
				if previous_characters == abbreviation:
					return false

	# 忽略两个非“.”字符彼此相邻
	var other_pause_characters: PackedStringArray = pause_at_characters.replace(".", "").split()
	if visible_characters > 1 and parsed_text[visible_characters - 1] in other_pause_characters and parsed_text[visible_characters] in other_pause_characters:
		return false

	return parsed_text[visible_characters - 1] in pause_at_characters.split()
