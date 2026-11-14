class_name Sfx
extends Node
## Procedural 8-bit mono 22050 Hz sound effects. Works on Desktop and Web export.

const SAMPLE_RATE := 22050
const POOL_SIZE := 8

var muted: bool = false

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	for i in range(POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "SfxPlayer_%d" % i
		add_child(p)
		_players.append(p)
	_build_sounds()


func toggle_mute() -> bool:
	muted = not muted
	if muted:
		for p in _players:
			p.stop()
	return muted


func play(sound_name: String, volume_db: float = -8.0) -> void:
	if muted:
		return
	if not _streams.has(sound_name) or _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sound_name] as AudioStreamWAV
	player.volume_db = volume_db
	player.play()


func _build_sounds() -> void:
	_streams["swing"] = _make_sweep(0.085, 420.0, 160.0, 0.25, 0.35)
	_streams["hit"] = _make_sweep(0.11, 200.0, 62.0, 0.55, 0.42)
	_streams["struct_hit"] = _make_sweep(0.16, 130.0, 46.0, 0.65, 0.48)
	_streams["player_hit"] = _make_sweep(0.15, 340.0, 120.0, 0.25, 0.45)
	_streams["pickup"] = _make_notes([523.0, 784.0], 0.055, 0.38)
	_streams["dropoff"] = _make_notes([330.0, 440.0, 587.0], 0.055, 0.36)
	_streams["bounce"] = _make_bounce(0.32)
	_streams["blood_moon"] = _make_blood_moon(0.72)
	_streams["fence_rebuilt"] = _make_notes([392.0, 523.0, 659.0, 784.0], 0.05, 0.38)
	_streams["ui_blip"] = _make_sweep(0.06, 260.0, 200.0, 0.0, 0.28)


func _make_wav(samples: PackedByteArray) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = samples
	return wav


func _to_signed_byte(sample_val: float) -> int:
	var clamped: int = clampi(roundi(sample_val * 127.0), -127, 127)
	return clamped & 0xFF


func _make_sweep(
	duration: float,
	freq_start: float,
	freq_end: float,
	noise_mix: float,
	gain: float
) -> AudioStreamWAV:
	var count: int = maxi(1, int(duration * float(SAMPLE_RATE)))
	var data: PackedByteArray = PackedByteArray()
	data.resize(count)

	var phase: float = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(freq_start * 100.0) + count

	for i in range(count):
		var t: float = float(i) / float(count)
		var freq: float = lerpf(freq_start, freq_end, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		var sq: float = 1.0 if sin(phase) >= 0.0 else -1.0
		var nz: float = rng.randf_range(-1.0, 1.0)
		var env: float = minf(1.0, t * 20.0) * (1.0 - t)
		var val: float = (sq * (1.0 - noise_mix) + nz * noise_mix) * env * gain
		data[i] = _to_signed_byte(val)

	return _make_wav(data)


func _make_notes(freqs: Array, note_len: float, gain: float) -> AudioStreamWAV:
	var note_samples: int = maxi(1, int(note_len * float(SAMPLE_RATE)))
	var total: int = note_samples * freqs.size()
	var data: PackedByteArray = PackedByteArray()
	data.resize(total)

	var phase: float = 0.0
	for n_idx in range(freqs.size()):
		var freq: float = float(freqs[n_idx])
		for j in range(note_samples):
			var lt: float = float(j) / float(note_samples)
			phase += TAU * freq / float(SAMPLE_RATE)
			var sq: float = 1.0 if sin(phase) >= 0.0 else -1.0
			var env: float = minf(1.0, lt * 18.0) * (1.0 - lt * 0.75)
			data[n_idx * note_samples + j] = _to_signed_byte(sq * env * gain)

	return _make_wav(data)


func _make_bounce(duration: float) -> AudioStreamWAV:
	var count: int = maxi(1, int(duration * float(SAMPLE_RATE)))
	var data: PackedByteArray = PackedByteArray()
	data.resize(count)

	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(count)
		var freq: float = 240.0 + sin(t * PI) * 520.0 + sin(t * TAU * 8.0) * 35.0
		phase += TAU * freq / float(SAMPLE_RATE)
		var wave: float = (1.0 if sin(phase) >= 0.0 else -1.0) * 0.65 + sin(phase * 0.5) * 0.35
		var env: float = minf(1.0, t * 14.0) * (1.0 - t * 0.85)
		data[i] = _to_signed_byte(wave * env * 0.42)

	return _make_wav(data)


func _make_blood_moon(duration: float) -> AudioStreamWAV:
	var count: int = maxi(1, int(duration * float(SAMPLE_RATE)))
	var data: PackedByteArray = PackedByteArray()
	data.resize(count)

	var p1: float = 0.0
	var p2: float = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 666

	for i in range(count):
		var t: float = float(i) / float(count)
		var f1: float = lerpf(98.0, 74.0, t)
		var f2: float = lerpf(146.0, 108.0, t)
		p1 += TAU * f1 / float(SAMPLE_RATE)
		p2 += TAU * f2 / float(SAMPLE_RATE)
		var s1: float = 1.0 if sin(p1) >= 0.0 else -1.0
		var s2: float = 1.0 if sin(p2) >= 0.0 else -1.0
		var rumble: float = rng.randf_range(-1.0, 1.0) * 0.15
		var env: float = minf(1.0, t * 6.0) * (1.0 - maxf(0.0, (t - 0.55) / 0.45))
		var val: float = (s1 * 0.5 + s2 * 0.35 + rumble) * env * 0.48
		data[i] = _to_signed_byte(val)

	return _make_wav(data)
