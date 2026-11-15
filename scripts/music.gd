extends Node
## Background music with crossfade (autoload Music).
## Music.play("menu" | "game" | "launch" | "moon")

const TRACKS := {
	"menu": "res://assets/music/menu_crystalline_horizons.ogg",
	"game": "res://assets/music/game_hypnotic_void_texture.ogg",
	"launch": "res://assets/music/launch_void_echoes.ogg",
	"moon": "res://assets/music/moon_luminous_stardust.ogg",
}
const VOLUME_DB := -8.0
const FADE := 1.2

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _current := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


func play(track: String) -> void:
	if track == _current or not TRACKS.has(track):
		return
	_current = track
	var stream: AudioStream = load(TRACKS[track])
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = -40.0
	p.play()
	var t := create_tween().set_parallel(true)
	t.tween_property(p, "volume_db", VOLUME_DB, FADE)
	t.tween_property(old, "volume_db", -80.0, FADE)
	t.chain().tween_callback(old.stop)
