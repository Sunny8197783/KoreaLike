# -*- coding: utf-8 -*-
"""data/weapons.json + 문서 표 조각 생성기. 사용: python -I gen.py <project_root>"""
import sys, os, json, math, copy
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from wdata import *
from analyze import levels, k_band

ROOT = sys.argv[1]
FR = {}

LABEL = {
    'dmg': '피해', 'cd': '쿨(초)', 'amt': '수', 'area': '범위(u)', 'pierce': '관통', 'spd': '속도(u/s)', 'hitbox': '판정 반경(u)',
    'catch_r': '귀환 참격 반경(u)', 'spins': '회전 수', 'kb': '넉백(u)', 'wave_dmg': '검기 피해', 'waves': '검기 수',
    'wave_range': '검기 사거리(u)', 'wave_pierce': '검기 관통', 'wave_width': '검기 폭(u)', 'wave_spd': '검기 속도(u/s)',
    'prongs': '갈래', 'thrusts': '연타/찌르기', 'width': '폭(u)', 'mark': '표식 증폭', 'verdict_chance': '판결 확률', 'verdict_cd': '판결 쿨(초)',
    'invuln': '무적(초)', 'lowhp_k': '저정기 계수', 'wave2_mult': '2파 배율', 'wave2_area': '2파 반경 배율', 'min_period': '최소 주기(초)',
    'elite': '정예+ 배율', 'bolt_dmg': '낙뢰 피해', 'bolt_r': '낙뢰 반경(u)', 'bolts_per_wave': '검기당 낙뢰', 'grand_every': '일제 낙뢰 주기(검기)',
    'grand_bolts': '일제 낙뢰 수', 'grand_dmg': '일제 낙뢰 피해', 'crit': '결단 가산', 'blast_dmg': '폭발 피해', 'blast_r': '폭발 반경(u)',
    'burn_dps': '화상(초당)', 'burn_dur': '화상 지속(초)', 'lunge_dmg': '창기 피해', 'lunge_range': '창기 사거리(u)', 'lunge_spd': '창기 속도(u/s)',
    'run_threshold': '창기 발동 이속(u/s)', 'domu_scale': '도무 환산', 'domu_cap': '도무 보너스 상한', 'hp_scale': '최대 정기 가산 비율',
    'angle': '각도(°)', 'back': '역타', 'ring_mult': '충격 고리 배율', 'ring_r': '충격 고리 반경(u)', 'ring_offset': '고리 거리(u)', 'ring_stun': '고리 경직(초)',
    'dur': '지속(초)', 'charges': '내구(타)', 'root': '봉박(초)', 'max_act': '동시 상한', 'formation': '진형 마름쇠', 'formation_r': '진형 반경(u)',
    'salgi_ref': '계산 기준 살기', 'salgi_cap': '살기 상한', 'fear': '공포(초)', 'fear_amp': '공포 대상 피해 증폭', 'stagger': '경직(초)',
    'res_dmg': '공명 피해', 'res_r': '공명 반경(u)', 'res_beats': '공명 주기(박)', 'res_period_ref': '공명 주기(중모리 기준, 초)', 'pull_spd': '끌어오기(u/s)',
    'orb_pull_r': '구슬 흡인 반경(u)', 'gusts': '돌풍 수', 'whirl': '회오리 수', 'whirl_dmg': '회오리 피해', 'whirl_tick': '회오리 틱(초)', 'whirl_r': '회오리 반경(u)',
    'orbit_r': '공전 반경(u)', 'dash_every': '돌진 주기(초)', 'pull_r': '끌어오기 반경(u)', 'omega': '각속도(°/s)', 'permanent': '상시',
    'petal_dmg': '꽃잎 피해', 'petal_r': '꽃잎 반경(u)', 'petal_every_beats': '꽃잎 주기(박)', 'petal_period_ref': '꽃잎 주기(중모리, 초)', 'hit_iv': '재타격 간격(초)',
    'chain': '연쇄 해원', 'chain_r': '연쇄 반경(u)', 'slow': '감속', 'tick': '틱(초)', 'trail_dmg': '트레일 피해', 'trail_width': '트레일 폭(u)', 'trail_len_ref': '트레일 길이(기준, u)',
    'puddles': '장판/바가지', 'hyang_puri': '향물 풀이 가산', 'ssuk_slow': '쑥물 감속', 'malgeun_heal': '맑은물 회복(초당)', 'push': '밀어내기(u)', 'purge_r': '정화 반경(u)',
    'purge_rate': '정화 속도(개/초)', 'burst_dmg': '정화 폭발 피해', 'burst_r': '정화 폭발 반경(u)', 'mirrors': '거울 수', 'reflect': '반사 횟수', 'reflect_decay': '반사 감쇠',
    'dark': '어둑시니 축소/타', 'light_r': '광명 구역 반경(u)', 'gideok_dmg': '기덕 피해', 'gideok_r': '기덕 반경(u)', 'counter_dmg': '반격 파동 피해', 'counter_r': '반격 반경(u)',
    'counter_icd': '반격 내부 쿨(초)', 'stun_beats': '진 경직(박)', 'buff': '버프 배율', 'white_dmg': '백 피해(풀릴 기색 대상)', 'orbit': '넋전 수', 'orbit_dmg': '넋전 피해',
    'aura_r': '결계 반경(u)', 'aura_dmg': '결계 피해', 'purge_in_blast': '폭발 정화', 'ring_judge': '고리 판정', 'reflect_mult': '반사 검기 배율', 'dark_shrink': '어둑시니 축소/타',
    'convert_haewon': '퇴치→해원 전환', 'caltrops': '마름쇠 수', 'field_dmg': '결계 피해', 'mass_haewon_cap': '일괄 해원 상한', 'pulse_dmg': '맥동 피해', 'pulse_cd': '맥동 간격(초)', 'pulse_r': '맥동 반경(u)',
    'pull_slow': '풀릴 기색 추가 감속', 'spin_time': '회전 시간(초)', 'ring2': '후속 고리', 'expand': '확산 시간(초)', 'thrust_iv': '연타 간격(초)', 'windup': '예비 동작(초)', 'purge': '정화 반경 배율',
    'purge_cap': '1회 정화 상한', 'orbit_r_': '', 'verdict': '',
}

def fmt(v, key=None):
    if isinstance(v, (int, float)):
        if key in ('pierce', 'wave_pierce') and v == INF:
            return '∞'
        if key in ('mark', 'fear_amp', 'slow', 'ssuk_slow', 'pull_slow', 'crit', 'domu_cap', 'hp_scale', 'reflect_decay', 'dark', 'dark_shrink', 'verdict_chance', 'malgeun_heal'):
            return ('%g%%' % round(v * 100, 2))
        if abs(v - round(v)) < 1e-9:
            return str(int(round(v)))
        return ('%.2f' % v).rstrip('0').rstrip('.')
    return str(v)

def d1(x):
    return ('%.0f' % x) if x >= 100 else ('%.1f' % x)

wmap = {w['id']: w for w in WEAPONS}
emap = {e['id']: e for e in EVOS}

# ---------------- 레벨 표 ----------------
for w in WEAPONS:
    L = levels(w)
    hdr = ['Lv', '변화'] + [c[1] for c in w['cols']] + ['DPS 보스', 'DPS 군집']
    rows = ['| ' + ' | '.join(hdr) + ' |', '|' + '---|' * len(hdr)]
    for i, s in enumerate(L):
        ch = '기본' if i == 0 else w['deltas'][i - 1][0]
        b, c = w['model'](s)
        cells = [str(i + 1), ch] + [fmt(s.get(k, 0), k) for k, _ in w['cols']] + [d1(b), d1(c)]
        rows.append('| ' + ' | '.join(cells) + ' |')
    FR['LV:' + w['id']] = '\n'.join(rows)
    e = emap[w['evo']]
    eb, ec = e['model'](e['stats'])
    b8, c8 = w['model'](L[7])
    erows = ['| 항목 | 값 |', '|---|---|']
    for k, v in e['stats'].items():
        erows.append('| %s (`%s`) | %s |' % (LABEL.get(k, k), k, fmt(v, k)))
    erows.append('| **DPS 추정 보스 / 군집** | **%s / %s** (Lv8 대비 군집 ×%.2f) |' % (d1(eb), d1(ec), ec / c8))
    FR['EVO:' + e['id']] = '\n'.join(erows)

# ---------------- 결합 표 ----------------
for u in UNIONS:
    ub, uc = u['model'](u['stats'])
    rows = ['| 항목 | 값 |', '|---|---|']
    for k, v in u['stats'].items():
        rows.append('| %s (`%s`) | %s |' % (LABEL.get(k, k), k, fmt(v, k)))
    rows.append('| **DPS 추정 보스 / 군집** | **%s / %s** |' % (d1(ub), d1(uc)))
    FR['UNION:' + u['id']] = '\n'.join(rows)

# ---------------- DPS 요약 ----------------
rows = ['| 무구 | 색 | Lv1 보스 | Lv1 군집 | Lv8 보스 | Lv8 군집 | 진화형 | 진화 보스 | 진화 군집 | 진화/Lv8 |', '|---|---|---|---|---|---|---|---|---|---|']
red8 = []; white8 = []; rede = []; whitee = []
for w in WEAPONS:
    L = levels(w)
    b1, c1 = w['model'](L[0]); b8, c8 = w['model'](L[7])
    e = emap[w['evo']]; eb, ec = e['model'](e['stats'])
    (red8 if w['color'] == 'red' else white8).append(c8)
    (rede if w['color'] == 'red' else whitee).append(ec)
    rows.append('| %s `%s` | %s | %s | %s | %s | %s | %s | %s | %s | ×%.2f |' % (
        w['name'], w['id'], '적' if w['color'] == 'red' else '백', d1(b1), d1(c1), d1(b8), d1(c8), e['name'], d1(eb), d1(ec), ec / c8))
FR['DPS_SUMMARY'] = '\n'.join(rows)
avg = lambda a: sum(a) / len(a)
FR['DPS_AVG'] = ('| 집계(군집 DPS) | 적 무구 평균 | 백 무구 평균 | 백/적 비 |\n|---|---|---|---|\n'
                 '| Lv8 | %s | %s | %.2f |\n| 진화형 | %s | %s | %.2f |\n'
                 '| 풀릴 기색 대상 실효(백 ×3.0) Lv8 | — | %s | %.2f |') % (
    d1(avg(red8)), d1(avg(white8)), avg(white8) / avg(red8), d1(avg(rede)), d1(avg(whitee)), avg(whitee) / avg(rede),
    d1(avg(white8) * 3), avg(white8) * 3 / avg(red8))

rows = ['| 결합 | 재료 | 범위 | DPS 보스 | DPS 군집 | 재료 진화형 군집 합 | 비 |', '|---|---|---|---|---|---|---|']
for u in UNIONS:
    ub, uc = u['model'](u['stats'])
    ssum = sum(emap[p]['model'](emap[p]['stats'])[1] for p in u['parts'])
    rows.append('| %s `%s` | %s + %s | %s | %s | %s | %s | ×%.2f |' % (u['name'], u['id'], emap[u['parts'][0]]['name'], emap[u['parts'][1]]['name'], u['scope'], d1(ub), d1(uc), d1(ssum), uc / ssum))
FR['UNION_SUMMARY'] = '\n'.join(rows)

# ---------------- 파열 성향 ----------------
CK = [('Lv1 @00:30', 0, 0.5, 1.0), ('Lv4 @05:00', 3, 5, 1.1), ('Lv8 @10:00', 7, 10, 1.3), ('진화 @15:00', 'evo', 15, 1.6), ('진화 @20:00', 'evo', 20, 1.9)]
rows = ['| 적 무구 | ' + ' | '.join('%s (한 %.1f, 신빨 %d%%)' % (n, H(t), sp * 100) for n, _, t, sp in CK) + ' |', '|---|' + '---|' * len(CK)]
for w in WEAPONS:
    if w['color'] != 'red':
        continue
    L = levels(w)
    cells = []
    for n, lv, t, sp in CK:
        if lv == 'evo':
            st = emap[w['evo']]['stats']
        else:
            st = L[lv]
        dmg = st['dmg'] + (8 if w['id'] == 'wpn_pyeongon' and lv == 'evo' else 0)
        k = dmg * sp / H(t)
        cells.append('k=%.2f → %s' % (k, k_band(k)))
    rows.append('| %s | %s |' % (w['name'], ' | '.join(cells)))
FR['RUPTURE'] = '\n'.join(rows)

# 레버 비교 (리뷰 R1): 15:00·20:00 진화형 k, 현행 / 레버 A(07 T 이차항 0.006) / 레버 B(적 진화 1타 ×1.5·주기 ×1.5)
LEV = [('진화 @15:00', 15, 1.6), ('진화 @20:00', 20, 1.9)]
hdr = ['적 진화형']
for n, t, sp in LEV:
    hdr += ['%s 현행 (한 %.1f)' % (n, H(t)), '레버 A (한 %.1f)' % H(t, T_B_LEVER_A), '레버 B (1타 ×%.1f)' % RED_SHAPE_LEVER_B]
rows = ['| ' + ' | '.join(hdr) + ' |', '|---|' + '---|' * (len(hdr) - 1)]
lever_count = {'cur': 0, 'A': 0, 'B': 0}
for w in WEAPONS:
    if w['color'] != 'red':
        continue
    e = emap[w['evo']]
    dmg = e['stats']['dmg'] + (8 if w['id'] == 'wpn_pyeongon' else 0)
    cells = []
    for n, t, sp in LEV:
        k0 = dmg * sp / H(t); kA = dmg * sp / H(t, T_B_LEVER_A); kB = k0 * RED_SHAPE_LEVER_B
        for key, kk in (('cur', k0), ('A', kA), ('B', kB)):
            if t == 20 and k_band(kk).startswith('파열'):
                lever_count[key] += 1
        cells += ['k=%.2f → %s' % (k0, k_band(k0)), 'k=%.2f → %s' % (kA, k_band(kA)), 'k=%.2f → %s' % (kB, k_band(kB))]
    rows.append('| %s | %s |' % (e['name'], ' | '.join(cells)))
rows.append('| **20:00 파열 성향 진화형 수 (10종 중)** | | | | **%d** | **%d** | **%d** |' % (lever_count['cur'], lever_count['A'], lever_count['B']))
FR['RUPTURE_LEVER'] = '\n'.join(rows)

# 시간대별 기준 한 표 (07 T 곡선 복제)
FR['HAN_CURVE'] = ('| 분 m | 0 | 0.5 | 3 | 5 | 6 | 9 | 10 | 12 | 15 | 18 | 20 |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n'
                   '| T(m) | ' + ' | '.join('%.3f' % T(m) for m in (0, 0.5, 3, 5, 6, 9, 10, 12, 15, 18, 20)) + ' |\n'
                   '| 기준 잡귀 한 = 12 × T(m) | ' + ' | '.join('%.1f' % H(m) for m in (0, 0.5, 3, 5, 6, 9, 10, 12, 15, 18, 20)) + ' |\n'
                   '| (구) 04 가정 H(t) — 폐기 | ' + ' | '.join('%.1f' % (12 * (1 + 0.12 * m + 0.006 * m * m)) for m in (0, 0.5, 3, 5, 6, 9, 10, 12, 15, 18, 20)) + ' |')

# ---------------- 빌드 몬테카를로 (리뷰 R2·R4·R7) ----------------
import buildsim as BS
SIM = BS.run_all(1000)
mm = BS.mmss

def trip(x):
    return '%s (%s~%s)' % (mm(x[1]), mm(x[0]), mm(x[2]))

rows = ['| 지표 | ' + ' | '.join(lbl for lbl, _ in SIM.values()) + ' |', '|---|' + '---|' * len(SIM)]
for key, name in (('first_lv8', '첫 무구 Lv8 중앙값 (p25~p75)'), ('evo1', '첫 진화'), ('evo2', '두 번째 진화'), ('evo3', '세 번째 진화'),
                  ('evo4', '네 번째 진화'), ('evo5', '다섯 번째 진화'), ('evo6', '여섯 번째 진화'), ('union1', '첫 결합')):
    rows.append('| %s | %s |' % (name, ' | '.join(trip(S[key]) for _, S in SIM.values())))
rows.append('| 20:00 진화 수 중앙값 (p25~p75) | %s |' % ' | '.join('%d (%d~%d)' % (S['n_evo'][1], S['n_evo'][0], S['n_evo'][2]) for _, S in SIM.values()))
rows.append('| 진화 5개 이상 런 비율 | %s |' % ' | '.join('%.0f%%' % (S['evo_ge5'] * 100) for _, S in SIM.values()))
rows.append('| 결합 1회 이상 런 비율 | %s |' % ' | '.join('%.0f%%' % (S['union_rate'] * 100) for _, S in SIM.values()))
rows.append('| 점지 선택 비율 무구 / 패시브 / 권능 | %s |' % ' | '.join('%.0f / %.0f / %.0f%%' % (S['pick_share']['weapon'] * 100, S['pick_share']['passive'] * 100, S['pick_share']['power'] * 100) for _, S in SIM.values()))
FR['EVO_TIMING'] = '\n'.join(rows).replace('99:00', '없음')

ref = SIM['red_all20'][1]['snap']
mix = SIM['mix_all20'][1]['snap']
rows = ['| 시각 | 무구 수 | 무구 레벨 합 | 패시브 수 | 권능 픽 누적 | 진화 수 | 단일 대상 DPS 합 | **위엄 유효 DPS** (적 1.0·백 0.4·결합 0.7) | HP_wieom 제안 (×25초) |', '|---|---|---|---|---|---|---|---|---|']
DPS_REF = {}
for t in BS.SNAP:
    d = ref[t]
    DPS_REF[t] = d
    rows.append('| %02d:00 | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | **%.0f** | %s |' % (
        t, d['n_wpn'], d['wpn_levels'], d['n_psv'], d['pwr_picks'], d['n_evo'], d['single'], d['wieom'],
        ('{:,}'.format(int(round(d['wieom'] * 25 / 100.0) * 100))) if t <= 15 else '— (시련 없음)'))
FR['DPS_REF'] = '\n'.join(rows)

# 보스·중간보스 한 역산 제안 (단일 대상 DPS 합 기준, 적 위주 빌드)
d10 = (ref[9]['single'] + ref[12]['single']) / 2.0
FR['BOSS_HAN_SUGGEST'] = ('| 대상 | 07 현행 한 | 07 목표 TTK | 기준 DPS (적 위주 중앙값) | 현행 TTK | 목표 TTK 중앙값으로 역산한 한 |\n|---|---|---|---|---|---|\n'
    '| 중간보스 (10:00) | 9,000 | 50~70초 | ≈%.0f (09·12분 보간) | %.0f초 | ≈%s |\n'
    '| 스테이지 보스 살형 (20:00) | 72,000 | 130~160초 | %.0f | %.0f초 | ≈%s |\n'
    '| 스테이지 보스 한형 (20:00) | 48,000 | 120~150초 | %.0f | %.0f초 | ≈%s (백 ×3 창 구조는 07 유지) |') % (
    d10, 9000 / d10, '{:,}'.format(int(round(d10 * 60 / 1000.0) * 1000)),
    ref[20]['single'], 72000 / ref[20]['single'], '{:,}'.format(int(round(ref[20]['single'] * 145 / 1000.0) * 1000)),
    ref[20]['single'], 48000 / ref[20]['single'], '{:,}'.format(int(round(ref[20]['single'] * 90 / 1000.0) * 1000)))

# 화력 여유비 (혼합 · 해금 20종 중앙값 빌드, 07 T 곡선)
K_MIN = [30, 45, 60, 85, 100, 115, 140, 160, 180, 200, 215, 230, 260, 285, 310, 335, 360, 380, 420, 450]
rows = ['| 시각 | 가정 밀도 ρ | 기준 신빨 | 빌드(중앙값): 무구 수 · 레벨 합 · 진화 · 패시브 · 권능 픽 | 적 DPS 용량 | 백 DPS 용량 | 유입 한/초 (분당 처치 × 12 × T) | 여유비(용량) | 실효 여유비(×0.5) |', '|---|---|---|---|---|---|---|---|---|']
HEAD = {}
for t in BS.SNAP:
    d = mix[t]
    inflow = K_MIN[t - 1] / 60.0 * H(t)
    ratio = (d['crowd_red'] + d['crowd_white']) / inflow
    HEAD[t] = ratio
    rows.append('| %02d:00 | %.2f | %d%% | %.0f · %.0f · %.0f · %.0f · %.0f | %s | %s | %.1f | %.1f | ≈%.1f |' % (
        t, BS.interp(BS.RHO_T, t), round(BS.interp(SINPPAL_REF, t) * 100), d['n_wpn'], d['wpn_levels'], d['n_evo'], d['n_psv'], d['pwr_picks'],
        '{:,}'.format(int(round(d['crowd_red']))), '{:,}'.format(int(round(d['crowd_white']))), inflow, ratio, ratio * 0.5))
FR['HEADROOM'] = '\n'.join(rows)

# 백 마무리 타수
rows = ['| 백 무구 | ' + ' | '.join(n for n, _, _, _ in CK) + ' |', '|---|' + '---|' * len(CK)]
for w in WEAPONS:
    if w['color'] != 'white':
        continue
    L = levels(w)
    cells = []
    for n, lv, t, sp in CK:
        st = emap[w['evo']]['stats'] if lv == 'evo' else L[lv]
        hit = st['dmg'] * sp * 3.0
        need = 0.35 * H(t)
        cells.append('%.1f vs %.1f → %d타' % (hit, need, math.ceil(need / hit - 1e-9)))
    rows.append('| %s | %s |' % (w['name'], ' | '.join(cells)))
FR['FINISH'] = '\n'.join(rows)

# ---------------- 박 양자화 ----------------
def pattern(P, g, n=12):
    # 05 3.2.2a 위상 이월(phase carry): ideal_t += cd, 최소 간격 1그리드, 지연 > 1그리드면 이월 버림
    ideal = P; last_k = 0; last_t = -1e9; fires = []
    for k in range(1, 400):
        t = k * g
        if t + 1e-9 >= ideal and t >= last_t + g - 1e-9:
            fires.append(k - last_k); last_k = k; last_t = t
            ideal += P
            if t - ideal > g:
                ideal = t + P
            if len(fires) >= n:
                break
    return fires

rows = ['| 거리 | 장단 | BPM | 1박(초) | 그리드 | 그리드(초) | P=0.6 | P=1.0 | P=1.5 | P=2.2 | P=3.0 |', '|---|---|---|---|---|---|---|---|---|---|---|']
for gid, gname, jd, bpm, span, frac in GEORI:
    beat = 60.0 / bpm; g = beat * frac
    cells = []
    for P in (0.6, 1.0, 1.5, 2.2, 3.0):
        Pe = max(P, g)
        f = pattern(Pe, g, 8)
        cells.append('%s (평균 %.2f)' % ('-'.join(str(x) for x in f[:6]), sum(f) * g / len(f)))
    rows.append('| %s `%s` | %s | %d | %.3f | %s박 | %.3f | %s |' % (gname, gid, jd, bpm, beat, '1/4' if frac == 0.25 else '1/2', g, ' | '.join(cells)))
FR['GRID'] = '\n'.join(rows)

# ---------------- 한도 표 ----------------
rows = ['| 무구 | 동시 활성 상한 | 최소 주기(초) | 신장 수 상한 | 신장 수 환산 규칙 |', '|---|---|---|---|---|']
for w in WEAPONS:
    lm = w['limits']
    rows.append('| %s `%s` | %d | %s | +%d | %s |' % (w['name'], w['id'], lm['max_active'], fmt(lm['min_period']), lm['amt_cap'], w['amount_rule']))
FR['LIMITS'] = '\n'.join(rows)

# 의례 기준값
FR['RITUAL'] = '| Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 | Lv7 | Lv8 | 진화형 | 결합 |\n|---|---|---|---|---|---|---|---|---|---|\n| ' + ' | '.join(str(RITUAL_REF[k]) for k in [1, 2, 3, 4, 5, 6, 7, 8, 'evo', 'union']) + ' |'

# ---------------- JSON ----------------
def jnum(v):
    if isinstance(v, float) and abs(v - round(v)) < 1e-9:
        return int(round(v))
    if isinstance(v, float):
        return round(v, 4)
    return v

def clean(d):
    return {k: jnum(v) for k, v in d.items()}

out = {
    'schema_version': 1,
    'source_doc': 'design/04-weapons-evolution.md',
    'canon_doc': 'design/01-concept-and-canon.md',
    'units': {'distance': 'unit (1u = 32px)', 'time': 'seconds (game time)', 'pierce_infinite': -1, 'percent_fields_are_fractions': True},
    'globals': {
        'damage_formula': 'final = round((level_dmg + flat_add) * (1 + sum(sinppal_pct)) * state_mult * crit_mult * special_mults), min 1',
        'state_mult': {'white_vs_pullil': 3.0, 'white_vs_pullil_stat': 'stat_puri (cap 6.0)', 'red_vs_pullil_common': 'maedeup_lock: hp floor 1 (elite+ exempt)'},
        'crit': {'stat': 'stat_gyeoldan', 'base': CRIT_BASE, 'cap': 0.5, 'mult_vs_normal': CRIT_MULT, 'vs_pullil_common': 'instant toechi (ignores maedeup lock)', 'applies_to': 'red only (union: red-mode hits only)'},
        'variance': 0,
        'quantization': {'owner': 'design/05-stats-passives.md 3.2.2a', 'mode': 'phase_carry',
                         'algorithm': 'on grid tick t: fire if t >= ideal_t and t >= last_fire_t + grid; ideal_t += P_eff; if t - ideal_t > grid: ideal_t = t + P_eff',
                         'grid': 'see geori_grid[].grid_beat_fraction (1/2 beat; 1/4 beat in geori_jutang_bujeong) [pending 12-audio CR on 1/3 beat]',
                         'downbeat_weapons': ['wpn_janggu', 'evo_hapjangdan'], 'downbeat_grid': '1 beat'},
        'cooldown': {'formula': 'P_eff = max(min_period, base_cd * max(floor, stat_jangdan), grid)', 'floor': 0.40, 'floor_sinmyeong_oreum': 0.25},
        'projectile_pool': {'global_soft_cap': 600, 'global_hard_cap': 768, 'merge_rule': 'spawn m<n -> dmg*n/m (cap x3); m=0 -> recycle oldest of same weapon', 'zone_cap_global': 64, 'hit_pair_budget_per_frame': 4000},
        'amount_cap_global': 10,
        'hit_lockout': 'per weapon instance per target; zones of same weapon do not stack on one target (one tick / tick interval)',
        'knockback_vs_pullil': {'white': 0.0, 'red': 1.0, 'note': 'white weapons never push pullil targets; buchae pulls 0.5u instead'},
        'red_vs_pullil_common': {'auto_aim': 'excluded', 'projectile_pass_through': True, 'pierce_consumed': False,
                                 'area_hit': 'maedeup_lock (dmg floor han 1, "tuk" feedback); crit still instant toechi',
                                 'note': 'review R11: red projectiles fly through giseak common/minion without spending pierce; elite+ unaffected'},
        'wieom': {'owner': 'design/06-deities-possession.md 3.5.1 / data/deities.json constants.wieom_color_coeff',
                  'color_coeff_ref': {'red': 1.0, 'white': 0.4, 'union': 0.7}, 'white_auto_aim_avatar': False,
                  'presence_factor': 'owned by 06 (02 proposes 0.35 outside 6u; pending)'},
        'status_effects': {'owner_apply': 'design/04 (duration/strength per weapon level)', 'owner_player_side': 'design/02 11.3 / combat_core.json',
                           'owner_enemy_resist': 'design/07 2.6 / enemies.json',
                           'ids': ['st_gongpo', 'st_bongbak', 'st_gyeongjik', 'st_pyosik', 'st_hwasang', 'st_dunhwa'],
                           'alias_pending_07': {'st_gyeongak': 'st_gongpo'}, 'slow_floor_speed': 0.30},
        'eodukssini': {'auto_aim_excluded': ['red'], 'red_hit_growth': 0.03, 'white_hit_shrink': 0.02, 'myeongdu_hit_shrink': 'per weapon field dark'},
        'bulgasari_absorb_tag': 'metal',
        'ritual_ref': {str(k): v for k, v in RITUAL_REF.items()},
        'ritual_ref_use': ['yeongga aura tick dmg = 0.15 * max ritual_ref among owned white weapons (union counts as white, 40) * sinppal * grid_g  (tick every grid g; per-second = 0.15 * ritual_ref * sinppal)',
                           'gildakkeum effect2 = 2 * sum(ritual_ref of owned white weapons) * sinppal (single hit at ring close)',
                           'no white weapon owned: ritual_ref fallback = 10 (= Lv1)'],
        'reference_curves': {'enemy_han': {'owner': 'design/07-enemies-bosses.md 3.2 / data/enemies.json scaling.T_han',
                                           'formula': 'han_base * T(m), T(m) = 1 + 0.18m + 0.012m^2', 'han_base_ref': HAN_BASE_REF,
                                           'values': {str(m): round(H(m), 1) for m in (0, 3, 5, 6, 9, 10, 12, 15, 18, 20)}},
                             'sinppal_ref': SINPPAL_REF, 'density_rho': RHO, 'aoe_expected_cap': AOE_CAP,
                             'dps_ref': {'source': 'tools/wpn04/buildsim.py profile red_all20 (median of 1000 runs) [assumption until 09 bot sim]',
                                         'minutes': BS.SNAP,
                                         'single_target_sum': [round(DPS_REF[t]['single']) for t in BS.SNAP],
                                         'wieom_effective': [round(DPS_REF[t]['wieom']) for t in BS.SNAP],
                                         'hp_wieom_suggest_x25s': [int(round(DPS_REF[t]['wieom'] * 25 / 100.0) * 100) for t in BS.SNAP if t <= 15]},
                             'headroom_mix_all20': {str(t): round(HEAD[t], 2) for t in BS.SNAP}},
        'evolution_rule': {'requires': ['weapon level 8', 'pair passive level>=1', 'open box_gilhyung or box_neokham'],
                           'box_contents': 'grade 1/3/5 items (05 12.1); per item: union -> evolution (union+evolution max 1 per box) -> +1 level to highest-level owned weapon (Lv<8) -> +1 to highest-level passive (Lv<5) -> yeopjeon',
                           'box_never_adds_new_item': True,
                           'priority': ['union', 'evolution (earliest Lv8 first)', 'upgrade highest-level weapon'], 'slot': 'kept',
                           'jeomji_owner': 'design/05-stats-passives.md 10 (single source); 04 requests unowned-weapon dilution x min(1, 6/unlocked_weapon_count)'},
        'union_rule': {'requires': ['both evolutions owned', 'open box'], 'slot': 'returns 1 slot', 'mode_switch': 'per hit: target pullil -> white(x stat_puri), else red(crit allowed)'},
    },
    'geori_grid': [{'id': g[0], 'jangdan': g[2], 'bpm': g[3], 'span': g[4], 'grid_beat_fraction': g[5], 'grid_sec': round(60.0 / g[3] * g[5], 4)} for g in GEORI],
    'weapons': [],
    'evolutions': [],
    'unions': [],
}
for w in WEAPONS:
    L = levels(w)
    lv = []
    for i, s in enumerate(L):
        b, c = w['model'](s)
        d = clean(s)
        d.update({'lv': i + 1, 'change': '기본' if i == 0 else w['deltas'][i - 1][0], 'est_dps_boss': round(b, 1), 'est_dps_crowd': round(c, 1)})
        lv.append(d)
    out['weapons'].append({
        'id': w['id'], 'loc_key': w['id'] + '.name', 'name_ko': w['name'], 'hanja': w['hanja'], 'color': w['color'], 'origin': w['origin'], 'scope': w['scope'],
        'archetype': w['archetype'], 'tags': w['tags'], 'targeting': w['targeting'], 'pair_passive': w['pair'], 'evolution': w['evo'],
        'max_level': 8, 'limits': clean(w['limits']), 'amount_rule': w['amount_rule'], 'ritual_ref_by_level': [RITUAL_REF[i] for i in range(1, 9)] if w['color'] == 'white' else None,
        'levels': lv,
    })
for e in EVOS:
    b, c = e['model'](e['stats'])
    out['evolutions'].append({'id': e['id'], 'loc_key': e['id'] + '.name', 'name_ko': e['name'], 'hanja': e['hanja'], 'color': e['color'], 'scope': e['scope'],
                              'recipe': {'weapon': e['base'], 'weapon_level': 8, 'passive': e['passive'], 'passive_min_level': 1, 'box': ['box_gilhyung', 'box_neokham']},
                              'stats': clean(e['stats']), 'summary': e['summary'], 'ritual_ref': RITUAL_REF['evo'] if e['color'] == 'white' else None,
                              'est_dps_boss': round(b, 1), 'est_dps_crowd': round(c, 1)})
for u in UNIONS:
    b, c = u['model'](u['stats'])
    out['unions'].append({'id': u['id'], 'loc_key': u['id'] + '.name', 'name_ko': u['name'], 'scope': u['scope'], 'color': 'dual',
                          'recipe': {'evolutions': u['parts'], 'box': ['box_gilhyung', 'box_neokham']}, 'stats': clean(u['stats']), 'summary': u['summary'],
                          'ritual_ref': RITUAL_REF['union'], 'est_dps_boss': round(b, 1), 'est_dps_crowd': round(c, 1)})

os.makedirs(os.path.join(ROOT, 'data'), exist_ok=True)
with open(os.path.join(ROOT, 'data', 'weapons.json'), 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=2)

# ---------------- 문서 렌더 ----------------
import glob
tpl = ''.join(open(f, encoding='utf-8').read() for f in sorted(glob.glob(os.path.join(HERE, 'doc_t*.md'))))
import re
missing = []
def sub(m):
    key = m.group(1)
    if key not in FR:
        missing.append(key)
        return m.group(0)
    return FR[key]
doc = re.sub(r'\{\{([A-Z_]+(?::[a-z_]+)?)\}\}', sub, tpl)
with open(os.path.join(ROOT, 'design', '04-weapons-evolution.md'), 'w', encoding='utf-8') as f:
    f.write(doc)
print('missing', missing)
print('unused', sorted(set(FR) - set(re.findall(r'\{\{([A-Z_]+(?::[a-z_]+)?)\}\}', tpl))))
