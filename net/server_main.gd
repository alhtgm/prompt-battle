# 通信対戦の専用サーバーの入口。画面なしで起動し、待ち受けを始める。
# 起動：godot --headless --path . res://net/server_main.tscn -- --port=7350
extends Node

const GameData := preload("res://core/game_data.gd")
const GameServer := preload("res://net/game_server.gd")


func _ready() -> void:
	var data := GameData.new()
	if not data.load_dir():
		printerr("data/ が読めない：\n" + "\n".join(data.errors))
		get_tree().quit(1)
		return
	var port: int = int(data.rule("online.port"))
	var scale: float = 1.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--time-scale="):
			scale = float(arg.get_slice("=", 1))
	var server := GameServer.new()
	server.name = "GameServer"
	server.time_scale = scale
	add_child(server)
	if server.start(data, port) != OK:
		printerr(server.last_error)
		get_tree().quit(1)
		return
	print("プロンプトバトルのサーバーを起動しました（ポート %d）" % port)
