extends Node
## audio 모듈 자체 검증(런 씬 없이 Game/Beat 틱을 직접 돌린다). 소유: audio.
##   창 모드(실제 오디오 드라이버, 마스터 뮤트):
##     godot --path game res://audio/tests/audio_sync_test.tscn -- --audio-live --audio-mute
##   단계: 진양조 동기 → 03:00 브리지·중모리 착지 → 시련(산신) 빙의 → 흥1(Beat.heung_mult) → 일시정지/재개 →
##         12:00 자진모리 → 히트·처치 폭주(집계·상한) → 20:00 보스 정적 → 종료(quit_game).
## 출력: [audio-test] 줄 + Audio.print_stats. 오디오 엔진 수치만 보고 게임 규칙은 건드리지 않는다.

var _t0: float = 0.0
var _step: int = 0
var _next: float = 0.0
var _flood_left: int = 0
var _disc: float = -1.0   # 이 시각에 동기 통계 창을 비운다(점프·착지 직후의 의도된 큰 오차를 정상 상태 수치에서 뺀다)


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--audio-mute"):
		AudioServer.set_bus_volume_db(0, -80.0)
	Game.reset_run(&"char_mansin")
	Game.begin_run()
	_t0 = Audio.now()
	_next = 0.0
	print("[audio-test] start silent=%s driver latency=%.1fms mix_rate=%d" % [Audio.silent, AudioServer.get_output_latency() * 1000.0, int(AudioServer.get_mix_rate())])
	Events.weapon_added.emit(&"wpn_sinkal", 0)


func _physics_process(_dt: float) -> void:
	Game.advance_tick()


func _jump_to(sec: float) -> void:
	var tk: int = int(sec * K.TICK_HZ)
	var d: int = tk - Game.game_tick
	Game.game_tick = tk
	Game.beat_tick += d


var _trace_next: float = 0.0


func _process(_dt: float) -> void:
	var t: float = Audio.now() - _t0
	if t >= _trace_next and OS.get_cmdline_user_args().has("--audio-trace"):
		_trace_next = t + 2.0
		print("[audio-trace] t=%.1f fps=%d lead_adj=%.1fms %s" % [t, Engine.get_frames_per_second(), Audio.music._lead_adj * 1000.0, Audio.music.stats_line()])
	if _flood_left > 0:
		_flood_left -= 1
		Audio.play_sfx(&"sfx_wpn_woldo_hit" if _flood_left % 2 == 0 else &"sfx_wpn_bangul_hit", &"SFX", -9.0, 0.08)
		for k in 40:
			var p: Vector2 = Vector2(randf_range(-200, 200), randf_range(-200, 200))
			Events.enemy_hit.emit(k, &"minion_test", p, 5.0, K.DmgColor.RED if k % 3 != 0 else K.DmgColor.WHITE, k % 17 == 0, false)
		for k in 6:
			Events.enemy_killed.emit(k, &"minion_test", Vector2.ZERO, K.KIND_HAEWON if k % 2 == 0 else K.KIND_TOECHI, &"white" if k % 2 == 0 else &"han_pa", K.TIER_MINION)
		Events.xp_collected.emit(1.0)
	if _disc > 0.0 and t >= _disc:
		_disc = -1.0
		Audio.music.stats_line()
	if t < _next:
		return
	match _step:
		0:
			_say("jinyang 20s sync")
			Audio.play_sfx(&"sfx_wpn_sinkal", &"SFX", -5.0, 0.05)   # combat 직접 호출 + 신호 = 1회만(dedup)
			Events.weapon_fired.emit(&"wpn_sinkal", 0, Vector2.ZERO)
			Audio.play_sfx(&"sfx_trl_omen")
			Events.trial_warn.emit(1, &"", 10.0)                     # deities 직접 호출 + 신호 = 1회만
			_next = t + 20.0
		1:
			Audio.print_stats("jinyang")
			_jump_to(174.0)
			_say("jump 2:54 -> bridge at 2:57, jungmori land 3:00")
			_disc = t + 9.0
			Events.weapon_added.emit(&"wpn_bangul", 1)
			Events.weapon_added.emit(&"wpn_gakgung", 2)
			_next = t + 20.0
		2:
			Audio.print_stats("jungmori")
			_say("trial sansin: gauge ramps -> possession")
			Events.trial_warn.emit(1, &"", 10.0)
			Events.trial_start.emit(1, &"deity_sansin")
			for k in 11:
				Events.trial_gauge_changed.emit(1, float(k) * 0.1, 0.05)
			Events.trial_end.emit(1, &"deity_sansin", &"wieom")
			_next = t + 8.0
		3:
			Audio.print_stats("possessed")
			_disc = t + 1.0
			_say("heung 1 (Beat.heung_mult=1.04)")
			Beat.heung_mult = 1.04
			_next = t + 10.0
		4:
			Audio.print_stats("heung1")
			Beat.heung_mult = 1.0
			_say("pause 3s (menu)")
			Game.push_pause(&"menu")
			_next = t + 3.0
		5:
			Game.pop_pause(&"menu")
			_disc = t + 0.05
			_say("resume")
			_next = t + 8.0
		6:
			Audio.print_stats("resumed")
			_jump_to(716.0)
			_disc = t + 6.0
			_say("jump 11:56 -> jajinmori 12:00, then hit flood 3s")
			_next = t + 10.0
		7:
			_flood_left = 180
			Events.ring_closed.emit(60, 14, Vector2.ZERO)
			Game.sinmyeong = 0.8
			_next = t + 6.0
		8:
			Audio.print_stats("flood")
			Game.sinmyeong_oreum = true
			Events.sinmyeong_oreum.emit(true)
			_next = t + 6.0
		9:
			Game.sinmyeong_oreum = false
			Events.sinmyeong_oreum.emit(false)
			Audio.print_stats("oreum")
			_say("midboss: stinger cue at warn + mus_mboss cue + midboss_incoming (stinger once)")
			Events.music_cue.emit(&"stg_mboss_enter")
			Events.music_cue.emit(&"mus_mboss_daegwi")
			Events.midboss_incoming.emit(&"mboss_daegwi")
			_next = t + 5.0
		10:
			Audio.print_stats("midboss")
			Events.music_cue.emit(&"mus_guksadang_jajinmori")
			_say("midboss off, hapil_start (band all in) + stg_hapil_buildup cue (alias)")
			Events.music_cue.emit(&"stg_hapil_buildup")
			Events.hapil_start.emit([&"deity_sansin"])
			_next = t + 5.0
		11:
			Audio.print_stats("hapil")
			_jump_to(1196.0)
			Events.boss_incoming.emit(&"boss_yeokryeo")
			_say("jump 19:56 -> geori myeongbu 20:00 silence -> waves stop_music -> mus_boss_yeokryeo_sal cue")
			_next = t + 5.5
		12:
			_say("waves stop_music (silence)")
			Audio.stop_music()
			_next = t + 2.0
		13:
			_say("mus_boss_yeokryeo_sal")
			Events.music_cue.emit(&"mus_boss_yeokryeo_sal")
			_disc = t + 5.0
			_next = t + 14.0
		14:
			Audio.print_stats("boss")
			_say("done")
			Game.quit_game(0)
			_next = t + 999.0
	_step += 1


func _say(s: String) -> void:
	print("[audio-test] t=%.1f game=%.1f geori=%s beat_pos=%.2f | %s" % [Audio.now() - _t0, Game.time_sec(), Beat.geori_id, Beat.beat_pos, s])
