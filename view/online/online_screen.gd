# 通信対戦の入口。名前とサーバーのアドレスを入れてつなぐか、このPCでサーバーを立てて（ホストして）つなぐ。
# つながったら待合室を出す。最初に入った人が「開始」を押すと、足りない人数をCPUで埋めて試合が始まる。
extends "res://view/screen_base.gd"

const GameClient := preload("res://net/game_client.gd")

var name_edit: LineEdit
var host_edit: LineEdit
var port_edit: LineEdit
var _form: VBoxContainer
var _room: VBoxContainer
var _status: Label
var _members: Label
var _start: Button
var _addresses: Label
var _message: Label


func build_ui() -> void:
	add_title("オンライン対戦")
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 8)
	box.add_child(_form)
	add_label("同じLANや、ポートを開けたPCのサーバーに、IPアドレスを入れてつなぐ。", 16, COL_DIM, _form)
	name_edit = _field("名前", "プレイヤー")
	host_edit = _field("サーバーのアドレス", "127.0.0.1")
	port_edit = _field("ポート", str(int(main.data.rule("online.port"))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_form.add_child(row)
	add_button("参加する", join, row)
	add_button("ホストする（このPCでサーバーを立てて参加）", host, row)
	_message = add_label("", 17, COL_BAD, _form)

	_room = VBoxContainer.new()
	_room.add_theme_constant_override("separation", 8)
	box.add_child(_room)
	_status = add_label("", 20, COL_ACCENT, _room)
	_members = add_label("", 18, COL_TEXT, _room)
	_addresses = add_label("", 15, COL_DIM, _room)
	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 12)
	_room.add_child(room_row)
	_start = add_button("開始する（足りない人数はCPU）", start, room_row)
	add_button("抜ける", leave, room_row)

	add_label(" ", 8)
	add_button("タイトルへ", back)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func join() -> String:
	return _connect(false)


func host() -> String:
	return _connect(true)


func start() -> void:
	if main.online != null:
		main.online.request_start()


func leave() -> void:
	main.leave_online()


func back() -> void:
	main.show_title()


func _connect(host_server: bool) -> String:
	var player_name: String = name_edit.text.strip_edges()
	if player_name.is_empty():
		_message.text = "名前を入れてください"
		return _message.text
	var err: String = main.start_online(host_edit.text.strip_edges(), int(port_edit.text), player_name, host_server)
	_message.text = err
	return err


func _refresh() -> void:
	var c: Variant = main.online
	var connected: bool = c != null and c.status != GameClient.Status.CLOSED
	_form.visible = not connected
	_room.visible = connected
	if c != null and c.status == GameClient.Status.CLOSED and _message.text.is_empty():
		_message.text = c.reason
	if not connected:
		return
	match c.status:
		GameClient.Status.CONNECTING:
			_status.text = "つないでいます…"
		GameClient.Status.LOBBY:
			_status.text = "待合室（%s）" % ("あなたが開始できます" if c.is_leader else "最初に入った人が開始するのを待っています")
		GameClient.Status.MATCH:
			_status.text = "試合を始めています…"
	var lines: PackedStringArray = PackedStringArray()
	for n: Variant in c.lobby:
		lines.append("・%s%s" % [n, "（あなた）" if n == c.my_name else ""])
	_members.text = "\n".join(lines)
	_start.visible = c.is_leader and c.status == GameClient.Status.LOBBY
	if main.is_hosting():
		_addresses.text = "ほかの人は、このPCのアドレス（%s）とポート %s でつなげます" % [
			"、".join(_local_addresses()), port_edit.text]
	else:
		_addresses.text = ""


func _field(label: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_form.add_child(row)
	var l: Label = add_label(label, 17, COL_TEXT, row)
	l.custom_minimum_size = Vector2(200, 0)
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(280, 0)
	row.add_child(e)
	return e


## このPCの、LANで使われるIPv4アドレス
static func _local_addresses() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out
