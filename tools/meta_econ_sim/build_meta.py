# -*- coding: utf-8 -*-
"""Builds data/meta_economy.json, data/achievements.json, data/save_profile.example.json
(single source of truth for design/09-meta-economy.md tables).
v2 (review fix): 09 owns all in-run currency amounts, price scale 2.1, shrine L1 free,
'살 맺힘 단' / '다시 묻기' display names, byeoksarok milestones + 호위 신장, 재가집 의뢰, 의례서 과제.
Usage: python build_meta.py [--md <path>]   (--md writes markdown table fragments)"""
import json, os, sys, hashlib

ROOT = "C:/Users/김태양/Desktop/KoreaLike"
DATA = os.path.join(ROOT, "data")
os.makedirs(DATA, exist_ok=True)

ECON_PRICE_SCALE = 2.1   # listed prices & one-time rewards x this in game (09 3.1)

# ---------------------------------------------------------------- weapons
WEAPONS = [
    # id, name, color, tier, base cost, discover condition (None = visible from start)
    ("wpn_sinkal", "신칼", "red", 0, 0, None),
    ("wpn_woldo", "월도", "red", 0, 0, None),
    ("wpn_gakgung", "각궁", "red", 0, 0, None),
    ("wpn_samjichang", "삼지창", "red", 1, 2000, None),
    ("wpn_jangchang", "장창", "red", 1, 2000, None),
    ("wpn_pyeongon", "편곤", "red", 2, 9000, None),
    ("wpn_jakdu", "작두", "red", 2, 9000, None),
    ("wpn_hojakdo", "호작도 부적", "red", 3, 20000, "누적 경악(공포) 부여 500회 또는 산신 위엄 빙의 1회"),
    ("wpn_cheoljillyeo", "철질려", "red", 3, 20000, "한 굿판에서 살기 50 도달 1회"),
    ("wpn_sainsageom", "사인참사검", "red", 4, 40000, "스테이지 보스 살형 퇴치 1회"),
    ("wpn_bangul", "방울", "white", 0, 0, None),
    ("wpn_buchae", "부채", "white", 0, 0, None),
    ("wpn_jijeon", "지전", "white", 0, 0, None),
    ("wpn_neokjeon", "넋전", "white", 1, 2000, None),
    ("wpn_ssukmul", "쑥물 바가지", "white", 1, 2000, None),
    ("wpn_obanggi", "오방기", "white", 2, 9000, None),
    ("wpn_janggu", "장구", "white", 2, 9000, None),
    ("wpn_gilbe", "길베", "white", 3, 20000, "한 번의 길닦음으로 20 해원 1회"),
    ("wpn_sogeum", "소금", "white", 3, 20000, "누적 살 알갱이 정화 300개(고리 포함)"),
    ("wpn_myeongdu", "명두", "white", 4, 40000, "어둑시니 소멸 5회"),
]
TIER_GATE = {1: 0, 2: 2, 3: 4, 4: 6}   # same-color purchased count required

# ---------------------------------------------------------------- characters
CHARS = [
    ("char_mansin", "만신", 0, "기본", None),
    ("char_baksu", "박수무당", 5000, "위엄 면 빙의 누적 3회", ("cnt_bingui_wieom_total", 3)),
    ("char_dangol", "단골", 5000, "해원 누적 500", ("cnt_haewon_total", 500)),
    ("char_myeongdu", "명두", 20000, "동행령 1종 해금(해원록 동행령 또는 벽사록 호위 신장)", ("cnt_companions_unlocked", 1)),
    ("char_simbang", "심방", 20000, "길흉 상자 누적 30개 개봉", ("cnt_box_gilhyung_opened", 30)),
    ("char_beopsa", "법사 (x1)", 40000, "어둑시니 정적 드롭 누적 10회", ("cnt_eodukssini_silence", 10)),
]

# ---------------------------------------------------------------- forge (display names: review fix, IDs unchanged)
FORGE = {
    "forge_gongsu": {"name": "다시 묻기(재점)", "name_old": "공수 교정", "stat": "stat_gongsu_gyojeong",
                     "costs": [2000, 6000, 12000, 22000, 36000], "max_rank": 5},
    "forge_mullim": {"name": "물림", "stat": "stat_mullim", "costs": [1500, 5000, 12000], "max_rank": 3,
                     "refund_rule": "02 점지 소유 (09는 랭크·가격만 소유)"},
    "forge_geumgi": {"name": "금기", "stat": "stat_geumgi", "costs": [3000, 8000, 16000, 26000, 40000], "max_rank": 5},
    "per_run_max_with_lineage": {"stat_gongsu_gyojeong": 6, "stat_mullim": 4, "stat_geumgi": 6},
}

# ---------------------------------------------------------------- shrines
DEITIES = [("deity_sansin", "산신"), ("deity_yongwang", "용왕"), ("deity_chilseong", "칠성"),
           ("deity_janggun", "장군·오방신장"), ("deity_barigongju", "바리공주"), ("deity_jeseok_daegam", "제석·대감")]
SHRINE_LV = [
    {"level": 1, "name": "청신(請神)", "jeongseong_gongdeok": 0, "jemul_bokjeon": 0, "req_bingui": 1, "req_both_faces": False,
     "auto": True, "ui_ko": "신령이 먼저 찾아와 신단이 차려진다(봉헌 없음)",
     "grants": ["만신 몸주신 선택 가능", "공수 1단계 대사", "신단 차림(촛불·정화수) 시각"]},
    {"level": 2, "name": "청배(請陪)", "jeongseong_gongdeok": 15000, "jemul_bokjeon": 0, "req_bingui": 10, "req_both_faces": False,
     "auto": False, "ui_ko": "정성을 올려 신단을 모신다(정성 그릇에 부분 봉헌 누적, 가격표 없음)",
     "grants": ["청배 표식: 출정 전 1신령 지정 → 06:00 시련 후보 보장", "공수 2단계 대사"]},
    {"level": 3, "name": "대접(待接)", "jeongseong_gongdeok": 30000, "jemul_bokjeon": 20000, "req_bingui": 30, "req_both_faces": True,
     "auto": False, "ui_ko": "정성(공덕)과 제물(복전)을 갖춰 신령을 대접한다(각각 누적 그릇)",
     "grants": ["빙의 오버레이 이색(異色) 팔레트", "신령 내력 3편(도감)", "공수 3단계 대사", "신단 정성 애니메이션"]},
]

# ---------------------------------------------------------------- myeongdu lineage tree
MYD = [
    ("myd_a1_mumyeong_jeogori", "A", 1, "무명 저고리", "정기 +10", "stat_jeonggi", 10, 1, 2500, "cur_gongdeok", [], 1.5),
    ("myd_a2_jeonghwa_sabal", "A", 1, "정화수 사발", "생기 +0.15/s", "stat_saenggi", 0.15, 1, 2500, "cur_gongdeok", [], 1.5),
    ("myd_a3_geumjul", "A", 2, "금줄", "신복 +1", "stat_sinbok", 1, 1, 7500, "cur_gongdeok", ["myd_a1_mumyeong_jeogori"], 2.0),
    ("myd_a4_jeopsin", "A", 2, "접신 발걸음", "접신 회피 +3%p", "stat_jeopsin_hoepi", 3, 2, 7500, "cur_gongdeok", ["myd_a2_jeonghwa_sabal"], 3.0),
    ("myd_a5_meokmul_gyeongmun", "A", 3, "먹물 경문", "출정 시 경문 각인 1개 보유", "pick_gyeongmun_gakin", 1, 2, 18000, "cur_gongdeok", ["myd_a3_geumjul|myd_a4_jeopsin"], 3.0),
    ("myd_a6_chilseong_myeongdari", "A", 4, "칠성 명다리", "명줄 +1", "stat_myeongjul", 1, 3, 32000, "cur_gongdeok", ["myd_a5_meokmul_gyeongmun"], 6.0),
    ("myd_b1_sinppal", "B", 1, "벼린 날", "신빨 +4%", "stat_sinppal", 4, 1, 2500, "cur_bokjeon", [], 2.5),
    ("myd_b2_gise", "B", 1, "시위 당김", "기세 +8%", "stat_gise", 8, 1, 2500, "cur_bokjeon", [], 1.0),
    ("myd_b3_doryang", "B", 2, "넓은 도량", "도량 +6%", "stat_doryang", 6, 1, 7500, "cur_bokjeon", ["myd_b1_sinppal|myd_b2_gise"], 2.0),
    ("myd_b4_gyeoldan", "B", 2, "결단", "결단 +2%p", "stat_gyeoldan", 2, 2, 7500, "cur_bokjeon", ["myd_b1_sinppal"], 3.0),
    ("myd_b5_jangdan", "B", 3, "잦은 가락", "장단 -3%", "stat_jangdan", -3, 2, 18000, "cur_bokjeon", ["myd_b3_doryang|myd_b4_gyeoldan"], 3.5),
    ("myd_b6_sinjang", "B", 4, "신장 한 분", "신장 수 +1", "stat_sinjang", 1, 3, 32000, "cur_bokjeon", ["myd_b5_jangdan"], 6.0),
    ("myd_c1_haengnyeol", "C", 1, "긴 행렬", "행렬 상한 +2", "stat_haengnyeol", 2, 1, 2500, "cur_gongdeok", [], 1.5),
    ("myd_c2_neok_sumyeong", "C", 1, "느린 이별", "넋 수명 +3초", "stat_neok_sumyeong", 3, 1, 2500, "cur_gongdeok", [], 1.5),
    ("myd_c3_gilbe", "C", 2, "긴 무명", "길베 +0.3초", "stat_gilbe", 0.3, 1, 7500, "cur_gongdeok", ["myd_c1_haengnyeol|myd_c2_neok_sumyeong"], 1.5),
    ("myd_c4_haewon_suryeon", "C", 2, "해원 숙련", "해원 숙련 +5%", "stat_haewon_suryeon", 5, 1, 7500, "cur_gongdeok", ["myd_c2_neok_sumyeong"], 1.5),
    ("myd_c5_puri", "C", 3, "풀이 손", "풀이 +0.2 (x3.0→x3.2)", "stat_puri", 0.2, 2, 18000, "cur_gongdeok", ["myd_c3_gilbe|myd_c4_haewon_suryeon"], 3.5),
    ("myd_c6_neokmaji", "C", 4, "넋맞이", "00:30에 영가 3 합류 + 행렬 상한 +2", "special_neokmaji", 3, 3, 32000, "cur_gongdeok", ["myd_c5_puri"], 4.0),
    ("myd_d1_chohon", "D", 1, "부르는 손", "초혼 +0.3유닛", "stat_chohon", 0.3, 1, 2500, "cur_bokjeon", [], 0.5),
    ("myd_d2_domu", "D", 1, "가벼운 발", "도무 +4%", "stat_domu", 4, 1, 2500, "cur_bokjeon", [], 1.5),
    ("myd_d3_jeomgwae", "D", 2, "엽전 점", "점괘 +10", "stat_jeomgwae", 10, 1, 7500, "cur_bokjeon", ["myd_d1_chohon|myd_d2_domu"], 1.0),
    ("myd_d4_siju", "D", 2, "대감 셈", "시주 +5%", "stat_siju", 5, 2, 7500, "cur_bokjeon", ["myd_d1_chohon"], 0.0),
    ("myd_d5_gongsu", "D", 3, "한 번 더 묻기", "다시 묻기 +1/런", "stat_gongsu_gyojeong", 1, 2, 18000, "cur_bokjeon", ["myd_d3_jeomgwae|myd_d4_siju"], 1.5),
    ("myd_d6_geumgi_mullim", "D", 4, "가릴 것 가리기", "금기 +1, 물림 +1/런", "stat_geumgi+stat_mullim", 1, 3, 32000, "cur_bokjeon", ["myd_d5_gongsu"], 2.0),
]
BRANCH = {"A": "정기 갈래 (신어머니 계보)", "B": "신빨 갈래 (장군 계보)", "C": "넋 갈래 (바리 계보)", "D": "복 갈래 (대감 계보)"}

# ---------------------------------------------------------------- 살 맺힘 단 (ID ladder_salpuri_dan unchanged)
# dan, name, pressure, modifier text, hook variables (08 14.5 maps these)
DAN = [
    (1, "부정(不淨)", "sal", "런 시작 살기 10 (기본 0)", {"salgi_base_add": 10}),
    (2, "맺힘", "han", "맺힘 복귀 12초→10초 (2회차 8초→7초)", {"maetim_return_s": [10, 7]}),
    (3, "드센 정예", "common", "정예 한 +25%, 정예 예약 슬롯 추가 확률 +0.10", {"elite_hp_mult": 1.25, "elite_extra_chance_add": 0.10}),
    (4, "이른 회귀", "sal", "원귀 회귀 임계 25/50/75 → 20/45/70", {"wongwi_thresholds": [20, 45, 70]}),
    (5, "짧은 넋", "han", "넋 수명 -5초 (기본 30→25)", {"neok_sumyeong_add_s": -5}),
    (6, "까다로운 시련", "common", "시련 제한 45→38초, 미완 빙의 효과 70%→60%", {"trial_limit_s": 38, "trial_incomplete_eff": 0.60}),
    (7, "바쁜 잡귀", "common", "일반 잡귀 이동속도 +10%, 출현량 +10%", {"normal_spd_mult": 1.10, "spawn_mult": 1.10}),
    (8, "재촉하는 사자", "sal", "저승사자 강제 강림 23:00→22:30, 사자 이동속도 +15%", {"forced_saja_s": 1350, "saja_spd_mult": 1.15}),
    (9, "깊은 어둠", "common", "어둑시니 상시: 첫 등장 07:30→05:00, 이후 맵에 최소 1체 유지", {"eodukssini_first_s": 300, "eodukssini_min_alive": 1}),
    (10, "빈 상(床)", "common", "공물 회복 20%→12%, 경문 각인 드롭 -50%", {"gongmul_heal": 0.12, "gyeongmun_drop_mult": 0.5}),
    (11, "거느린 대장", "common", "중간보스 한 +30%, 졸개 소환량 x1.5", {"mboss_hp_mult": 1.30, "mboss_minion_mult": 1.5}),
    (12, "굳은 한", "han", "풀릴 기색 임계 35%→25%", {"pullil_threshold": 0.25}),
    (13, "쌓이는 살", "sal", "일반 퇴치 살기 +0.02→+0.03, 원귀 한 x4→x5", {"salgi_per_normal_toechi": 0.03, "wongwi_hp_mult": 5}),
    (14, "깊은 매듭", "common", "한형 매듭 7→9, 살형 합신 소환 +1단계, 보스 한 +20%", {"gopuri_knots": 9, "sal_boss_summon_step_add": 1, "boss_hp_mult": 1.20}),
    (15, "마지막 맺힘", "common", "길닦음 최소 면적 9→14타일², 재사용 1.0→1.5초, 적 탄속 +10%", {"ring_min_area": 14, "ring_cooldown_s": 1.5, "enemy_bullet_spd_mult": 1.10}),
]
DAN_COSMETIC = {5: "cos_mubok_dan05", 10: "cos_mubok_dan10", 15: "cos_gilbe_geumbak"}
LADDER_RULES = {
    "display_name_ko": "살 맺힘 단", "display_name_old": "살풀이 단",
    "clear_fx_name_ko": "살풀이 (단을 깨면 정산 ③에서 살풀이춤 컷)",
    "open": "아무 스테이지나 표준 굿판 첫 클리어",
    "gating": "global",
    "advance_counts_modes": ["mode_pyojun", "mode_muhan(20:00 보스 해결 시점)"],
    "advance_excluded_modes": ["mode_jajinmori", "mode_oneul"],
    "modifiers_apply_modes": ["mode_pyojun", "mode_jajinmori", "mode_muhan"],
    "records": ["ladder.max_dan_cleared (전역, 게이트)", "ladder.best_dan_by_char (배지)", "ladder.best_dan_by_stage (표시 전용 기록)"],
    "income_mult_per_dan": 0.05,
    "hook_owner": "08-stages-waves 14.5 (훅 변수 → 웨이브 변수 매핑만)",
}

# ---------------------------------------------------------------- achievements (values here x0.5 rounded = listed base values)
ACH = [
    ("ach_first_haewon", "첫 해원", "입문", "첫 해원 1회", 300, 0, None, False),
    ("ach_first_toechi", "첫 퇴치", "입문", "첫 퇴치 1회", 0, 300, None, False),
    ("ach_first_gildakkeum", "길을 닦다", "입문", "길닦음 1회 성립", 300, 0, None, False),
    ("ach_first_bingui", "몸에 실리다", "입문", "시련 1회 통과(빙의)", 300, 300, None, False),
    ("ach_first_evo", "벼리고 다듬다", "입문", "진화 1회", 0, 500, None, False),
    ("ach_first_union", "양면", "입문", "결합 1회", 1000, 1000, None, False),
    ("ach_first_eodukssini", "별거 아니네", "입문", "어둑시니 소멸 1회", 500, 0, None, True),
    ("ach_first_wongwi", "돌아온 것들", "입문", "원귀 회귀 1회 겪기", 0, 500, None, True),
    ("ach_first_clear", "한 판을 마치다", "입문", "표준 굿판 클리어 1회", 2000, 2000, "title_saenae_mudang", False),
    ("ach_haewon_1000", "천 번의 배웅", "해원", "해원 누적 1,000", 1000, 0, None, False),
    ("ach_haewon_10000", "만 번의 배웅", "해원", "해원 누적 10,000", 3000, 0, "cos_mubok_sosaek", False),
    ("ach_haewon_100000", "넋길잡이", "해원", "해원 누적 100,000", 5000, 0, "title_neokgiljabi", False),
    ("ach_ring_30", "큰 고리", "해원", "길닦음 1회로 30 해원", 1000, 0, None, False),
    ("ach_ring_100", "온 마을 씻김", "해원", "길닦음 1회로 100 해원", 2000, 0, "cos_gilbe_geumsa", False),
    ("ach_procession_60", "끝없는 행렬", "해원", "영가 행렬 60 동시 유지", 2000, 0, None, False),
    ("ach_pure_haewon_clear", "풀어 보낸 굿", "해원", "뒷전 이전(00:00~19:00) 해원 비율 90% 이상으로 클리어", 3000, 0, "title_pureo_bonaen", False),
    ("ach_elite_haewon_all", "큰 한도 풀린다", "해원", "정예 5종 모두 해원 1회 이상", 2000, 0, None, False),
    ("ach_toechi_1000", "천 번의 벽사", "퇴치", "퇴치 누적 1,000", 0, 1000, None, False),
    ("ach_toechi_10000", "만 번의 벽사", "퇴치", "퇴치 누적 10,000", 0, 3000, "cos_mubok_hongcheollik", False),
    ("ach_toechi_100000", "벽사 무당", "퇴치", "퇴치 누적 100,000", 0, 5000, "title_byeoksa_mudang", False),
    ("ach_hanpa_10", "단칼", "퇴치", "단일 타격으로 한 파열 10체 동시", 0, 1000, None, False),
    ("ach_gyeoldanta_500", "결단", "퇴치", "결단타 퇴치 누적 500", 0, 1500, None, False),
    ("ach_pure_toechi_clear", "깎아 부순 굿", "퇴치", "뒷전 이전(00:00~19:00) 해원 비율 10% 이하로 클리어", 0, 3000, "title_kkakka_busun", False),
    ("ach_saja_chase_60", "사자의 시험", "퇴치", "사자의 시험 완수(90초 버티기 또는 시험 원귀 3기 퇴치)", 0, 2000, None, False),
    ("ach_wongwi_3_clear", "세 번 돌아와도", "퇴치", "한 굿판에서 원귀 회귀 3회 후 클리어", 0, 2500, None, False),
    ("ach_eoullim_clear", "어울림 굿", "균형", "해원 비율 45~55%로 클리어", 2000, 2000, "title_eoullim", False),
    ("ach_salgi_zero_15m", "맑은 굿판", "균형", "15:00 시점 살기 0", 2000, 0, None, False),
    ("ach_salgi_100_clear", "살을 안고서도", "균형", "살기 100 도달 후 클리어", 0, 2000, None, False),
    ("ach_bingui_12", "열두 명두", "신령", "12면 모두 빙의(명두 12점)", 3000, 3000, "title_gyeseungja", False),
    ("ach_hapil_first", "신령 합일", "신령", "18:00 신령 합일 1회", 1000, 1000, None, False),
    ("ach_all_wieom_run", "위엄의 굿", "신령", "한 굿판 6면 모두 위엄", 0, 2000, None, False),
    ("ach_all_gaho_run", "가호의 굿", "신령", "한 굿판 6면 모두 가호", 2000, 0, None, False),
    ("ach_trial_15s", "단숨의 시련", "신령", "시련을 15초 이내 통과", 1000, 0, None, False),
    ("ach_shrine_l3_first", "정성껏 대접하다", "신령", "신단 1곳 대접(3단계)", 2000, 0, "cos_sindan_dancheong", False),
    ("ach_momju_six", "여섯 몸주", "신령", "만신으로 6신령 각각을 몸주신으로 두고 클리어", 3000, 3000, "cos_mansin_hwarot", False),
    ("ach_clear_guksadang", "인왕산 굿을 마치다", "굿판", "국사당 클리어", 3000, 3000, None, False),
    ("ach_clear_jindo", "진도 씻김을 마치다", "굿판", "진도 씻김 마을 클리어", 5000, 5000, None, False),
    ("ach_clear_east_sea", "별신을 마치다", "굿판", "동해안 별신굿 바닷가 클리어", 8000, 8000, None, False),
    ("ach_boss_han_all", "세 매듭", "굿판", "보스 3종 한형 모두 해원", 3000, 0, None, False),
    ("ach_boss_sal_all", "세 벽사", "굿판", "보스 3종 살형 모두 퇴치", 0, 3000, None, False),
    ("ach_jajinmori_clear", "자진모리", "굿판", "자진모리 굿판 클리어", 2000, 2000, None, False),
    ("ach_muhan_40", "밤새 굿", "굿판", "무한굿 40:00 도달", 2000, 2000, None, False),
    ("ach_daily_first", "오늘의 굿판", "굿판", "오늘의 굿판 기록 시도 1회 완료", 500, 500, None, False),
    ("ach_dwitjeon_three", "뒷전 상차림", "굿판", "뒷전에서 공물상 3개를 고리 1개로 감싸기", 2000, 0, None, False),
    ("ach_gopuri_60s", "막힘 없는 고풀이", "굿판", "한형 고풀이를 60초 이내 완료", 2000, 0, None, False),
    ("ach_wpn_all", "무구 스무 점", "수집", "무구 20종 모두 해금", 3000, 3000, "title_mugu_jangin", False),
    ("ach_evo_all", "스무 진화", "수집", "진화 20종 모두 발견", 5000, 5000, None, False),
    ("ach_union_all", "넷의 양면", "수집", "v1 결합 4종 모두 발견", 3000, 3000, None, False),
    ("ach_comp_all", "여덟 동행", "수집", "해원록 동행령 8종 모두 해금", 3000, 0, "cos_gilbe_madang_deung", False),
    ("ach_sayeon_72", "모든 사연", "수집", "사연 조각 72개 모두", 0, 0, "title_haewon_girokja", False),
    ("ach_byeoksa_max", "벽사록 완성", "수집", "벽사록 24종 모두 3단계(호위 신장 4위 모두 모심)", 0, 0, "title_byeoksarok", False),
    ("ach_chars_all", "다섯 무당", "수집", "v1 무당 5명 모두 해금", 2000, 2000, "cos_sindang_geolgae", False),
    ("ach_dan_1", "첫 맺힘을 풀다", "살 맺힘", "살 맺힘 단 1 클리어", 1000, 1000, None, False),
    ("ach_dan_5", "다섯 단", "살 맺힘", "살 맺힘 단 5 클리어", 0, 0, "cos_mubok_dan05", False),
    ("ach_dan_10", "열 단", "살 맺힘", "살 맺힘 단 10 클리어", 0, 0, "cos_mubok_dan10", False),
    ("ach_dan_15", "살을 다 풀다", "살 맺힘", "살 맺힘 단 15 클리어", 0, 0, "title_salpuri", False),
    ("ach_dan_15_all_chars", "다섯 갈래 살풀이", "살 맺힘", "v1 무당 5명 모두로 단 15 클리어", 0, 0, "cos_myeongdu_geumbak", False),
]

# ---------------------------------------------------------------- singirok (symmetric: 해원록 98,400 공덕 / 벽사록 98,400 복전)
HAEWONROK = {
    "piece_reward_G": 200, "species_complete_G": 1000,
    "piece_rules": {
        "normal": ["그 종 첫 해원(캐논)", "그 종 해원 누적 150", "종별 사연 조건 sc_* 1회"],
        "elite": ["넋함 1번째", "넋함 2번째", "넋함 3번째"],
        "mboss": ["해원 1회", "해원 2회", "해원 3회"],
        "boss": ["한형 고풀이 1회", "살 맺힘 단 3 이상에서 고풀이", "살 맺힘 단 8 이상에서 고풀이"],
        "owner": "09 (07 2.11과 enemies.json sayeon은 이 값을 참조)",
    },
    "sayeon_conditions": {
        "enm_dalgyal_gwisin": {"key": "sc_ring_species_20", "ko": "길닦음 1회로 달걀귀신 20체 해원", "target": 20, "scope": "single_ring"},
        "enm_agwi": {"key": "sc_agwi_before_gongmul_30", "ko": "아귀가 노린 공물에 닿기 전에 해원, 누적 30", "target": 30, "scope": "profile"},
        "enm_gaekgwi": {"key": "sc_gaekgwi_attached_10", "ko": "착(着)이 붙은 적과 함께 해원, 누적 10", "target": 10, "scope": "profile"},
        "enm_cheonyeo_gwisin": {"key": "sc_cheonyeo_mid_volley_25", "ko": "탄막을 쏘는 중에 해원, 누적 25", "target": 25, "scope": "profile"},
        "enm_mongdal_gwisin": {"key": "sc_mongdal_mid_dash_25", "ko": "돌진하는 중에 해원, 누적 25", "target": 25, "scope": "profile"},
        "enm_mul_gwisin": {"key": "sc_mul_in_puddle_20", "ko": "자기 웅덩이 위에서 해원, 누적 20", "target": 20, "scope": "profile"},
        "enm_hosik_wonhon": {"key": "sc_hosik_in_sansin_gaho_10", "ko": "산신 가호 시련 중에 해원 10 (한 굿판)", "target": 10, "scope": "run"},
        "enm_dokkaebi_bul": {"key": "sc_dokkaebi_bul_8_lamps", "ko": "굿판 등불 8개를 모두 밝힌 굿판에서 해원", "target": 1, "scope": "run"},
        "enm_yeongsan": {"key": "sc_yeongsan_on_hyungsal_20", "ko": "흉살 장판 위에서 해원, 누적 20", "target": 20, "scope": "profile"},
        "enm_sangmun": {"key": "sc_sangmun_while_cursed_10", "ko": "상문살에 걸린 상태에서 해원 10", "target": 10, "scope": "profile"},
        "enm_subi": {"key": "sc_subi_dwitjeon_ring_30", "ko": "뒷전거리 공물상 고리로 수비 30 해원 (한 굿판)", "target": 30, "scope": "run"},
        "enm_hwehwe_gwisin": {"key": "sc_hwehwe_pinned_10", "ko": "경문 각인 없이 가위눌림 상태에서 해원 10", "target": 10, "scope": "profile"},
    },
    "milestones": [
        {"pieces": 18, "reward_G": 5000, "extra": "title_haewon_ipmun"},
        {"pieces": 36, "reward_G": 10000, "extra": "길베 마당 확장(다리·연못) + stage_myeongbu 해금 조건 충족(x1)"},
        {"pieces": 54, "reward_G": 15000, "extra": "cos_mubok_sobok"},
        {"pieces": 72, "reward_G": 30000, "extra": "에필로그 '베가르기' 로비 연출 + title_haewon_girokja"},
    ],
}
BYEOKSA = {
    "thresholds": {"normal": [100, 600, 2500], "elite": [10, 40, 120], "mboss": [1, 5, 15], "boss": [1, 3, 8]},
    "elite_count_note": "원귀 퇴치는 원본 종에 +5로 집계",
    "damage_bonus_pct": [3, 6, 10], "damage_bonus_applies_to": "red_weapons_only",
    "tier_reward_B": 200, "species_complete_B": 1000,
    "milestones": [
        {"tiers": 18, "reward_B": 5000, "extra": "comp_sinjang_dong + title_byeoksa_ipmun"},
        {"tiers": 36, "reward_B": 10000, "extra": "comp_sinjang_seo + 대장간 확장(담금질 못) + stage_myeongbu 해금 조건 충족(x1, CANON-REQUEST)"},
        {"tiers": 54, "reward_B": 15000, "extra": "comp_sinjang_nam + cos_mubok_jeollip"},
        {"tiers": 72, "reward_B": 30000, "extra": "comp_sinjang_buk + 에필로그 '사자의 읍' 로비 연출 + title_byeoksarok"},
    ],
}
SINJANG = [  # 호위 신장 동행령 [NEW] (effect numbers: proposal, final owner = companion owner)
    {"id": "comp_sinjang_dong", "name_ko": "동방 신장", "unlock": "벽사록 단계 합 18",
     "effect_ko": "한 파열 시 10% 확률로 0.5유닛 안 다른 적 1체에 그 피해의 50% 연쇄(적 피해)"},
    {"id": "comp_sinjang_seo", "name_ko": "서방 신장", "unlock": "벽사록 단계 합 36",
     "effect_ko": "정예 퇴치 시 경문 각인 1 (런당 최대 3)"},
    {"id": "comp_sinjang_nam", "name_ko": "남방 신장", "unlock": "벽사록 단계 합 54",
     "effect_ko": "원귀 회귀 직후 15초 동안 신빨 +20%"},
    {"id": "comp_sinjang_buk", "name_ko": "북방 신장", "unlock": "벽사록 단계 합 72",
     "effect_ko": "무당이 지나간 살 알갱이를 거둬 결단 +0.5%p 누적(런 내 최대 +5%p). 거둔 알갱이는 원귀 회귀 재료에서 빠진다(살기 수치는 그대로)"},
]
UIRYESEO = [  # 의례서 과제 [NEW] = 04 9장 아키타입 8. 클리어(표준) 조건. 보상: 공덕 1,000 + 복전 1,000 + 낙관 외형
    ("uir_a1_byeoksa_ildo", "벽사 일도", "뒷전 이전 해원 비율 ≤ 20%", ["evo_daejakdu|evo_isippalsugeom"]),
    ("uir_a2_gildakkeum_haengnyeol", "길닦음 행렬", "뒷전 이전 해원 비율 ≥ 85%", ["evo_begareugi|evo_cheoneum_bangul"]),
    ("uir_a3_ijungju", "깎고 푸는 이중주", "해원 비율 40~60%", ["union_neoksinkal"]),
    ("uir_a4_hwagong_jeonghwa", "화공 정화", "해원 비율 20~40%", ["union_sogeumsal"]),
    ("uir_a5_chilseong_myeonggyeong", "칠성 명경", "해원 비율 30~50%", ["union_chilseong_myeonggyeonggeom"]),
    ("uir_a6_jakdu_dari", "작두다리", "해원 비율 45~65%, 정기 30% 이하에서 보스 해결", ["union_jakdu_dari"]),
    ("uir_a7_obang_jinji", "오방 진지", "해원 비율 30~50%", ["evo_obangjin", "evo_cheoljillyeojin"]),
    ("uir_a8_jangdan_pokju", "장단 폭주", "해원 비율 50~70%, 신명 오름 5회 이상", ["evo_hapjangdan", "evo_pajinchang"]),
]
UIROE = {  # 재가집 의뢰 [NEW]
    "id": "sys_jaegajip_uiroe", "open": "3번째 굿판 종료 후(첫 클리어 전이라도)", "offers": 3, "pick": "0 또는 1",
    "pool_target_v1": 30, "modes": ["mode_pyojun"], "excluded_modes": ["mode_oneul", "mode_jajinmori", "mode_muhan"],
    "deity_guarantee_slot": "09:00 (03:00 몸주신·06:00 청배 표식과 겹치지 않게)",
    "reward_caps": {"currency_mult_max": 1.20, "one_currency_only": True, "record_x2_note": "지정 종: 해원 시 사연 조각 판정 x2, 퇴치 시 벽사록 집계 x2"},
    "reward_requires": "표준 굿판 클리어(보스 해결). 사망 시 의뢰 보상 없음, 일반 정산은 그대로",
    "refresh": "의뢰를 받은 굿판이 끝나면 그 1장만 교체. 받지 않은 의뢰는 3런 동안 유지",
    "samples": [
        {"id": "uiroe_bada_adeul", "sayeon_ko": "바다에서 돌아오지 못한 아들", "mods": {"species_weight": {"enm_mul_gwisin": 2.0}, "deity_guarantee": "deity_yongwang"},
         "reward": {"record_x2": {"enm_mul_gwisin": 2}}, "unlock": "동해안 개방"},
        {"id": "uiroe_jangsa", "sayeon_ko": "장사가 안 되는 집", "mods": {"deity_guarantee": "deity_jeseok_daegam", "mboss_fixed": "mboss_dokkaebi"},
         "reward": {"currency_mult": {"cur_yeopjeon": 1.20}}, "unlock": "기본"},
        {"id": "uiroe_honrye", "sayeon_ko": "혼례를 못 치르고 간 딸", "mods": {"species_weight": {"enm_cheonyeo_gwisin": 2.0, "enm_mongdal_gwisin": 1.5}},
         "reward": {"record_x2": {"enm_cheonyeo_gwisin": 2, "enm_mongdal_gwisin": 2}}, "unlock": "기본"},
        {"id": "uiroe_horangi", "sayeon_ko": "산에서 범에게 물려 간 할아버지", "mods": {"species_weight": {"enm_hosik_wonhon": 2.0}, "deity_guarantee": "deity_sansin"},
         "reward": {"record_x2": {"enm_hosik_wonhon": 2}}, "unlock": "기본"},
        {"id": "uiroe_yeokbyeong", "sayeon_ko": "마마가 돈 마을", "mods": {"elite_extra": {"elite_yeokgwi_ttae": 2}},
         "reward": {"currency_mult": {"cur_yeopjeon": 1.20}}, "unlock": "국사당 클리어"},
        {"id": "uiroe_jesa_eomneun", "sayeon_ko": "제사 지내 줄 이 없는 넋들", "mods": {"species_weight": {"enm_agwi": 1.5, "enm_gaekgwi": 1.5}},
         "reward": {"currency_mult": {"cur_neok": 1.20}}, "unlock": "기본"},
        {"id": "uiroe_sangyeo", "sayeon_ko": "상엿소리 없이 묻힌 사람들", "mods": {"species_weight": {"enm_yeongsan": 2.0, "enm_sangmun": 1.5}},
         "reward": {"record_x2": {"enm_yeongsan": 2, "enm_sangmun": 2}}, "unlock": "진도 개방"},
        {"id": "uiroe_gamum", "sayeon_ko": "가뭄 든 바닷마을", "mods": {"mboss_fixed": "mboss_gangcheori"},
         "reward": {"currency_mult": {"cur_neok": 1.20}}, "unlock": "동해안 개방"},
        {"id": "uiroe_dokkaebi", "sayeon_ko": "밤마다 불이 떠다니는 고개", "mods": {"species_weight": {"enm_dokkaebi_bul": 2.0}},
         "reward": {"record_x2": {"enm_dokkaebi_bul": 2}}, "unlock": "기본"},
        {"id": "uiroe_kkum", "sayeon_ko": "밤마다 가위눌리는 집", "mods": {"species_weight": {"enm_hwehwe_gwisin": 2.0}, "deity_guarantee": "deity_chilseong"},
         "reward": {"record_x2": {"enm_hwehwe_gwisin": 2}}, "unlock": "기본"},
        {"id": "uiroe_byeoksa", "sayeon_ko": "원귀가 들끓는 폐가", "mods": {"salgi_base_add": 15, "deity_guarantee": "deity_janggun"},
         "reward": {"currency_mult": {"cur_yeopjeon": 1.20}}, "unlock": "원귀 회귀 3회 겪기"},
        {"id": "uiroe_bari", "sayeon_ko": "버려진 딸을 기리는 굿", "mods": {"deity_guarantee": "deity_barigongju", "neok_sumyeong_add_s": -3},
         "reward": {"currency_mult": {"cur_neok": 1.20}}, "unlock": "단골 해금"},
    ],
}

# ---------------------------------------------------------------- income constants (09 owns every in-run currency amount)
INCOME = {
    "owner_note": "넋·엽전의 모든 인게임 획득량은 이 블록이 단일 원본이다. 02/04/06/07/08 문서와 enemies.json·combat_core.json·waves_*.json은 키를 참조한다.",
    "conversion": {"cur_neok_to_cur_gongdeok": 1.0, "cur_yeopjeon_to_cur_bokjeon": 1.0, "apply_stat": "stat_siju",
                   "siju_applied": "정산 시 1회만(드롭 시점에는 곱하지 않음)"},
    "neok_sources": {"haewon": 1, "cheondo": 1, "cheondo_in_ring": 2, "procession_full_instant_cheondo_bonus": 1,
                     "box_neokham_elite": 60, "box_neokham_wongwi": 80, "mboss_haewon_neokham": 300,
                     "boss_han_neokham_total": 1500, "boss_han_neokham_count": 2,
                     "trial_gaho": 40, "trial_incomplete_mult": 0.5,
                     "elite_haewon_direct": 0},
    "yeopjeon_sources": {"box_gilhyung_elite": 330, "box_gilhyung_wongwi": 440, "box_gilhyung_mboss": 1000,
                         "box_gilhyung_boss_sal_total": 1800, "box_gilhyung_boss_sal_count": 2,
                         "trial_wieom": 40, "trial_incomplete_mult": 0.5,
                         "mboss_dokkaebi_haewon_rain": 400, "box_fallback_per_slot": 20, "saseul_seugi_fail": 20,
                         "bujeong_dok_drop": 2, "normal_ghost": 0,
                         "daegam_wieom_box_mult": 1.30},
    "box_rules": {"box_contents": "확정 부가(등급 무관). 등급(소길/중길/대길)과 강화 수 1/3/5는 02 18장·combat_core.chest 소유",
                  "unopened_at_run_end": "런 종료 시 미개봉 상자는 확정 부가 재화만 지급",
                  "evolution_per_box": "04 6.2 (상자당 진화·결합 1건)"},
    "settlement": {"eoullim_band": [0.35, 0.65], "eoullim_mult": 1.15, "saja_bow_gongdeok_mult": 1.5,
                   "sal_geodum_bokjeon_mult_max": 0.5, "sal_geodum_base_s": 90, "sal_geodum_wongwi": 3,
                   "sal_geodum_progress": "p = max(거둠 경과초/90, 막아 낸 원귀 수/3), B x (1 + 0.5 p)",
                   "jeseok_gaho_gongdeok_mult": 1.25, "dan_mult_per_dan": 0.05,
                   "uiroe_currency_mult_max": 1.20},
    "mode_mult": {"mode_pyojun": 1.0, "mode_jajinmori": 0.9, "mode_muhan": {"0-30m": 1.0, "30-40m": 0.6, "40m+": 0.3},
                  "mode_oneul": 1.0, "mode_oneul_practice": 1.0, "mode_daedong": 1.0},
    "mode_oneul_completion_bonus": {"cur_gongdeok": 3000, "cur_bokjeon": 3000, "when": "그날 기록 시도 1회 완료(사망 포함). 연습 런은 없음"},
    "stage_mult": {"stage_guksadang": 1.0, "stage_jindo_ssitgim": 1.1, "stage_east_sea_byeolsin": 1.2,
                   "stage_jeju_chilmeori": 1.25, "stage_myeongbu": 1.3},
    "afk_rule": {"window_s": 60, "inactive_if_all_zero": ["damage_dealt", "damage_taken", "haewon", "toechi", "move_input"],
                 "beopsa_ward_damage_counts_as_activity": True, "income_mult_while_afk": 0.0, "modes": ["mode_muhan"]},
    "model_assumptions": {"N20_kills": 4360, "kills_curve": "combat_core.curves_assumption.kills_per_min",
                          "E20_elites_reserved": 14, "elites_source": "waves_stage1.json elites (+0.05*floor(salgi/10)/슬롯)",
                          "salgi_formula": "05 3.4.1 연속식, 기대 곡선은 02 9장 소유"},
    "reference_run_R_std_actual": 19000,
    "reference_run_R_std_base": 9050,
    "econ_price_scale": ECON_PRICE_SCALE,
    "econ_price_scale_applies_to": ["모든 해금 가격", "일회성 재화 보상(업적·해원록·벽사록·단 첫 클리어·의례서·오늘의 굿판 보너스)", "롱테일 단가", "나눔 환전 최소 단위"],
    "econ_price_scale_rounding": 100,
}

LONGTAIL = [
    {"id": "lt_yeondeung", "name": "회향 연등", "currency": "cur_gongdeok", "cost": 1000, "max": 108},
    {"id": "lt_punggyeong", "name": "대장간 풍경", "currency": "cur_bokjeon", "cost": 1000, "max": 108},
]
HINT = {"id": "seogo_bigyeol", "name": "비결 두루마리", "currency": "cur_gongdeok", "cost": 500,
        "targets": "evo_* 20 + union_* v1 4 = 24"}

FACILITIES = [
    {"id": "hub_sindang", "open_when": "처음부터(첫 굿판 이후 로비 진입 시)", "currency": "cur_gongdeok"},
    {"id": "hub_gutpan_mun", "open_when": "처음부터", "currency": None},
    {"id": "hub_singirok_seogo", "open_when": "첫 굿판 종료(해원 또는 퇴치 1회 기록)", "currency": "cur_gongdeok"},
    {"id": "hub_myeongdu_dan", "open_when": "명두 계승점 1점 획득(첫 빙의)", "currency": "mixed"},
    {"id": "hub_daejanggan", "open_when": "복전 1 이상 보유 또는 2번째 굿판 종료", "currency": "cur_bokjeon"},
    {"id": "hub_gilbe_madang", "open_when": "공간은 처음부터, 건너감 연출은 첫 종 사연 완성 시", "currency": "cur_gongdeok(회향)"},
]

MODE_ONEUL = {
    "source_of_truth": "08-stages-waves 14.4",
    "unlock": "첫 굿판 완료(사망 포함)",
    "seed": "hash(\"soulpath-daily-\" + YYYYMMDD(UTC) + season_salt)  (14 3.13 형식)",
    "character": "시드로 v1 무당 5종 중 1명 고정(선택 없음)",
    "attempts": "하루 1회 기록 시도 + 연습 무제한(기록·일일 보너스·순위표 없음)",
    "dan": "무시(고정 수정자)", "cheongbae_mark": "사용 불가", "uiroe": "사용 불가",
    "ladder_or_stage_unlock": "인정하지 않음",
    "crash_policy": "기록 시도는 이어하기 불가. run_journal 마지막 기록 시점 점수로 확정(crashed=true)",
}

# ---------------------------------------------------------------- build JSON
def wpn_json():
    out = []
    for wid, name, color, tier, cost, disc in WEAPONS:
        out.append({"id": wid, "name_ko": name, "color": color, "tier": tier, "default_unlocked": tier == 0,
                    "cost": cost, "currency": ("cur_bokjeon" if color == "red" else "cur_gongdeok") if cost else None,
                    "gate_same_color_purchased": TIER_GATE.get(tier, 0), "discover_condition": disc})
    return out

meta = {
    "schema": "soulpath.meta_economy", "version": 2, "doc": "design/09-meta-economy.md",
    "note": "모든 비용·일회성 보상은 econ_price_scale 곱 적용 전 기준가(게임 표시가 = 기준가 x 2.1, 100 단위 반올림). 인게임 드롭량(income.*_sources)은 스케일하지 않는다. 수치는 밸런스 튜닝 대상, 규칙은 01 캐논 준수.",
    "income": INCOME,
    "weapons": wpn_json(),
    "characters": [{"id": c, "name_ko": n, "cost_gongdeok": cost, "condition_text": t,
                    "condition": ({"counter": cond[0], "gte": cond[1]} if cond else None),
                    "scope": "x1" if c == "char_beopsa" else "v1"} for c, n, cost, t, cond in CHARS],
    "forge": FORGE,
    "shrines": {"deities": [d for d, _ in DEITIES], "levels": SHRINE_LV,
                "free_at_start": [{"deity": "deity_sansin", "level": 1}],
                "offering_ui": "가격표 대신 '정성 그릇'(누적 바). 부분 봉헌 가능, 환불 없음"},
    "myeongdu": {
        "points_source": "신령 면(12) 첫 빙의 시 1점, 최대 12",
        "collection": [{"id": f"myeongdu_{d.split('_',1)[1]}__{f}", "deity": d, "face": f"face_{f}"}
                       for d, _ in DEITIES for f in ("wieom", "gaho")],
        "power_index_cap": 25,
        "respec": {"cost": 0, "where": "hub_myeongdu_dan", "when": "로비에서 언제나"},
        "branches": BRANCH,
        "nodes": [{"id": i, "branch": b, "tier": t, "name_ko": n, "effect_ko": e, "stat": s, "value": v,
                   "points": p, "unlock_cost": c, "currency": cu,
                   "prereq_any_of": (pre[0].split("|") if pre else []), "power_index": pi}
                  for i, b, t, n, e, s, v, p, c, cu, pre, pi in MYD],
    },
    "singirok": {"haewonrok": HAEWONROK, "byeoksarok": BYEOKSA, "sinjang_companions": SINJANG, "hint": HINT,
                 "uiryeseo": [{"id": i, "archetype_ko": n, "condition_ko": c, "requires_held_at_clear": req,
                               "reward": {"cur_gongdeok": 1000, "cur_bokjeon": 1000, "cosmetic": f"cos_nakgwan_{i[4:6]}"},
                               "source": "04-weapons-evolution 9장"} for i, n, c, req in UIRYESEO],
                 "completion_weights": {"sayeon": 0.30, "byeoksarok": 0.30, "evo_union": 0.15, "myeongdu": 0.15, "neokduri": 0.10}},
    "uiroe": UIROE,
    "ladder_rules": LADDER_RULES,
    "ladder_salpuri_dan": [{"dan": d, "id": f"dan_{d:02d}", "name_ko": n, "pressure": side, "modifier_ko": m,
                            "hooks": hooks, "income_mult": round(1 + 0.05 * d, 2),
                            "first_clear_reward": {"cur_gongdeok": 300 * d, "cur_bokjeon": 300 * d,
                                                   "cosmetic": DAN_COSMETIC.get(d)}} for d, n, side, m, hooks in DAN],
    "mode_oneul": MODE_ONEUL,
    "longtail": LONGTAIL,
    "exchange_nanum": {"id": "xchg_nanum", "rate": {"cur_gongdeok_to_cur_bokjeon": [2, 1], "cur_bokjeon_to_cur_gongdeok": [2, 1]},
                       "min_lot": 1000, "where": ["hub_sindang", "hub_daejanggan"], "daily_cap": None},
    "facilities": FACILITIES,
}
with open(os.path.join(DATA, "meta_economy.json"), "w", encoding="utf-8") as f:
    json.dump(meta, f, ensure_ascii=False, indent=2)

def half(v):
    return int(round(v * 0.5 / 50) * 50)

ach_json = {"schema": "soulpath.achievements", "version": 2, "doc": "design/09-meta-economy.md#13",
            "note": "보상은 기준가(econ_price_scale 적용 전).",
            "achievements": [{"id": i, "name_ko": n, "category": c, "condition_ko": cond,
                              "reward": {"cur_gongdeok": half(g), "cur_bokjeon": half(b), "item": x}, "hidden": h,
                              "steam_api_name": i.upper()} for i, n, c, cond, g, b, x, h in ACH]}
with open(os.path.join(DATA, "achievements.json"), "w", encoding="utf-8") as f:
    json.dump(ach_json, f, ensure_ascii=False, indent=2)

# ---------------------------------------------------------------- example profile save (v1 schema + review fields)
payload = {
    "version": 1,
    "game_build": "1.0.0+b1234",
    "profile_id": "7f3c2a9e-1b4d-4e7a-9c11-2f6b8d0e5a77",
    "created_utc": "2026-11-20T09:12:00Z",
    "updated_utc": "2026-11-22T14:03:41Z",
    "playtime_s": 18240,
    "wallet": {"cur_gongdeok": 12450, "cur_bokjeon": 7310},
    "ledger": {"cur_gongdeok": {"earned": 109050, "spent": 96600}, "cur_bokjeon": {"earned": 66110, "spent": 58800}},
    "unlocks": {
        "chars": ["char_mansin", "char_baksu", "char_dangol"],
        "char_ready": ["char_simbang"],
        "weapons": ["wpn_sinkal", "wpn_woldo", "wpn_gakgung", "wpn_samjichang", "wpn_jangchang", "wpn_jakdu",
                    "wpn_bangul", "wpn_buchae", "wpn_jijeon", "wpn_neokjeon", "wpn_ssukmul", "wpn_janggu"],
        "weapons_discovered": ["wpn_gilbe"],
        "evos_discovered": ["evo_sinjangkal", "evo_cheoneum_bangul"],
        "unions_discovered": [],
        "recipes_revealed": ["evo_irwolseonpung"],
        "stages": ["stage_guksadang", "stage_jindo_ssitgim"],
        "modes": ["mode_pyojun", "mode_jajinmori", "mode_oneul"],
    },
    "forge": {"forge_gongsu": 2, "forge_mullim": 1, "forge_geumgi": 1},
    "shrines": {
        "deity_sansin": {"level": 2, "bingui": 11, "faces": ["face_wieom", "face_gaho"], "gongsu_tier_seen": 2,
                         "jeongseong": 0, "jemul": 0},
        "deity_yongwang": {"level": 1, "bingui": 4, "faces": ["face_gaho"], "gongsu_tier_seen": 1, "jeongseong": 6300, "jemul": 0},
        "deity_chilseong": {"level": 1, "bingui": 3, "faces": ["face_gaho"], "gongsu_tier_seen": 1, "jeongseong": 0, "jemul": 0},
        "deity_janggun": {"level": 1, "bingui": 6, "faces": ["face_wieom"], "gongsu_tier_seen": 1, "jeongseong": 0, "jemul": 0},
        "deity_barigongju": {"level": 1, "bingui": 2, "faces": ["face_gaho"], "gongsu_tier_seen": 1, "jeongseong": 0, "jemul": 0},
        "deity_jeseok_daegam": {"level": 1, "bingui": 1, "faces": ["face_wieom"], "gongsu_tier_seen": 1, "jeongseong": 0, "jemul": 0},
    },
    "cheongbae_mark": "deity_sansin",
    "myeongdu": {
        "collected": ["myeongdu_sansin__wieom", "myeongdu_sansin__gaho", "myeongdu_yongwang__gaho",
                      "myeongdu_chilseong__gaho", "myeongdu_janggun__wieom", "myeongdu_barigongju__gaho",
                      "myeongdu_jeseok_daegam__wieom"],
        "nodes_unlocked": ["myd_a1_mumyeong_jeogori", "myd_b1_sinppal", "myd_c1_haengnyeol", "myd_c2_neok_sumyeong"],
        "loadout": ["myd_a1_mumyeong_jeogori", "myd_b1_sinppal", "myd_c1_haengnyeol", "myd_c2_neok_sumyeong"],
    },
    "singirok": {
        "haewonrok": {"enm_dalgyal_gwisin": {"pieces": [1, 2], "haewon": 812, "neokduri_seen": 255,
                                                "sc_progress": {"sc_ring_species_20": 14}},
                      "enm_agwi": {"pieces": [1], "haewon": 140, "neokduri_seen": 7}},
        "byeoksarok": {"enm_dalgyal_gwisin": {"toechi": 655, "tier": 2},
                       "elite_dueoksini": {"toechi": 12, "tier": 1}},
        "milestones_claimed": [18],
        "byeoksa_milestones_claimed": [],
        "uiryeseo_done": [],
    },
    "companions": {"unlocked": ["comp_dalgyal"], "equipped": "comp_dalgyal"},
    "ladder": {"max_dan_cleared": 3, "best_dan_by_char": {"char_mansin": 3, "char_baksu": 1},
               "best_dan_by_stage": {"stage_guksadang": 3, "stage_jindo_ssitgim": 2},
               "first_clear_claimed": [1, 2, 3], "selected_dan": 4},
    "uiroe": {"offered": ["uiroe_jangsa", "uiroe_honrye", "uiroe_horangi"], "offered_age_runs": [0, 1, 2],
              "accepted": None, "completed": ["uiroe_dokkaebi"]},
    "achievements": {"ach_first_haewon": "2026-11-20T09:13:05Z", "ach_first_clear": "2026-11-20T11:40:12Z"},
    "ach_progress": {"ach_haewon_1000": 1000, "ach_haewon_10000": 3412},
    "cosmetics": {"owned": ["cos_mubok_sosaek"], "equipped": {"char_mansin": "cos_mubok_sosaek"},
                  "titles_owned": ["title_saenae_mudang"], "title_equipped": "title_saenae_mudang"},
    "lobby": {"lt_yeondeung": 0, "lt_punggyeong": 0, "pending_crossings": ["enm_dalgyal_gwisin"]},
    "daily": {"last_record_date_utc": "2026-11-22", "pending_submissions": []},
    "ach_pending_platform": [],
    "active_run_uid": None,
    "run_guard": {"suspend_nonce": None, "crash_resumes": {}},
    "settled_run_uids": ["r-000014", "r-000015", "r-000016"],
    "tamper_flag": False,
    "counters": {"cnt_haewon_total": 3412, "cnt_toechi_total": 2980, "cnt_bingui_wieom_total": 5,
                 "cnt_box_gilhyung_opened": 27, "cnt_eodukssini_silence": 3, "cnt_companions_unlocked": 1,
                 "cnt_byeoksa_tiers": 9, "cnt_runs": 16, "cnt_clears": 5, "cnt_gildakkeum": 410},
    "run_history": [{"run_uid": "r-000016", "seed": "4096128833", "stage": "stage_jindo_ssitgim",
                     "mode": "mode_pyojun", "dan": 3, "char": "char_mansin", "result": "CLEAR_BOW",
                     "time_s": 1262, "haewon": 2390, "toechi": 2050, "neok": 6020, "yeopjeon": 4950,
                     "gongdeok_gain": 13137, "bokjeon_gain": 7201, "build_hash": "b1234"}],
    "flags": {"tutorial_done": True, "seen_settlement_tips": 3},
}
canon = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
save = {"payload": payload, "integrity": {"algo": "sha256", "digest": hashlib.sha256(canon.encode("utf-8")).hexdigest()}}
with open(os.path.join(DATA, "save_profile.example.json"), "w", encoding="utf-8") as f:
    json.dump(save, f, ensure_ascii=False, indent=2)

# ---------------------------------------------------------------- summary + optional markdown fragments
tg = sum(half(a[4]) for a in ACH); tb = sum(half(a[5]) for a in ACH)
print("ach", len(ACH), tg, tb)
print("myd total", sum(x[8] for x in MYD), "G", sum(x[8] for x in MYD if x[9] == "cur_gongdeok"))
print("weapons total", sum(w[4] for w in WEAPONS))
print("forge total", sum(sum(v["costs"]) for k, v in FORGE.items() if k.startswith("forge_")))
print("shrine G", 6 * sum(l["jeongseong_gongdeok"] for l in SHRINE_LV), "B", 6 * sum(l["jemul_bokjeon"] for l in SHRINE_LV))
print("chars v1", sum(c[2] for c in CHARS if c[0] != "char_beopsa"))
if "--md" in sys.argv:
    out = sys.argv[sys.argv.index("--md") + 1]
    md = ["| 단 | ID | 이름 | 압박 | 수정자 | 훅 변수 | 배율 | 첫 클리어 보상 |", "|---:|---|---|---|---|---|---:|---|"]
    side_ko = {"sal": "살 쪽", "han": "넋 쪽", "common": "공통"}
    for d, n, side, m, hooks in DAN:
        cos = DAN_COSMETIC.get(d)
        hk = ", ".join(f"`{k}`" for k in hooks)
        md.append(f"| {d} | `dan_{d:02d}` | {n} | {side_ko[side]} | {m} | {hk} | ×{1+0.05*d:.2f} | 공덕 {300*d:,} + 복전 {300*d:,}{(' + `'+cos+'`') if cos else ''} |")
    open(out, "w", encoding="utf-8").write("\n".join(md))
