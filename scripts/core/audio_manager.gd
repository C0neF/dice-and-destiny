## Audio Manager - Procedural 8-bit SFX generator + playback pool + BGM
## All sound effects are synthesized at startup from waveform parameters.
extends Node

# Pregenerated AudioStream cache: sfx_name -> AudioStreamWAV
var _sfx_cache: Dictionary = {}

# Playback pool
const POOL_SIZE = 12
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0

# Volume (0.0 to 1.0) — persisted via SaveManager
var sfx_volume: float = 0.8
var bgm_volume: float = 0.6

# BGM
var _bgm_player: AudioStreamPlayer
var _bgm_fade_player: AudioStreamPlayer  # For crossfade
var _current_bgm: String = ""
const BGM_FADE_DURATION = 1.0

# BGM paths
const BGM_TRACKS = {
	"lobby": "res://assets/audio/bgm_lobby.ogg",
	"battle": "res://assets/audio/bgm_battle.mp3",
}

func _ready():
	for i in range(POOL_SIZE):
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	
	# BGM players
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)
	
	_bgm_fade_player = AudioStreamPlayer.new()
	_bgm_fade_player.bus = "Master"
	add_child(_bgm_fade_player)
	
	_generate_all()

## Play a named sound effect
func play(sfx_name: String, volume_scale: float = 1.0):
	if sfx_volume <= 0.01:
		return
	var stream = _sfx_cache.get(sfx_name)
	if not stream:
		return
	var player = _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	player.pitch_scale = 1.0
	player.stream = stream
	player.volume_db = linear_to_db(clampf(sfx_volume * volume_scale, 0.0, 1.0))
	player.play()

## Play with slight pitch randomization (good for repeated sounds like coin, hit)
func play_varied(sfx_name: String, volume_scale: float = 1.0):
	if sfx_volume <= 0.01:
		return
	var stream = _sfx_cache.get(sfx_name)
	if not stream:
		return
	var player = _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	player.stream = stream
	player.volume_db = linear_to_db(clampf(sfx_volume * volume_scale, 0.0, 1.0))
	player.pitch_scale = randf_range(0.85, 1.15)
	player.play()

## Set SFX volume
func set_volume(vol: float):
	sfx_volume = clampf(vol, 0.0, 1.0)

## Set BGM volume (also updates currently playing BGM)
func set_bgm_volume(vol: float):
	bgm_volume = clampf(vol, 0.0, 1.0)
	if _bgm_player.playing:
		_bgm_player.volume_db = linear_to_db(bgm_volume)

## Play a BGM track by name. Crossfades if another track is playing.
func play_bgm(track_name: String):
	if track_name == _current_bgm and _bgm_player.playing:
		return  # Already playing
	
	var path = BGM_TRACKS.get(track_name, "")
	if path == "":
		stop_bgm()
		return
	
	var stream = load(path)
	if not stream:
		push_warning("BGM not found: " + path)
		return
	
	# Enable looping
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamMP3:
		stream.loop = true
	
	# Crossfade: move current to fade player, start new on main
	if _bgm_player.playing:
		_bgm_fade_player.stream = _bgm_player.stream
		_bgm_fade_player.volume_db = _bgm_player.volume_db
		_bgm_fade_player.play(_bgm_player.get_playback_position())
		# Fade out old
		var tw_out = create_tween()
		tw_out.tween_property(_bgm_fade_player, "volume_db", -40.0, BGM_FADE_DURATION)
		tw_out.tween_callback(_bgm_fade_player.stop)
	
	_current_bgm = track_name
	_bgm_player.stream = stream
	_bgm_player.volume_db = -40.0  # Start silent
	_bgm_player.play()
	# Fade in new
	var tw_in = create_tween()
	tw_in.tween_property(_bgm_player, "volume_db", linear_to_db(bgm_volume), BGM_FADE_DURATION)

## Stop BGM with fade out
func stop_bgm(fade: float = 0.5):
	if not _bgm_player.playing:
		_current_bgm = ""
		return
	_current_bgm = ""
	var tw = create_tween()
	tw.tween_property(_bgm_player, "volume_db", -40.0, fade)
	tw.tween_callback(_bgm_player.stop)

# ============================================================
#  SFX GENERATION
# ============================================================

func _generate_all():
	# Combat
	_sfx_cache["card_play"] = _gen_card_play()
	_sfx_cache["hit"] = _gen_hit()
	_sfx_cache["hit_crit"] = _gen_hit_crit()
	_sfx_cache["player_hurt"] = _gen_player_hurt()
	_sfx_cache["enemy_die"] = _gen_enemy_die()
	_sfx_cache["boss_phase"] = _gen_boss_phase()
	_sfx_cache["explosion"] = _gen_explosion()
	# Pickups
	_sfx_cache["coin"] = _gen_coin()
	_sfx_cache["heal"] = _gen_heal()
	_sfx_cache["powerup"] = _gen_powerup()
	# Dice
	_sfx_cache["dice_roll"] = _gen_dice_roll()
	# UI
	_sfx_cache["ui_click"] = _gen_ui_click()
	_sfx_cache["ui_hover"] = _gen_ui_hover()
	_sfx_cache["wave_start"] = _gen_wave_start()
	_sfx_cache["upgrade"] = _gen_upgrade()
	_sfx_cache["purchase"] = _gen_purchase()
	# Elements
	_sfx_cache["freeze"] = _gen_freeze()
	_sfx_cache["fire"] = _gen_fire()
	_sfx_cache["poison"] = _gen_poison()
	_sfx_cache["lightning"] = _gen_lightning()
	# Extra
	_sfx_cache["shield"] = _gen_shield()
	_sfx_cache["dodge"] = _gen_dodge()
	_sfx_cache["game_over"] = _gen_game_over()
	_sfx_cache["victory"] = _gen_victory()

# ============================================================
#  WAVEFORM ENGINE (16-bit, 44100 Hz)
# ============================================================

const SAMPLE_RATE = 44100

func _samples_to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.mix_rate = SAMPLE_RATE
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	# Convert float → 16-bit signed PCM (little-endian)
	var data = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s = clampf(samples[i], -1.0, 1.0)
		var val = int(s * 32767.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	wav.data = data
	return wav

func _gen_samples(duration: float, generator: Callable) -> PackedFloat32Array:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t = float(i) / SAMPLE_RATE
		samples[i] = generator.call(t)
	return samples

## Apply simple low-pass filter to soften harsh edges
func _lowpass(samples: PackedFloat32Array, cutoff: float = 0.15) -> PackedFloat32Array:
	var out = PackedFloat32Array()
	out.resize(samples.size())
	if samples.size() == 0:
		return out
	out[0] = samples[0]
	for i in range(1, samples.size()):
		out[i] = out[i - 1] + cutoff * (samples[i] - out[i - 1])
	return out

# --- Oscillators ---

func _square(t: float, freq: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0

func _saw(t: float, freq: float) -> float:
	return fmod(t * freq, 1.0) * 2.0 - 1.0

func _sine(t: float, freq: float) -> float:
	return sin(t * freq * TAU)

func _noise() -> float:
	return randf_range(-1.0, 1.0)

func _tri(t: float, freq: float) -> float:
	var phase = fmod(t * freq, 1.0)
	return 4.0 * absf(phase - 0.5) - 1.0

## Pulse wave with variable duty cycle (0.0-1.0)
func _pulse(t: float, freq: float, duty: float = 0.25) -> float:
	return 1.0 if fmod(t * freq, 1.0) < duty else -1.0

# --- Envelopes ---

func _adsr(t: float, duration: float, attack: float = 0.01, decay: float = 0.1,
		sustain: float = 0.3, release: float = 0.1) -> float:
	if t < attack:
		return t / maxf(attack, 0.001)
	elif t < attack + decay:
		return 1.0 - (1.0 - sustain) * ((t - attack) / maxf(decay, 0.001))
	elif t < duration - release:
		return sustain
	elif t < duration:
		return sustain * (1.0 - (t - (duration - release)) / maxf(release, 0.001))
	return 0.0

func _exp_decay(t: float, rate: float = 5.0) -> float:
	return exp(-t * rate)

# ============================================================
#  INDIVIDUAL SFX GENERATORS
# ============================================================

## Card play: snappy percussive click with harmonic tail
func _gen_card_play() -> AudioStreamWAV:
	var dur = 0.1
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 35.0)
		var click = _pulse(t, 900.0, 0.3) * _exp_decay(t, 60.0) * 0.4
		var body = _tri(t, 600.0 + t * 1500.0) * env * 0.35
		return click + body
	)
	return _samples_to_stream(_lowpass(samples, 0.3))

## Attack hit: meaty punch with sub-bass thump
func _gen_hit() -> AudioStreamWAV:
	var dur = 0.18
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 14.0)
		var sub = _sine(t, 60.0) * _exp_decay(t, 10.0) * 0.5  # Sub bass
		var freq = 220.0 - t * 600.0
		var mid = _square(t, maxf(freq, 55)) * 0.35
		var crack = _noise() * _exp_decay(t, 30.0) * 0.3  # Impact crack
		return (sub + mid + crack) * env * 0.65
	)
	return _samples_to_stream(_lowpass(samples, 0.25))

## Critical hit: layered impact with bright overtone
func _gen_hit_crit() -> AudioStreamWAV:
	var dur = 0.25
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 10.0)
		var sub = _sine(t, 50.0) * _exp_decay(t, 8.0) * 0.4
		var freq = 440.0 - t * 900.0
		var mid = _square(t, maxf(freq, 80)) * 0.3
		var high = _saw(t, maxf(freq * 1.5, 120)) * _exp_decay(t, 18.0) * 0.25
		var crack = _noise() * _exp_decay(t, 25.0) * 0.25
		return (sub + mid + high + crack) * env * 0.75
	)
	return _samples_to_stream(_lowpass(samples, 0.3))

## Player hurt: descending dissonant buzz with sub hit
func _gen_player_hurt() -> AudioStreamWAV:
	var dur = 0.3
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 7.0)
		var freq = 350.0 - t * 600.0
		var buzz = _square(t, maxf(freq, 45)) * 0.4
		var dissonance = _pulse(t, maxf(freq * 1.07, 48), 0.35) * 0.2  # Slightly detuned
		var sub = _sine(t, 40.0) * _exp_decay(t, 6.0) * 0.3
		return (buzz + dissonance + sub) * env * 0.55
	)
	return _samples_to_stream(_lowpass(samples, 0.2))

## Enemy death: punchy pop with noise scatter
func _gen_enemy_die() -> AudioStreamWAV:
	var dur = 0.25
	var samples = _gen_samples(dur, func(t):
		var pop = _sine(t, 180.0 - t * 300.0) * _exp_decay(t, 12.0) * 0.45
		var scatter = _noise() * _exp_decay(t, 10.0) * 0.4
		var sparkle = _tri(t, 800.0 + t * 1200.0) * _exp_decay(t, 20.0) * 0.2
		return pop + scatter + sparkle
	)
	return _samples_to_stream(_lowpass(samples, 0.3))

## Boss phase: deep ominous rumble building to a hit
func _gen_boss_phase() -> AudioStreamWAV:
	var dur = 1.0
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.08, 0.3, 0.6, 0.3)
		var bass = _sine(t, 40.0 + t * 25.0) * 0.45
		var rumble = _noise() * 0.15 * (0.5 + t * 0.5)
		var mid = _square(t, 80.0 + t * 180.0) * 0.25
		var high = _saw(t, 200.0 + t * 500.0) * _exp_decay(t - 0.5, 4.0) * 0.2 if t > 0.5 else 0.0
		return (bass + rumble + mid + high) * env * 0.7
	)
	return _samples_to_stream(_lowpass(samples, 0.15))

## Explosion: massive layered boom
func _gen_explosion() -> AudioStreamWAV:
	var dur = 0.5
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 4.5)
		var sub = _sine(t, 35.0 + t * 15.0) * 0.45  # Deep sub bass
		var crunch = _noise() * 0.4 * _exp_decay(t, 6.0)
		var mid = _saw(t, 80.0 - t * 40.0) * 0.2
		var tail = _noise() * 0.15 * _exp_decay(t, 2.5)  # Rumble tail
		return (sub + crunch + mid + tail) * env * 0.8
	)
	return _samples_to_stream(_lowpass(samples, 0.12))

## Coin: bright two-tone ding (classic coin sound)
func _gen_coin() -> AudioStreamWAV:
	var dur = 0.15
	var samples = _gen_samples(dur, func(t):
		# Two quick notes: B5 → E6
		var freq = 988.0 if t < 0.05 else 1319.0
		var env = _exp_decay(t, 18.0)
		return (_tri(t, freq) * 0.45 + _sine(t, freq * 2.0) * 0.2) * env * 0.45
	)
	return _samples_to_stream(samples)

## Heal: warm ascending chord
func _gen_heal() -> AudioStreamWAV:
	var dur = 0.4
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.06, 0.12, 0.5, 0.18)
		# Gentle chord: C5 + E5 + G5 rising
		var rise = t * 80.0
		var c = _sine(t, 523.0 + rise) * 0.3
		var e = _sine(t, 659.0 + rise) * 0.25
		var g = _tri(t, 784.0 + rise) * 0.2
		return (c + e + g) * env * 0.5
	)
	return _samples_to_stream(_lowpass(samples, 0.4))

## Powerup: triumphant rising arpeggio (C major)
func _gen_powerup() -> AudioStreamWAV:
	var dur = 0.4
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.02, 0.08, 0.65, 0.15)
		var step = int(t * 14.0) % 5
		var freqs = [523.0, 659.0, 784.0, 1047.0, 1319.0]  # C5 E5 G5 C6 E6
		var freq = freqs[step]
		var main = _pulse(t, freq, 0.3) * 0.3
		var shimmer = _sine(t, freq * 2.0) * 0.15
		return (main + shimmer) * env * 0.45
	)
	return _samples_to_stream(_lowpass(samples, 0.35))

## Dice roll: rattling with decelerating ticks ending in a final "clack"
func _gen_dice_roll() -> AudioStreamWAV:
	var dur = 0.5
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 3.5)
		# Decelerating tick rate
		var rate = maxf(6.0, 35.0 - t * 50.0)
		var phase = fmod(t * rate, 1.0)
		var tick = 1.0 if phase < 0.12 else 0.0
		var click = _noise() * tick * 0.35
		var tone = _tri(t, 500.0 + randf_range(-80, 80)) * tick * 0.3
		# Final settle "clack" at the end
		var settle = 0.0
		if t > dur - 0.06:
			settle = _pulse(t, 700.0, 0.4) * _exp_decay(t - (dur - 0.06), 40.0) * 0.5
		return (click + tone) * env + settle
	)
	return _samples_to_stream(_lowpass(samples, 0.3))

## UI click: crisp micro-tick
func _gen_ui_click() -> AudioStreamWAV:
	var dur = 0.05
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 55.0)
		return _pulse(t, 1100.0, 0.35) * env * 0.3
	)
	return _samples_to_stream(samples)

## UI hover: whisper-soft tick
func _gen_ui_hover() -> AudioStreamWAV:
	var dur = 0.035
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 70.0)
		return _sine(t, 1400.0) * env * 0.12
	)
	return _samples_to_stream(samples)

## Wave start: heroic fanfare-like rising brass
func _gen_wave_start() -> AudioStreamWAV:
	var dur = 0.7
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.12, 0.15, 0.65, 0.25)
		var freq = 180.0 + t * 350.0
		var brass = _saw(t, freq) * 0.3
		var body = _square(t, freq * 0.5) * 0.2
		var octave = _sine(t, freq * 2.0) * 0.15
		var sub = _sine(t, freq * 0.25) * 0.1
		return (brass + body + octave + sub) * env * 0.55
	)
	return _samples_to_stream(_lowpass(samples, 0.18))

## Upgrade: bright ascending 3-note chime
func _gen_upgrade() -> AudioStreamWAV:
	var dur = 0.45
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.02, 0.1, 0.5, 0.2)
		# Three notes: E5 → A5 → E6
		var step = int(t * 9.0) % 3
		var freqs = [659.0, 880.0, 1319.0]
		var freq = freqs[step]
		var main = _tri(t, freq) * 0.4
		var harmonic = _sine(t, freq * 2.0) * 0.2
		var sparkle = _sine(t, freq * 3.0) * 0.08
		return (main + harmonic + sparkle) * env * 0.45
	)
	return _samples_to_stream(samples)

## Purchase: satisfying "ka-ching" register sound
func _gen_purchase() -> AudioStreamWAV:
	var dur = 0.2
	var samples = _gen_samples(dur, func(t):
		# Quick double ding
		var env1 = _exp_decay(t, 25.0) if t < 0.08 else 0.0
		var env2 = _exp_decay(t - 0.07, 20.0) if t >= 0.07 else 0.0
		var note1 = _tri(t, 880.0) * env1 * 0.4
		var note2 = _tri(t, 1320.0) * env2 * 0.4
		return note1 + note2
	)
	return _samples_to_stream(samples)

## Freeze: crystalline shimmer with ice crack
func _gen_freeze() -> AudioStreamWAV:
	var dur = 0.3
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 7.0)
		var shimmer = _sine(t, 2200.0 + sin(t * 50.0) * 600.0) * 0.25
		var crystal = _tri(t, 3000.0 + sin(t * 30.0) * 400.0) * _exp_decay(t, 12.0) * 0.2
		var crack = _noise() * _exp_decay(t, 35.0) * 0.2  # Initial crack
		return (shimmer + crystal + crack) * env * 0.45
	)
	return _samples_to_stream(_lowpass(samples, 0.5))

## Fire: whooshing crackle
func _gen_fire() -> AudioStreamWAV:
	var dur = 0.25
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 7.0)
		var whoosh = _noise() * 0.35 * _exp_decay(t, 8.0)
		var crackle = _noise() * 0.15 * (1.0 if fmod(t * 40.0, 1.0) < 0.3 else 0.0)
		var base = _saw(t, 130.0 - t * 90.0) * 0.3
		var heat = _sine(t, 80.0) * 0.15
		return (whoosh + crackle + base + heat) * env * 0.55
	)
	return _samples_to_stream(_lowpass(samples, 0.18))

## Poison: squelchy bubbling
func _gen_poison() -> AudioStreamWAV:
	var dur = 0.25
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 8.0)
		# Multiple bubble frequencies
		var bub1 = _sine(t, 280.0 + sin(t * 50.0) * 120.0) * 0.3
		var bub2 = _sine(t, 400.0 + sin(t * 70.0 + 1.0) * 80.0) * 0.2
		var squelch = _noise() * _exp_decay(t, 20.0) * 0.15
		return (bub1 + bub2 + squelch) * env * 0.45
	)
	return _samples_to_stream(_lowpass(samples, 0.25))

## Lightning: sharp electric zap with crackle tail
func _gen_lightning() -> AudioStreamWAV:
	var dur = 0.2
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 12.0)
		var zap = _noise() * 0.35 * _exp_decay(t, 20.0)
		var buzz = _square(t, 1800.0 - t * 6000.0) * 0.35
		var crackle = _noise() * 0.2 * (1.0 if fmod(t * 60.0, 1.0) < 0.2 else 0.0)
		return (zap + buzz + crackle) * env * 0.55
	)
	return _samples_to_stream(_lowpass(samples, 0.4))

## Shield: solid resonant "dong"
func _gen_shield() -> AudioStreamWAV:
	var dur = 0.25
	var samples = _gen_samples(dur, func(t):
		var env = _exp_decay(t, 8.0)
		var main = _sine(t, 340.0) * 0.4
		var overtone = _sine(t, 680.0) * 0.2 * _exp_decay(t, 12.0)
		var click = _noise() * _exp_decay(t, 50.0) * 0.2
		return (main + overtone + click) * env * 0.5
	)
	return _samples_to_stream(_lowpass(samples, 0.3))

## Dodge: quick swoosh
func _gen_dodge() -> AudioStreamWAV:
	var dur = 0.15
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.01, 0.05, 0.3, 0.08)
		var freq = 400.0 + t * 2000.0  # Rising whoosh
		var swoosh = _noise() * 0.3
		var tone = _sine(t, freq) * 0.2
		return (swoosh + tone) * env * 0.4
	)
	return _samples_to_stream(_lowpass(samples, 0.35))

## Game over: sad descending minor chord
func _gen_game_over() -> AudioStreamWAV:
	var dur = 1.2
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.1, 0.3, 0.4, 0.5)
		# Descending minor: Am → Dm
		var drop = t * 40.0
		var a = _sine(t, 220.0 - drop) * 0.3
		var c = _sine(t, 262.0 - drop) * 0.25
		var e = _tri(t, 330.0 - drop) * 0.2
		return (a + c + e) * env * 0.5
	)
	return _samples_to_stream(_lowpass(samples, 0.2))

## Victory: triumphant major fanfare
func _gen_victory() -> AudioStreamWAV:
	var dur = 1.0
	var samples = _gen_samples(dur, func(t):
		var env = _adsr(t, dur, 0.08, 0.15, 0.6, 0.35)
		# Rising major arpeggio: C → E → G → C'
		var step = int(t * 6.0) % 4
		var freqs = [523.0, 659.0, 784.0, 1047.0]
		var freq = freqs[step]
		var brass = _saw(t, freq) * 0.25
		var body = _tri(t, freq) * 0.3
		var shimmer = _sine(t, freq * 2.0) * 0.12
		return (brass + body + shimmer) * env * 0.55
	)
	return _samples_to_stream(_lowpass(samples, 0.25))
