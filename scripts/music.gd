extends Node

const D = preload("res://scripts/mission_data.gd")
const TRACKS := {
	"menu": "res://assets/music/crystalline_horizons.ogg",
	"base": "res://assets/music/hypnotic_void_texture.ogg",
	"danger": "res://assets/music/void_echoes.ogg",
	"moon": "res://assets/music/luminous_stardust.ogg",
}
const VOLUME_DB := -8.0
const DUCK_DB := 22.0
const SILENT_DB := -60.0
const FADE := 1.8

var _players: Array[AudioStreamPlayer] = []
var _tweens: Array = [null, null]
var _active := 0
var _current := ""
var _ducked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)


func play(track: String) -> void:
	if track == _current:
		return
	_current = track
	var old := _players[_active]
	if old.playing:
		_fade(_active, SILENT_DB, true)
	if not TRACKS.has(track):
		return
	var stream := load(TRACKS[track]) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	_fade(_active, _target_db(), false)


func stop() -> void:
	_current = ""
	for i in _players.size():
		if _players[i].playing:
			_fade(i, SILENT_DB, true)


func set_ducked(ducked: bool) -> void:
	if ducked == _ducked:
		return
	_ducked = ducked
	if _players[_active].playing:
		_fade(_active, _target_db(), false)


func play_for_state(st: Dictionary) -> void:
	if st.is_empty():
		return
	if st.get("over", false):
		var ending: Dictionary = D.ENDINGS.get(st.get("ending", ""), {})
		play("moon" if ending.get("good", false) else "danger")
		return
	var fl: Dictionary = st.get("flight", {})
	if fl.is_empty():
		play("base")
	elif fl.get("phase", "") in ["orbit", "site", "landing"]:
		play("moon")
	else:
		play("danger")


func _target_db() -> float:
	return VOLUME_DB - (DUCK_DB if _ducked else 0.0)


func _fade(i: int, db: float, stop_after: bool) -> void:
	if _tweens[i] != null:
		_tweens[i].kill()
	var p := _players[i]
	var t := create_tween()
	t.tween_property(p, "volume_db", db, FADE)
	if stop_after:
		t.tween_callback(p.stop)
	_tweens[i] = t
