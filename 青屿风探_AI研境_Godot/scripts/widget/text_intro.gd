extends CanvasLayer
## 黑幕 + 打字机的文字介绍。
##
## 用法（TextIntro 已注册为 autoload）：
##     await TextIntro.play("这里是一段介绍文字")
##     await TextIntro.play("淡入淡出各 1.5 秒", -1.0, 1.5, 1.5)
##     await TextIntro.play("每字 0.05 秒", 0.05)
##     await TextIntro.play("打完停留 2 秒", -1.0, -1.0, -1.0, 2.0)
##
## 文字里支持两种内嵌标记（标记本身不会显示）：
##     [speed=秒/字]  从这之后改变写字速度
##     [wait=秒]      在这里暂停多少秒再继续打
##
##     TextIntro.play("开头正常[speed=0.2]变慢了[wait=1.5]停顿一下再继续")

## 播放结束（淡出完成）时发出。
signal finished

## 默认打字速度，单位：秒/字。0.2 = 每字 0.2 秒；0.033 约等于每秒 30 字。
@export var default_seconds_per_char: float = 0.2
## 默认淡入时长（秒）。
@export var fade_in_time: float = 0.5
## 文字打完后停留多久再开始淡出（秒）。
@export var hold_time: float = 0.6
## 默认淡出时长（秒）。
@export var fade_out_time: float = 0.5

## 整块内容的根节点，淡入淡出改它的 modulate.a。
@onready var root: Control = $Root
## 显示文字的标签（unique name，不依赖层级路径）。
@onready var label: Label = %Label

## 是否正在播放，防止重复触发。
var _busy: bool = false


func _ready() -> void:
	# 开始就隐藏自己，等 play() 再显示。
	hide()
	root.modulate.a = 0.0


## 是否正在播放。
func is_playing() -> bool:
	return _busy


## 播放一段文字介绍。
## text             : 要显示的文字，可内嵌 [speed=秒/字] 和 [wait=秒] 标记
## seconds_per_char : 默认打字速度（秒/字）。负数用默认值；0 = 瞬间显示完
## fade_in          : 淡入时长（秒）。负数用默认值；0 = 不淡入
## fade_out         : 淡出时长（秒）。负数用默认值；0 = 不淡出
## hold             : 文字打完后停留多久再淡出（秒）。负数用默认值；0 = 不停留
## 结束时发出 finished 信号，也可以直接 await 这个函数。
func play(
	text: String,
	seconds_per_char: float = -1.0,
	fade_in: float = -1.0,
	fade_out: float = -1.0,
	hold: float = -1.0
) -> void:
	if _busy:
		push_warning("TextIntro.play: 上一次还没播完，本次忽略。")
		return

	_busy = true

	# 传负数（如 -1）= 用导出的默认值；传 0 = 瞬时 / 不停留。
	var base_speed: float = default_seconds_per_char if seconds_per_char < 0.0 else seconds_per_char
	var fi: float = fade_in_time if fade_in < 0.0 else fade_in
	var fo: float = fade_out_time if fade_out < 0.0 else fade_out
	var ht: float = hold_time if hold < 0.0 else hold

	# ---- 解析内嵌标记 ----
	var parsed: Dictionary = _parse_tags(text, base_speed)
	var clean: String = parsed["text"]
	var speeds: Dictionary = parsed["speeds"]
	var waits: Dictionary = parsed["waits"]

	# ---- 准备内容 ----
	label.text = clean
	label.visible_characters = 0
	root.modulate.a = 0.0
	show()

	# 等一帧，让 Label 完成排版（show 之后容器才会真正布局）。
	await get_tree().process_frame

	# ---- 1) 淡入 ----
	await _fade_to(1.0, fi)

	# ---- 2) 打字机（按 speeds 变速，遇 waits 暂停）----
	await _type_out(clean.length(), base_speed, speeds, waits)

	# ---- 3) 停留 ----
	if ht > 0.0:
		await get_tree().create_timer(ht).timeout

	# ---- 4) 淡出 ----
	await _fade_to(0.0, fo)

	# ---- 5) 收尾 ----
	hide()
	_busy = false
	finished.emit()


## 解析 [speed=X] 和 [wait=N] 标记。
## 返回：
##   text   : 去掉标记后的正文
##   speeds : 字典，键 = 字符索引，值 = 从该位置起生效的「秒/字」
##   waits  : 字典，键 = 字符索引，值 = 在该位置暂停的秒数
func _parse_tags(text: String, _base_speed: float) -> Dictionary:
	var re := RegEx.new()
	# 同时匹配 [speed=0.2] 和 [wait=1.5]
	re.compile("\\[(speed|wait)=([0-9]*\\.?[0-9]+)\\]")

	var clean: String = ""
	var speeds: Dictionary = {}
	var waits: Dictionary = {}
	var last: int = 0

	for m in re.search_all(text):
		# 标记之前的文字接到正文
		clean += text.substr(last, m.get_start() - last)

		var tag: String = m.get_string(1)
		var value: float = m.get_string(2).to_float()
		if tag == "speed":
			speeds[clean.length()] = value
		elif tag == "wait":
			waits[clean.length()] = value

		last = m.get_end()

	clean += text.substr(last)
	return {"text": clean, "speeds": speeds, "waits": waits}


## 逐字显示：按 speeds 变速，遇到 waits 就在那个字符位置暂停。
func _type_out(total: int, base_speed: float, speeds: Dictionary, waits: Dictionary) -> void:
	if total <= 0:
		return

	var pending_waits: Dictionary = waits.duplicate()
	var idx: int = 0
	var acc: float = 0.0
	var speed: float = speeds.get(0, base_speed)

	# 起手就是「瞬间」模式：一次性全显示（中间的 wait 会一并跳过）。
	if speed <= 0.0:
		label.visible_characters = total
		return

	while idx < total:
		# 到达暂停点：先停 N 秒，再继续打
		if pending_waits.has(idx):
			var w: float = pending_waits[idx]
			pending_waits.erase(idx)
			if w > 0.0:
				await get_tree().create_timer(w).timeout
			continue

		await get_tree().process_frame
		acc += get_process_delta_time()

		# 这一帧够推进几个字就推进几个
		while acc >= speed and idx < total:
			# 下一个位置是暂停点，先跳出内外层去处理
			if pending_waits.has(idx):
				break

			acc -= speed
			idx += 1

			# 到达下一个变速点
			if speeds.has(idx):
				speed = speeds[idx]
				if speed <= 0.0:
					label.visible_characters = total
					return

		label.visible_characters = idx


## 把整块内容的透明度渐变到 target。
func _fade_to(target: float, duration: float) -> void:
	if duration <= 0.0:
		root.modulate.a = target
		return
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", target, duration)
	await tween.finished


## 当前正文（去掉标记后的文字），调试用。
func get_visible_text() -> String:
	return label.text
