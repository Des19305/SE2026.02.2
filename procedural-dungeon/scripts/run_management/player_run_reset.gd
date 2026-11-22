class_name PlayerRunReset
extends RefCounted

var _player: Player
var _run_manager: Node


func _init(player: Player, run_manager: Node) -> void:
	assert(player != null, "PlayerRunReset requires a Player")
	assert(run_manager != null, "PlayerRunReset requires a RunManager")

	_player = player
	_run_manager = run_manager
	_run_manager.connect(&"run_started", _on_run_started)


func _on_run_started(_seed: int, _dungeon: Dictionary) -> void:
	_player.reset_hp(true)
