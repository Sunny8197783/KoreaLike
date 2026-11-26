# -*- coding: utf-8 -*-
"""04 리뷰 대응: 점지(05 10장) + 상자(04 6.2) 몬테카를로로 진화 타이밍·빌드 분포·기준 DPS를 낸다.

사용: python -I buildsim.py            (요약 출력)
      gen.py가 import해서 문서 표(EVO_TIMING, BUILD_SIM, DPS_REF, HEADROOM, RUPTURE_LEVER)와 JSON을 만든다.

가정(모두 [가정], 09 봇 시뮬레이션이 대체):
- 레벨 곡선: 02 `req(L)` 혼합 런 앵커 (00:00 L1, 00:12 L2, 03:00 L7, 05:00 L10, 10:00 L22, 15:00 L34, 20:00 L48) 선형 보간.
- 빙의 점지: 시련 5회(03·06·09·12·15분, +0.75분에 해결 가정) 직후 1회씩. 18:00 합일 = 강신 6.
- 점지: 05 10장(범주 2단 추첨, 10.3 범주 가중, 10.4 항목 가중, G1~G3 보장). 점괘 100(4번째 칸 없음), 리롤·물림·금기 없음.
- 미보유 무구 희석 보정: 항목 가중 × min(1, 6 / 해금 무구 수)  (04가 05 10.4에 요청하는 값)
- 상자: data/waves_stage1.json 정예 14 + 중간보스 1(최소 3개). 해결 +0.4분(중간보스 +0.8분). 원귀 상자 제외.
- 상자 등급(05 12.1, 점괘 100): 1개 76% / 3개 20% / 5개 4%.
- 상자 내용(04 6.2 개정): 칸마다 결합 → 진화(둘 합쳐 상자당 1건) → 최고 레벨 무구 +1 → 최고 레벨 패시브 +1.
- 선택 정책 '집중 강화': 최고 레벨 무구 강화 > 짝 패시브(무구 Lv6+) > 신규 무구(4개까지) > 패시브 > 권능.
- 무당: 만신(신칼 00:00, 방울 00:30 지급).
"""
import sys, os, random, math, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wdata
from analyze import levels

W = {w['id']: w for w in wdata.WEAPONS}
E = {e['id']: e for e in wdata.EVOS}
U = {u['id']: u for u in wdata.UNIONS}
EVO_OF = {w['id']: w['evo'] for w in wdata.WEAPONS}
PAIR = {w['id']: w['pair'] for w in wdata.WEAPONS}
PASSIVES = sorted(set(PAIR.values()))
LV = {w['id']: levels(w) for w in wdata.WEAPONS}

LEVEL_ANCHORS = [(0.0, 1), (0.2, 2), (3.0, 7), (5.0, 10), (10.0, 22), (15.0, 34), (20.0, 48)]
TRIALS = [3.0, 6.0, 9.0, 12.0, 15.0]
TRIAL_RESOLVE = 0.75
HAPIL = 18.0
BOX_GRADE = [(1, 0.76), (3, 0.20), (5, 0.04)]
ELITE_SLOTS = [(405, 1), (450, 1), (500, 1), (690, 1), (690, 1), (810, 1), (810, 1), (885, 1), (960, 2), (990, 2), (1050, 2)]
MBOSS_T = 10.0
SNAP = [3, 6, 9, 12, 15, 20]
SINPPAL_REF = {0: 1.0, 5: 1.1, 10: 1.3, 15: 1.6, 20: 1.9}
RHO_T = {3: 0.10, 5: 0.15, 10: 0.30, 15: 0.40, 20: 0.50}
UNLOCK_BASE = ['wpn_sinkal', 'wpn_woldo', 'wpn_gakgung', 'wpn_bangul', 'wpn_buchae', 'wpn_neokjeon']
UNLOCK_ALL = [w['id'] for w in wdata.WEAPONS]


def interp(table, t):
    ks = sorted(table)
    if t <= ks[0]:
        return table[ks[0]]
    for a, b in zip(ks, ks[1:]):
        if a <= t <= b:
            return table[a] + (table[b] - table[a]) * (t - a) / (b - a)
    return table[ks[-1]]


def level_up_times():
    out = []
    for L in range(2, 49):
        for (t0, l0), (t1, l1) in zip(LEVEL_ANCHORS, LEVEL_ANCHORS[1:]):
            if l0 < L <= l1:
                out.append(t0 + (t1 - t0) * (L - l0) / (l1 - l0))
                break
    return out


def box_events():
    ev = []
    for sec, n in ELITE_SLOTS:
        for _ in range(n):
            ev.append((sec / 60.0 + 0.4, 'elite'))
    ev.append((MBOSS_T + 0.8, 'mboss'))
    return sorted(ev)


class Run:
    def __init__(s, rng, unlocked, policy, dilution, box_upgrade=True):
        s.rng = rng; s.unlocked = unlocked; s.policy = policy; s.dilution = dilution; s.box_upgrade = box_upgrade
        s.wpn = {}          # id -> level (1..8) ; evolved -> 'evo' ; union parts removed
        s.evo = []          # evolution ids owned (not consumed by union)
        s.unions = []
        s.psv = {}          # passive -> level
        s.pwr = {}          # (deity, k) -> level
        s.rank = 0
        s.recent_deity = None; s.recent_left = 0; s.g1_left = 0
        s.g2_counter = 0
        s.level = 1
        s.first_lv8 = None; s.evo_times = []; s.union_times = []
        s.picks = {'weapon': 0, 'passive': 0, 'power': 0}
        s.snap = {}

    # ---- slots ----
    def wslots_used(s):
        return len(s.wpn) + len(s.evo) + len(s.unions)

    def wcolor(s, wid):
        return W[wid]['color']

    # ---- candidate pool (05 10.2) ----
    def pool(s):
        P = {'weapon': [], 'passive': [], 'power': []}
        for wid, lv in s.wpn.items():
            if lv < 8:
                P['weapon'].append(('w_up', wid))
        if s.wslots_used() < 6:
            for wid in s.unlocked:
                if wid not in s.wpn and EVO_OF[wid] not in s.evo and not s.consumed(wid):
                    P['weapon'].append(('w_new', wid))
        for p, lv in s.psv.items():
            if lv < 5:
                P['passive'].append(('p_up', p))
        if len(s.psv) < 6:
            for p in PASSIVES:
                if p not in s.psv:
                    P['passive'].append(('p_new', p))
        for d in range(s.rank):
            for k in range(4):
                if s.pwr.get((d, k), 0) < 3:
                    P['power'].append(('d', (d, k)))
        return P

    def consumed(s, wid):
        e = EVO_OF[wid]
        return any(e in U[u]['parts'] for u in s.unions)

    def item_w(s, it):
        kind, x = it
        if kind == 'w_up':
            return 130.0
        if kind == 'w_new':
            w = 100.0 * (min(1.0, 6.0 / len(s.unlocked)) if s.dilution else 1.0)
            if PAIR[x] in s.psv:
                w *= 1.3
            return w
        if kind == 'p_up':
            return 130.0
        if kind == 'p_new':
            w = 100.0
            for wid, lv in s.wpn.items():
                if PAIR[wid] == x:
                    w *= 2.5 if lv == 8 else 1.5
                    break
            return w
        d, k = x
        w = 100.0 * (1.3 if (d, k) in s.pwr else 1.0)
        if s.recent_left > 0 and d == s.recent_deity:
            w *= 1.5
        return w

    def cat_w(s, P):
        empty_w = 6 - s.wslots_used(); empty_p = 6 - len(s.psv)
        cw = {'weapon': 40.0 * (1.25 if s.level <= 10 and empty_w >= 2 else 1.0),
              'passive': 30.0 * (1.1 if s.level <= 10 and empty_p >= 4 else 1.0),
              'power': (15.0 + 5.0 * s.rank) if s.rank > 0 else 0.0}
        return {c: (cw[c] if P[c] else 0.0) for c in cw}

    def wpick(s, items, weights):
        tot = sum(weights)
        r = s.rng.random() * tot
        for it, w in zip(items, weights):
            r -= w
            if r <= 0:
                return it
        return items[-1]

    def cards(s):
        P = s.pool()
        slots = []
        def take(cat, filt):
            c = [it for it in P[cat] if filt(it)]
            if not c:
                return False
            it = s.wpick(c, [s.item_w(i) for i in c])
            slots.append((cat, it)); P[cat].remove(it)
            return True
        g = 0
        if s.g1_left > 0 and g < 2:
            if take('power', lambda it: it[1][0] == s.recent_deity):
                g += 1
            s.g1_left -= 1
        lv8_nopair = [wid for wid, lv in s.wpn.items() if lv == 8 and PAIR[wid] not in s.psv]
        if lv8_nopair and len(s.psv) < 6 and g < 2:
            s.g2_counter += 1
            if s.g2_counter >= 3:
                if take('passive', lambda it: it[0] == 'p_new' and it[1] == PAIR[lv8_nopair[0]]):
                    g += 1
        if s.level <= 6 and s.wslots_used() < 6 and g < 2:
            if take('weapon', lambda it: it[0] == 'w_new'):
                g += 1
        while len(slots) < 3:
            cw = s.cat_w(P)
            cats = [c for c in cw if cw[c] > 0]
            if not cats:
                break
            cat = s.wpick(cats, [cw[c] for c in cats])
            it = s.wpick(P[cat], [s.item_w(i) for i in P[cat]])
            slots.append((cat, it)); P[cat].remove(it)
        if any(c == 'passive' and it == ('p_new', PAIR[w]) for c, it in slots for w in lv8_nopair):
            s.g2_counter = 0
        return slots

    def score(s, cat, it):
        kind, x = it
        pol = s.policy
        if kind == 'w_up':
            return 100 + 8 * s.wpn[x]
        if kind == 'w_new':
            n = s.wslots_used()
            sc = 85 if n < 4 else 70
            col = W[x]['color']
            reds = sum(1 for w in s.wpn if W[w]['color'] == 'red') + sum(1 for e in s.evo if E[e]['color'] == 'red')
            whites = sum(1 for w in s.wpn if W[w]['color'] == 'white') + sum(1 for e in s.evo if E[e]['color'] == 'white')
            if pol == 'red':
                sc += 20 if col == 'red' else -25
            else:
                sc += 15 if (col == 'red' and reds <= whites) or (col == 'white' and whites < reds) else 0
            return sc
        if kind == 'p_new':
            for wid, lv in s.wpn.items():
                if PAIR[wid] == x:
                    return 160 if lv >= 6 else (80 if lv >= 3 else 55)
            return 35
        if kind == 'p_up':
            return 45
        return 52 if it[1] in s.pwr else 50

    def apply(s, cat, it):
        kind, x = it
        s.picks[cat] += 1
        if kind == 'w_up':
            s.wpn[x] += 1
            if s.wpn[x] == 8 and s.first_lv8 is None:
                s.first_lv8 = s.t
        elif kind == 'w_new':
            s.wpn[x] = 1
        elif kind == 'p_up':
            s.psv[x] += 1
        elif kind == 'p_new':
            s.psv[x] = 1
        else:
            s.pwr[x] = s.pwr.get(x, 0) + 1

    def jeomji(s):
        c = s.cards()
        if not c:
            return
        best = max(c, key=lambda ci: (s.score(*ci), s.rng.random()))
        s.apply(*best)
        if s.recent_left > 0:
            s.recent_left -= 1

    def box(s, kind):
        n = 3 if kind == 'mboss' else 1
        if kind != 'mboss':
            r = s.rng.random(); acc = 0
            for k, p in BOX_GRADE:
                acc += p
                if r <= acc:
                    n = k; break
        else:
            n = 5 if s.rng.random() < 0.04 else 3
        transformed = False
        for _ in range(n):
            if not transformed:
                done = False
                for uid, u in U.items():
                    if uid not in s.unions and all(p in s.evo for p in u['parts']):
                        for p in u['parts']:
                            s.evo.remove(p)
                        s.unions.append(uid); s.union_times.append(s.t)
                        done = True; break
                if not done:
                    cand = [wid for wid, lv in s.wpn.items() if lv == 8 and PAIR[wid] in s.psv]
                    if cand:
                        wid = cand[0]
                        del s.wpn[wid]; s.evo.append(EVO_OF[wid]); s.evo_times.append(s.t)
                        done = True
                if done:
                    transformed = True
                    continue
            if not s.box_upgrade:
                continue
            up = [wid for wid, lv in s.wpn.items() if lv < 8]
            if up:
                wid = max(up, key=lambda w: (s.wpn[w], s.rng.random()))
                s.wpn[wid] += 1
                if s.wpn[wid] == 8 and s.first_lv8 is None:
                    s.first_lv8 = s.t
                continue
            pu = [p for p, lv in s.psv.items() if lv < 5]
            if pu:
                p = max(pu, key=lambda p: (s.psv[p], s.rng.random()))
                s.psv[p] += 1

    def dps(s, t):
        sp = interp(SINPPAL_REF, t)
        wdata.RHO = interp(RHO_T, t)
        b_red = b_white = b_union = c_red = c_white = 0.0
        for wid, lv in s.wpn.items():
            b, c = W[wid]['model'](LV[wid][lv - 1])
            if W[wid]['color'] == 'red':
                b_red += b; c_red += c
            else:
                b_white += b; c_white += c
        for e in s.evo:
            b, c = E[e]['model'](E[e]['stats'])
            if E[e]['color'] == 'red':
                b_red += b; c_red += c
            else:
                b_white += b; c_white += c
        for u in s.unions:
            b, c = U[u]['model'](U[u]['stats'])
            b_union += b; c_red += c * 0.5; c_white += c * 0.5
        wdata.RHO = 0.30
        return {'single': sp * (b_red + b_white + b_union),
                'wieom': sp * (b_red + 0.4 * b_white + 0.7 * b_union),
                'crowd_red': sp * c_red, 'crowd_white': sp * c_white,
                'n_wpn': s.wslots_used(), 'n_psv': len(s.psv),
                'wpn_levels': sum(s.wpn.values()) + 8 * (len(s.evo) + 2 * len(s.unions)),
                'n_evo': len(s.evo_times), 'pwr_picks': s.picks['power']}

    def run(s):
        events = [(t, 'lvl') for t in level_up_times()]
        events += [(t + TRIAL_RESOLVE, 'trial') for t in TRIALS]
        events += [(HAPIL, 'hapil')]
        events += [(t, 'box_' + k) for t, k in box_events()]
        events += [(0.5, 'white_start')]
        events += [(float(x), 'snap') for x in SNAP]
        events.sort(key=lambda e: (e[0], e[1] != 'snap'))
        s.wpn['wpn_sinkal'] = 1
        for t, k in events:
            s.t = t
            if k == 'lvl':
                s.level += 1; s.jeomji()
            elif k == 'white_start':
                s.wpn['wpn_bangul'] = 1
            elif k == 'trial':
                s.rank += 1; s.recent_deity = s.rank - 1; s.recent_left = 3; s.g1_left = 2
                s.jeomji()            # 빙의 점지
            elif k == 'hapil':
                s.rank = 6
            elif k.startswith('box_'):
                s.box(k[4:])
            elif k == 'snap':
                s.snap[int(t)] = s.dps(t)
        return s


def simulate(unlocked, policy, dilution, n=1000, seed=4, box_upgrade=True):
    rng = random.Random(seed)
    return [Run(rng, unlocked, policy, dilution, box_upgrade).run() for _ in range(n)]


def q(a, p):
    a = sorted(a)
    if not a:
        return float('nan')
    i = (len(a) - 1) * p
    lo = int(math.floor(i)); hi = int(math.ceil(i))
    return a[lo] + (a[hi] - a[lo]) * (i - lo)


def mmss(x):
    if x is None or x != x:
        return '—'
    m = int(x); s_ = int(round((x - m) * 60))
    if s_ == 60:
        m += 1; s_ = 0
    return '%02d:%02d' % (m, s_)


def summarize(runs):
    INF = 99.0
    first8 = [r.first_lv8 if r.first_lv8 is not None else INF for r in runs]
    ev = lambda i: [r.evo_times[i] if len(r.evo_times) > i else INF for r in runs]
    n_evo = [len(r.evo_times) for r in runs]
    n_union = [len(r.unions) for r in runs]
    tot = sum(sum(r.picks.values()) for r in runs)
    out = {
        'first_lv8': (q(first8, .25), q(first8, .5), q(first8, .75)),
        'evo1': (q(ev(0), .25), q(ev(0), .5), q(ev(0), .75)),
        'evo2': (q(ev(1), .25), q(ev(1), .5), q(ev(1), .75)),
        'evo3': (q(ev(2), .25), q(ev(2), .5), q(ev(2), .75)),
        'evo4': (q(ev(3), .25), q(ev(3), .5), q(ev(3), .75)),
        'evo5': (q(ev(4), .25), q(ev(4), .5), q(ev(4), .75)),
        'evo6': (q(ev(5), .25), q(ev(5), .5), q(ev(5), .75)),
        'union1': (q([r.union_times[0] if r.union_times else INF for r in runs], .25), q([r.union_times[0] if r.union_times else INF for r in runs], .5), q([r.union_times[0] if r.union_times else INF for r in runs], .75)),
        'n_evo': (q(n_evo, .25), q(n_evo, .5), q(n_evo, .75)),
        'evo_ge5': sum(1 for x in n_evo if x >= 5) / len(runs),
        'union_rate': sum(1 for x in n_union if x >= 1) / len(runs),
        'pick_share': {k: sum(r.picks[k] for r in runs) / tot for k in ('weapon', 'passive', 'power')},
        'snap': {},
    }
    for t in SNAP:
        d = [r.snap[t] for r in runs]
        out['snap'][t] = {k: q([x[k] for x in d], .5) for k in d[0]}
    return out


PROFILES = [
    ('mix_base6', '혼합 · 기본 해금 6종', UNLOCK_BASE, 'mix', True),
    ('mix_all20', '혼합 · 해금 20종 · 희석 보정', UNLOCK_ALL, 'mix', True),
    ('mix_all20_nodil', '혼합 · 해금 20종 · 보정 없음', UNLOCK_ALL, 'mix', False),
    ('red_all20', '적 위주 · 해금 20종 · 희석 보정', UNLOCK_ALL, 'red', True),
    ('mix_all20_nobox', '(비교) 혼합 · 해금 20종 · 상자 강화 없음', UNLOCK_ALL, 'mix', True, False),
]


def run_all(n=1000):
    return {p[0]: (p[1], summarize(simulate(p[2], p[3], p[4], n=n, box_upgrade=(p[5] if len(p) > 5 else True)))) for p in PROFILES}


if __name__ == '__main__':
    R = run_all(int(sys.argv[1]) if len(sys.argv) > 1 else 400)
    for pid, (label, S) in R.items():
        print('==', label)
        for k in ('first_lv8', 'evo1', 'evo2', 'evo3', 'evo4', 'evo5', 'evo6', 'union1'):
            print('  %-9s p25 %s  med %s  p75 %s' % (k, *(mmss(x) for x in S[k])))
        print('  n_evo p25/med/p75', S['n_evo'], 'ge5 %.2f union %.2f' % (S['evo_ge5'], S['union_rate']))
        print('  picks', {k: round(v, 2) for k, v in S['pick_share'].items()})
        for t, d in S['snap'].items():
            print('  t=%2d single %6.0f wieom %6.0f crowdR %6.0f crowdW %6.0f wpn %.0f psv %.0f lvls %.0f evo %.0f pwr %.0f' % (
                t, d['single'], d['wieom'], d['crowd_red'], d['crowd_white'], d['n_wpn'], d['n_psv'], d['wpn_levels'], d['n_evo'], d['pwr_picks']))
