# CREDITS

프로젝트에 포함된 외부 에셋의 출처와 라이선스. CC0/CC-BY/OFL만 허용 (NC/ND 금지).

## Fonts (fonts_tiles agent)

| 파일 | 폰트 | 저작자 | 라이선스 | 출처 |
|---|---|---|---|---|
| fonts/galmuri/Galmuri7.ttf, Galmuri9.ttf, Galmuri11.ttf, Galmuri11-Bold.ttf, Galmuri11-Condensed.ttf, Galmuri14.ttf, GalmuriMono11.ttf | Galmuri v2.40.4 (한글 픽셀 UI 본문) | Lee Minseo (quiple) | SIL OFL 1.1 — fonts/galmuri/LICENSE.txt | https://github.com/quiple/galmuri/releases/tag/v2.40.4 |
| fonts/fusion_pixel/fusion-pixel-12px-proportional-ko.otf | Fusion Pixel Font 12px proportional (ko) 2026.11.10 — 한자·확장 CJK 폴백 | TakWolf (Ark Pixel, Cubic 11, Galmuri 기반) | SIL OFL 1.1 — fonts/fusion_pixel/OFL.txt, LICENSES/ | https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.11.10 |
| fonts/nanum_brush/NanumBrushScript-Regular.ttf | Nanum Brush Script (제목·부적풍 붓글씨) | NHN Corp. / Sandoll Communication | SIL OFL 1.1 — fonts/nanum_brush/OFL.txt | https://github.com/google/fonts/tree/main/ofl/nanumbrushscript |

OFL: 폰트 파일 단독 판매 금지, 수정 시 Reserved Font Name 사용 금지. 게임 번들 동봉은 허용.

## Stage 국사당 환경 (fonts_tiles agent)

- game/assets/tiles/tile_guksadang_*.png — PixelLab create_topdown_tileset(pro) 생성물. PixelLab 유료 구독(Tier 1) 생성 결과물로 상업 이용 가능(PixelLab ToS). 외부 저작물 아님.
- game/assets/props/* — PixelLab create_map_object 생성물 + tools/props_postprocess.py 후처리, 또는 tools/props_handdrawn.py 코드 손그림(프로젝트 원작). 외부 저작물 아님.
- game/assets/vfx/vfx_candle_flame_s.* — tools/props_handdrawn.py 원작(pixelfx --sheet JSON 형식 준수).

<!-- audio:begin -->
## Audio (audio agent)

game/assets/music/*.ogg, game/assets/sfx/*.ogg 는 tools/audio/ 의 합성 코드(프로젝트 원작)와 아래 외부 샘플을 가공(잘라내기·피치·필터·엔벨로프·레이어·잔향)해 만든 2차 저작물이다. 외부 샘플은 전부 CC0 또는 CC-BY 4.0 이며 NC/ND/BY-SA 는 쓰지 않았다. 원본 정리본: art/audio/src/ (SOURCES.json).

### CC-BY 4.0 — 저작자 표시 필수

| 샘플 | 제목 | 저작자 | 라이선스 | 출처 | 변경 | 사용처 |
|---|---|---|---|---|---|---|
| gong_korean_cdrk | gong_0001_[korean]_1_shot_mono.flac | cdrk | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | https://freesound.org/people/cdrk/sounds/18660 | 피치 변경·감쇠 엔벨로프·필터·합성음과 레이어 | music/*_kkwaenggwari, sfx_trl_bingui, sfx_trl_grm_connect_star, sfx_trl_hapil |

표기 예(게임 내 크레딧 화면): "gong_0001_[korean]_1_shot_mono.flac" by cdrk (freesound.org/people/cdrk/sounds/18660), CC BY 4.0, modified.

### CC0 1.0 — 의무 없음(감사 표기)

| 샘플 | 제목 | 저작자 | 출처 | 사용처 |
|---|---|---|---|---|
| bamboo_forest | bamboo forest (1).wav | Codly | https://freesound.org/people/Codly/sounds/546985 | amb_jindo_ssitgim |
| bamboo_hit | Bamboo Hit | DaveJf | https://freesound.org/people/DaveJf/sounds/727509 | sfx_trl_grm_install, sfx_trl_sinjangdae, sfx_wpn_obanggi |
| bamboo_maraca | Small Bamboo Maraca | JarredGibb | https://freesound.org/people/JarredGibb/sounds/263891 | sfx_enm_subi, sfx_plr_step, sfx_sys_wongwi_rise, sfx_ui_reroll, sfx_wpn_sogeum, sfx_wpn_sogeum_hit |
| bell_1ring | 1ring | iluppai | https://freesound.org/people/iluppai/sounds/148849 | sfx_amb_pungyeong, sfx_sys_deungbul, sfx_sys_pungyeong, sfx_trl_avatar_smile |
| bell_burma | BurmaBell.aif | LozKaye | https://freesound.org/people/LozKaye/sounds/94024 | (보관만, 미사용) |
| bowl_strike_a | singing bowl strike sound | inoshirodesign | https://freesound.org/people/inoshirodesign/sounds/271370 | (보관만, 미사용) |
| bowl_strike_b | Tibetan Singing Bowl (Struck) | Truthiswithin | https://freesound.org/people/Truthiswithin/sounds/193022 | (보관만, 미사용) |
| breath_deep | slow deep breath and sharp intake of breath (breathing).wav | Tac_333 | https://freesound.org/people/Tac_333/sounds/511256 | sfx_chaser_saja_eup, sfx_enm_hosik_wonhon, sfx_plr_hit, sfx_plr_revive, sfx_sys_eoduk_grow, sfx_sys_pullil_enter, sfx_trl_avatar_smile |
| breath_woman | Woman, female, inhale, exhale, sigh, breathing.wav | SpliceSound | https://freesound.org/people/SpliceSound/sounds/218311 | sfx_enm_gaekgwi, sfx_plr_levelup_ready, sfx_sys_haewon_elite, stg_death |
| candle_light | Candle lighting.wav | mfearnley | https://freesound.org/people/mfearnley/sounds/434145 | sfx_sys_deungbul, sfx_ui_title_start |
| candle_wind | burning candle in the wind.wav | 16GPanskaSibinska_N | https://freesound.org/people/16GPanskaSibinska_N/sounds/497195 | sfx_enm_dokkaebi_bul |
| chime_single_02 | wind chimes - single 02.wav | Anthousai | https://freesound.org/people/Anthousai/sounds/398493 | sfx_sys_deungbul, sfx_trl_avatar_smile |
| chime_single_03 | wind chimes - single 03.wav | Anthousai | https://freesound.org/people/Anthousai/sounds/398492 | (보관만, 미사용) |
| chime_single_04 | wind chimes - single 04.wav | Anthousai | https://freesound.org/people/Anthousai/sounds/398496 | sfx_sys_deungbul, sfx_trl_avatar_smile |
| cloth_flap | Fabric flaps | PelicanPolice | https://freesound.org/people/PelicanPolice/sounds/580967 | amb_east_sea_byeolsin, amb_jeju_chilmeori, amb_myeongbu, sfx_boss_knot_untie, sfx_chaser_saja_eup, sfx_chaser_saja_step, sfx_enm_gaekgwi, sfx_evo_reveal, sfx... |
| coins | coins2.wav | squashy555 | https://freesound.org/people/squashy555/sounds/235434 | sfx_pick_yeopjeon, sfx_ui_settle_tick, sfx_wpn_jijeon_hit, sfx_wpn_pyeongon, sfx_wpn_pyeongon_hit |
| crash_mute | crash mute1.wav | lewis | https://freesound.org/people/lewis/sounds/15576 | music/*_jegeum, sfx_trl_bingui, sfx_trl_hapil |
| crash_thin16 | Meinl_Byzance_16__Extra_Dry_Thin_Crash_C_5.wav | ankealtd | https://freesound.org/people/ankealtd/sounds/696206 | music/*_jegeum, sfx_trl_bingui, sfx_trl_hapil |
| crash_thrashed20 | crash thrashed 20''.wav | laffik | https://freesound.org/people/laffik/sounds/583969 | music/*_jegeum, sfx_trl_bingui, sfx_trl_hapil |
| crickets_forest | crickets night forest with 2 sharp close cicadas back and forth.flac | kyles | https://freesound.org/people/kyles/sounds/453862 | amb_lobby_sindang |
| crickets_pine | cricket night ambience lebanon pine forest .wav | Ramston | https://freesound.org/people/Ramston/sounds/580353 | amb_guksadang |
| drum_hits_dry | Single drum hits 17 inch drum dry (no reverb) | wolfdoctor | https://freesound.org/people/wolfdoctor/sounds/553876 | sfx_chaser_saja_eup, sfx_elite_eodukssini, sfx_sys_gilbe_close_ready, sfx_sys_sinmyeong_tick, sfx_trl_grm_install, sfx_trl_sinjangdae, sfx_trl_wieom_step, sf... |
| drum_hits_low | Low single drum hits 17 inch dry (no reverb) | wolfdoctor | https://freesound.org/people/wolfdoctor/sounds/553878 | music/*_buk, music/*_janggu, sfx_chaser_saja_step, sfx_sys_cheondo, sfx_sys_gildakkeum, sfx_sys_gyeoldanta, sfx_sys_hanpa, sfx_sys_oreum_end, sfx_sys_oreum_s... |
| drum_sticks | drum sticks unprocessed.wav | soundhead | https://freesound.org/people/soundhead/sounds/73380 | music/*_janggu, sfx_sys_cheondo, sfx_sys_gildakkeum, sfx_sys_gyeoldanta, sfx_sys_hanpa, sfx_sys_oreum_end, sfx_sys_oreum_start, sfx_sys_sinmyeong_full, sfx_s... |
| fire_crackle | fire crackles | florianreichelt | https://freesound.org/people/florianreichelt/sounds/563766 | amb_lobby_sindang, sfx_enm_dokkaebi_bul |
| gong_low_bash | low gong bash | hiddenpersuader | https://freesound.org/people/hiddenpersuader/sounds/155460 | (보관만, 미사용) |
| gong_qubodup | Gong | qubodup | https://freesound.org/people/qubodup/sounds/157432 | music/*_jing, sfx_trl_bingui, sfx_trl_grm_ring_capture, sfx_trl_hapil |
| gong_small_clear | Gong_Center_Clear.wav | Q.K. | https://freesound.org/people/Q.K./sounds/56240 | (보관만, 미사용) |
| heartbeat60 | heartbeat-60bpm.wav | loudernoises | https://freesound.org/people/loudernoises/sounds/332821 | sfx_sys_eoduk_heart, stg_boss_silence |
| korean_bell | Korean Bell.wav | sarena6487528 | https://freesound.org/people/sarena6487528/sounds/474949 | amb_myeongbu, sfx_elite_wongwi, sfx_enm_agwi, sfx_enm_sangmun, sfx_evo_reveal, sfx_evt_gongmulsang, sfx_sys_doryang, sfx_sys_gilbe_close_ready, sfx_sys_giun_... |
| match_light | Lighting matches_01.WAV | Leandri140029 | https://freesound.org/people/Leandri140029/sounds/437548 | sfx_elite_wongwi |
| paper_flap | Paper, rustling, flapping, throwing, 10.mp3 | TRP | https://freesound.org/people/TRP/sounds/576951 | sfx_plr_hit_blocked, sfx_sys_cheondo, sfx_sys_gildakkeum, sfx_sys_gyeoldanta, sfx_sys_hanpa, sfx_sys_yeongga_substitute, sfx_trl_grm_ring_capture, sfx_ui_unl... |
| paper_fold | folding paper.wav | allcaps99 | https://freesound.org/people/allcaps99/sounds/97974 | sfx_boss_knot_untie, sfx_enm_sangmun, sfx_pick_hosinbu, sfx_sys_yeongga_join, sfx_ui_banish, sfx_ui_jeomji_open, sfx_ui_skip, sfx_wpn_buchae |
| paper_rustle | Paper Rustling 02.wav | swidmark | https://freesound.org/people/swidmark/sounds/171325 | sfx_chaser_saja_step, sfx_enm_mongdal_gwisin, sfx_evt_gongmulsang, sfx_pick_neok, sfx_sys_yeongga_join, sfx_ui_nav, sfx_wpn_jijeon, sfx_wpn_neokjeon, sfx_wpn... |
| paper_tear_a | Tearing paper | Poligonstudio | https://freesound.org/people/Poligonstudio/sounds/392616 | sfx_sys_cheondo, sfx_sys_gildakkeum, sfx_sys_gyeoldanta, sfx_sys_hanpa, sfx_trl_grm_ring_capture, sfx_wpn_sinkal, sfx_wpn_sinkal_hit, stg_death |
| paper_tear_b | Tearing paper | vladnegrila | https://freesound.org/people/vladnegrila/sounds/339969 | sfx_wpn_sinkal, sfx_wpn_sinkal_hit, stg_death |
| rin_gong_6 | rin_gong_6.wav | strangehorizon | https://freesound.org/people/strangehorizon/sounds/616454 | (보관만, 미사용) |
| sleigh_antique | Antique sleigh bells - 9:12:19, 11.49 AM.wav | ktandry | https://freesound.org/people/ktandry/sounds/484391 | (보관만, 미사용) |
| sleigh_bells | Sleigh Bells Shaking | se2001 | https://freesound.org/people/se2001/sounds/478601 | amb_myeongbu, sfx_evo_reveal, sfx_pick_hosinbu, sfx_plr_death, sfx_plr_dodge, sfx_plr_levelup_ready, sfx_sys_cheondo, sfx_sys_doryang, sfx_sys_gildakkeum, sf... |
| smack_body | Impact: Smack Body | Sheyvan | https://freesound.org/people/Sheyvan/sounds/520702 | sfx_sys_cheondo, sfx_sys_gildakkeum, sfx_sys_gyeoldanta, sfx_sys_hanpa, sfx_trl_grm_ring_capture, sfx_wpn_pyeongon_hit, sfx_wpn_sinkal, sfx_wpn_sinkal_hit, s... |
| smacks | Smacks And Thwacks (m).wav | BarryTheWhite | https://freesound.org/people/BarryTheWhite/sounds/396345 | sfx_enm_agwi, sfx_plr_hit, sfx_wpn_gakgung, sfx_wpn_gakgung_hit, sfx_wpn_obanggi_hit, sfx_wpn_samjichang_hit |
| splash_6 | Meinl_Byzance_6__Splash_C_1.wav | ankealtd | https://freesound.org/people/ankealtd/sounds/696198 | music/*_jegeum, sfx_trl_bingui, sfx_trl_hapil |
| talempong_03 | talempong_pacik_03.wav | ixnixnixn | https://freesound.org/people/ixnixnixn/sounds/214998 | (보관만, 미사용) |
| talempong_05 | talempong_pacik_05.wav | ixnixnixn | https://freesound.org/people/ixnixnixn/sounds/215001 | (보관만, 미사용) |
| water_drop | Water Drop | willstepp | https://freesound.org/people/willstepp/sounds/188293 | amb_island_bungyo, sfx_enm_mul_gwisin, sfx_trl_grm_escort_arrive, sfx_wpn_ssukmul, sfx_wpn_ssukmul_hit |
| whoosh_heavy | Whoosh, Swoosh, heavy | FALL-E | https://freesound.org/people/FALL-E/sounds/697436 | sfx_wpn_pyeongon, sfx_wpn_woldo |
| whoosh_swing | Swing Whoosh.wav | yutface | https://freesound.org/people/yutface/sounds/257015 | sfx_enm_mongdal_gwisin |
| whoosh_sword | Whoosh Swipe Fight Sounds Sword Air | benniknop | https://freesound.org/people/benniknop/sounds/317849 | sfx_sys_gyeoldanta, sfx_wpn_sainsageom, sfx_wpn_sainsageom_hit |
| wind_foliage | Light wind through the foliage at dusk (Gran Sabana, Venezuela) | felix.blume | https://freesound.org/people/felix.blume/sounds/384240 | amb_guksadang |
| wind_night_a | windynight.wav | j1987 | https://freesound.org/people/j1987/sounds/106134 | amb_island_bungyo, amb_jindo_ssitgim, sfx_trl_omen |
| wind_night_b | night_wind.wav | BranndyBottle | https://freesound.org/people/BranndyBottle/sounds/464694 | amb_jeju_chilmeori, amb_trial_field, sfx_trl_avatar_smile |
| wood_block_b | Impact: Wood 3 - Small Block | Sheyvan | https://freesound.org/people/Sheyvan/sounds/475272 | sfx_sys_maedeup_lock, sfx_sys_maetim, sfx_trl_avatar_telegraph, sfx_ui_error, sfx_wpn_jangchang_hit |
| wood_blocks | Impact: Wood 4 - Small Blocks | Sheyvan | https://freesound.org/people/Sheyvan/sounds/475273 | sfx_chaser_saja_eup, sfx_elite_eodukssini, sfx_enm_agwi, sfx_evt_gongmulsang, sfx_sys_gilbe_close_ready, sfx_trl_sinjangdae, sfx_trl_wieom_step, sfx_ui_banis... |

- 프로젝트 원작(외부 샘플 없음): 장단 선율·베드 스템(*_melody, *_bed), 순수 합성 SFX(sfx_trl_circle_enter, sfx_enm_proj_generic, sfx_enm_dalgyal_gwisin, sfx_pick_wonhon, sfx_sys_gilbe_close_ready 등).
- 검색 경로: Openverse API(Freesound·Wikimedia 색인). Wikimedia 의 장구 녹음(CC BY-SA 4.0)은 BY-SA 라 제외.
<!-- audio:end -->
