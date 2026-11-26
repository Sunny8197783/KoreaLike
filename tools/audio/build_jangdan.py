"""build_jangdan.py — 장단 루프 합성기 (KoreaLike / 넋길: 해원굿).

data/audio_jangdan.json 의 속도 단계(tier)마다 박 구조·BPM 그대로 장단을 배열해 레이어별 루프 OGG 를 만든다.

  python -I tools/audio/build_jangdan.py                 # 전 tier, 흥 0단계
  python -I tools/audio/build_jangdan.py --heung 0 1 2   # 흥 1·2단계(×1.04, ×1.08) 렌더 추가
  python -I tools/audio/build_jangdan.py --only jd_jajinmori

출력: game/assets/music/<jd_id>_<layer>.ogg   layer = janggu|buk|jing|kkwaenggwari|jegeum|melody|bed|mix
      (흥 단계 h>0 은 <jd_id>_<layer>_h<h>.ogg)
      game/assets/music/music_index.json   (BPM·박·루프 길이·레이어 표 — 런타임 박 동기화용)

레이어 ↔ data/audio_music_layers.json:
  janggu=L00(장구 기준 박, 상시)  buk=L02(대북, 산신)  jing=L03(징, 용왕)  kkwaenggwari=L04(꽹과리, 칠성)
  jegeum=L07(제금, 제석·대감)  melody=L05 태평소 메김(1·2각)+L06 피리 받음(3·4각) — 보스·명부 tier 는 아쟁(적 팔레트)
  bed=L01(저역 지속음, 기준음 D)  mix=프로토타입용 단일 스트림(위 레이어 합)

루프 경계: 모든 레이어를 '원형 버퍼'로 렌더한다. 루프 끝을 넘는 징 여운·잔향·굴림 꼬리는 버퍼 앞쪽으로 접어 더하므로
루프 지점에 무음 구간도, 잘린 꼬리로 인한 클릭도 없다. 박 0(덩)은 정확히 샘플 0에 놓인다.

장단 패턴(1문자 = 1소박, 2분박 장단은 1문자 = 반박) — 기호와 장구 구음(문헌 표기 관습):
  D = 덩  (합장단: 궁편+채편 동시)            K = 쿵  (궁편/북편 단독)
  T = 덕  (채편 단독, 민요·풍물 악보의 '따')    g = 기덕 (채편 앞꾸밈 '기' + 본음 '덕', 한 소박 안)
  R = 더러러러 (채편 굴림, 다음 타점까지)       . = 쉼
  * audio_jangdan.json proto_patterns 는 '게임 펄스' 프로토타입이며 실제 장단 전사본이 아니다(verified=false).
    굿거리 행만 교육용 구음 "덩 기덕 쿵 더러러러 / 쿵 기덕 쿵 더러러러" 의 단순화(verified=partial).
    데이터에 없는 살풀이·엇모리·휘모리 패턴은 아래 EXTRA_PATTERNS 에 같은 규칙(첫 소박 = 덩)으로 보충했다.
    국악 자문 전사본이 오면 JSON 의 패턴 문자열만 바꾸면 된다.
"""
from __future__ import annotations

import argparse
import json
import zlib
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gugak_dsp as d  # noqa: E402
import gugak_inst as gi  # noqa: E402
from gugak_dsp import SR, db, rng  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data", "audio_jangdan.json")
OUT = os.path.join(ROOT, "game", "assets", "music")

# 데이터에 패턴이 없는 tier 보충(프로토, verified=false). 길이 = beats_per_cycle × subbeats_per_beat.
EXTRA_PATTERNS = {
    # 살풀이 12/8(4대박×3소박): 굿거리 골격을 느리게 — "덩 . 기덕 | 쿵 . 덕 | 쿵 기덕 . | 쿵 덕 ."
    "jd_salpuri": "D.gK.TKg.KT.",
    # 엇모리 10/8 혼소박 3+2+3+2: 묶음 첫 소박에 덩/쿵 — "덩 . 덕 | 쿵 . | 덕 . 덕 | 쿵 ."
    "jd_eotmori": "D.TK.T.TK.",
    # 휘모리 4/4 2분박: 가장 빠른 몰이 — "덩 덕 | 쿵 덕 | 덕 쿵 | 덕 덕"
    "jd_hwimori": "DTKTTKTT",
    # 굿거리: 데이터 jd_gutgeori_reference 사용(아래에서 읽음)
}

def _h(s: str) -> int:
    """프로세스 간 안정적인 해시(재현 가능한 빌드)."""
    return zlib.crc32(s.encode("utf-8"))


# 루프 길이 목표(초) — 정수 장단 수, 4장단 단위 변주가 맞도록 4의 배수 우선.
TARGET_LOOP_S = 32.0

# tier → 선율 악기 구성 (메김, 받음)
MELODY_INST = {
    "jd_jinyang": ("daegeum", "piri"), "jd_jungmori": ("taepyeongso", "piri"),
    "jd_jungjungmori": ("taepyeongso", "piri"), "jd_jajinmori": ("taepyeongso", "piri"),
    "jd_danmori": ("taepyeongso", "piri"), "jd_jinobangjin": ("taepyeongso", "piri"),
    "jd_salpuri": ("ajaeng", "ajaeng"), "jd_eotmori": ("ajaeng_dist", "ajaeng_dist"),
    "jd_hwimori": ("ajaeng", "ajaeng_dist"), "jd_gutgeori": ("daegeum", "daegeum"),
}
NOTES_PER_UNIT = {"jd_jinyang": 3, "jd_jungmori": 4, "jd_jungjungmori": 5, "jd_jajinmori": 6, "jd_danmori": 6,
                  "jd_jinobangjin": 8, "jd_hwimori": 6, "jd_salpuri": 4, "jd_eotmori": 5, "jd_gutgeori": 4}
# 경토리(국사당, 솔=D): D E G A B — 반음 오프셋. 보스·명부는 육자배기토리 단순화 D F G A C.
TORI_GYEONG = [-5, -3, 0, 2, 5, 7, 9, 12, 14]
TORI_YUKJA = [-5, -2, 0, 3, 5, 7, 10, 12, 15]
BOSS_TIERS = {"jd_salpuri", "jd_eotmori", "jd_hwimori"}

# 믹스 내 레이어 상대 레벨(dB) — 12-audio 12.2: 장구는 다른 음악 레이어 대비 +2dB
MIX_DB = {"janggu": 0.0, "buk": -2.5, "jing": -5.0, "kkwaenggwari": -7.0, "jegeum": -9.0, "melody": -4.0, "bed": -9.0}
MIX_TARGET_LUFS = -20.0  # 소스 기준. 음악 버스 -6dB 에서 12.2 전투 음악 -26 LUFS-S 근처


# ------------------------------------------------------------------ 시간 격자
class Grid:
    def __init__(self, tier: dict, mult: float):
        self.tier = tier
        self.id = tier["id"]
        self.bpm = tier["bpm_base"] * mult
        self.beat = 60.0 / self.bpm
        self.spb = tier["subbeats_per_beat"]
        self.bpc = tier["beats_per_cycle"]
        self.sub = self.beat / self.spb
        self.nsub = self.bpc * self.spb
        self.cycle = self.beat * self.bpc
        self.gak = self.cycle / tier["gak_count"]
        # 장단 수는 흥 0단계(기본 BPM) 기준으로 고정 → 흥 1·2 렌더도 같은 장단 수(박 위치 = 재생 비율로 대응)
        base_cycle = 60.0 / tier["bpm_base"] * self.bpc
        self.cycles = max(1, int(round(TARGET_LOOP_S / base_cycle)))
        if self.cycles >= 4:
            self.cycles = int(round(self.cycles / 4.0)) * 4
        self.length = self.cycles * self.cycle
        self.n = int(round(self.length * SR))

    def t(self, cyc: int, sub_i: float) -> float:
        return cyc * self.cycle + sub_i * self.sub


class Loop:
    """원형 렌더 버퍼(스테레오). place 는 루프 끝을 넘으면 앞으로 감는다."""

    def __init__(self, n: int):
        self.n = n
        self.buf = np.zeros((n, 2))

    def place(self, sig: np.ndarray, t: float, gain_db: float = 0.0, pan: float = 0.0):
        s = d.to_stereo(sig, pan) if sig.ndim == 1 else sig
        s = s * db(gain_db)
        i = int(round(t * SR)) % self.n
        k = 0
        while k < len(s):
            take = min(len(s) - k, self.n - i)
            self.buf[i:i + take] += s[k:k + take]
            k += take
            i = 0


_CACHE: dict = {}


def voice(kind: str, vel: float, seed: int, **kw) -> np.ndarray:
    """라운드로빈 8테이크 × 속도 0.1 단위 캐시."""
    vb = round(max(0.05, min(1.0, vel)), 1)
    key = (kind, vb, seed % 8, tuple(sorted(kw.items())))
    if key not in _CACHE:
        s = seed % 8
        if kind == "deong":
            x = gi.janggu_deong(vb, s)
        elif kind == "kung":
            x = gi.janggu_kung(vb, s)
        elif kind == "deok":
            x = gi.janggu_deok(vb, s)
        elif kind == "gi":
            x = gi.janggu_gi(vb, s)
        elif kind == "daebuk":
            x = gi.daebuk(vb, s)
        elif kind == "jing":
            x = gi.jing(vb, s, **kw)
        elif kind.startswith("kkw_"):
            x = gi.kkwaenggwari(kind[4:], vb, s)
        elif kind.startswith("jeg_"):
            x = gi.jegeum(kind[4:], vb, s)
        else:
            raise KeyError(kind)
        _CACHE[key] = x
    return _CACHE[key]


def pattern_of(tier_id: str, data: dict) -> str:
    pp = data["proto_patterns"]
    if tier_id == "jd_gutgeori":
        return pp["jd_gutgeori_reference"]
    return pp.get(tier_id) or EXTRA_PATTERNS[tier_id]


# ------------------------------------------------------------------ 레이어: 장구 (L00)
def layer_janggu(g: Grid, pat: str) -> np.ndarray:
    L = Loop(g.n)
    r = rng(_h(g.id) % 10000)
    fast = g.sub < 0.2
    for c in range(g.cycles):
        fill = (c % 4 == 3)
        p = list(pat)
        if fill:
            # 4장단째 변주(넘김): 마지막 빈 소박들을 기덕/굴림으로 채워 다음 장단 덩으로 몰아 넣는다
            last = len(p) - 1
            if p[last] == ".":
                p[last] = "R" if not fast else "g"
            elif p[last - 1] == ".":
                p[last - 1] = "g"
        for i, ch in enumerate(p):
            if ch == ".":
                continue
            t = g.t(c, i)
            first = (i == 0)
            hum = 0.0 if (i % g.spb == 0) else r.uniform(-0.002, 0.002)  # 박머리는 정확히, 소박만 미세 흔들림
            v = r.uniform(0.92, 1.0)
            seed = c * 97 + i * 13
            if ch == "D":
                L.place(voice("deong", (1.0 if c % 4 == 0 else 0.95) * v if first else 0.85 * v, seed), t)
            elif ch == "K":
                L.place(voice("kung", 0.8 * v, seed), t + hum)
            elif ch == "T":
                L.place(voice("deok", 0.74 * v, seed), t + hum, pan=0.12)
            elif ch == "g":
                L.place(voice("gi", 0.5 * v, seed), t + hum, pan=0.12)
                L.place(voice("deok", 0.7 * v, seed + 1), t + g.sub * 0.5, pan=0.12)
            elif ch == "R":
                # 다음 타점까지(최대 2소박) 굴림
                j = i + 1
                while j < len(p) and p[j] == "." and j - i < 2:
                    j += 1
                length = (j - i) * g.sub * 0.92
                rate = 18.0 if g.sub > 0.25 else 24.0
                L.place(gi.janggu_roll(length, 0.62 * v, seed, rate=rate), t + hum, pan=0.12)
    return L.buf


# ------------------------------------------------------------------ 레이어: 대북 (L02)
def buk_hits(g: Grid) -> list:
    """(cycle 내 소박 위치, 세기) 목록 — 12-audio 4.3 편곡 밀도 가이드."""
    s, b = g.spb, g.bpc
    tid = g.id
    if tid == "jd_jinyang":
        return [(0, 1.0), (6 * s, 0.7), (12 * s, 0.85), (18 * s, 0.7)]
    if tid == "jd_jungmori":
        return [(k * 3 * s, 1.0 if k == 0 else 0.8) for k in range(4)] + [((k * 3 + 2) * s, 0.5) for k in range(4)]
    if tid in ("jd_jungjungmori", "jd_salpuri", "jd_gutgeori"):
        hits = [(k * s, 1.0 if k == 0 else 0.7) for k in range(b)]
        return hits if tid != "jd_gutgeori" else [(0, 0.8), (2 * s, 0.6)]
    if tid == "jd_jajinmori":
        return [(k * s, 1.0 if k == 0 else 0.75) for k in range(b)] + [(3 * s + 2, 0.5)]
    if tid == "jd_danmori":
        return [(k * s, 1.0 if k == 0 else 0.75) for k in range(b)] + [(1 * s + 1, 0.45), (3 * s + 1, 0.5)]
    if tid == "jd_jinobangjin":
        return [(k * s, 1.0 if k == 0 else 0.8) for k in range(b)] + [(k * s + 1, 0.4) for k in range(b)]
    if tid == "jd_hwimori":
        return [(k * s, 1.0 if k == 0 else 0.7) for k in range(b)]
    if tid == "jd_eotmori":  # 3+2+3+2 묶음 머리
        return [(0, 1.0), (3, 0.7), (5, 0.85), (8, 0.7)]
    return [(0, 1.0)]


def layer_buk(g: Grid) -> np.ndarray:
    L = Loop(g.n)
    r = rng(11 + _h(g.id) % 1000)
    hits = buk_hits(g)
    for c in range(g.cycles):
        for (pos, v) in hits:
            L.place(voice("daebuk", v * r.uniform(0.93, 1.0) * (1.0 if c % 4 == 0 or pos else 0.94), c * 7 + pos),
                    g.t(c, pos), pan=-0.08)
        if c % 4 == 3 and g.sub > 0.12:  # 넘김: 다음 장단 덩 직전 한 타
            L.place(voice("daebuk", 0.55, c), g.t(c, g.nsub - 1), pan=-0.08)
    return L.buf


# ------------------------------------------------------------------ 레이어: 징 (L03)
def layer_jing(g: Grid) -> np.ndarray:
    L = Loop(g.n)
    if g.cycle > 10:
        times = [g.t(c, k * (g.nsub // g.tier["gak_count"])) for c in range(g.cycles) for k in range(g.tier["gak_count"])]
        every = 1
    else:
        every = 2 if g.cycle < 2.4 else 1
        times = [g.t(c, 0) for c in range(0, g.cycles, every)]
    dur = min(7.0, max(2.5, g.cycle * every * 1.8))
    for k, t in enumerate(times):
        v = 1.0 if k % 4 == 0 else 0.86
        L.place(voice("jing", v, k, dur=round(dur, 1)), t, pan=-0.2)
    return L.buf


# ------------------------------------------------------------------ 레이어: 꽹과리 (L04)
def layer_kkwaenggwari(g: Grid, pat: str) -> np.ndarray:
    L = Loop(g.n)
    r = rng(23 + _h(g.id) % 1000)
    dense = g.id in ("jd_jajinmori", "jd_danmori", "jd_jinobangjin", "jd_hwimori", "jd_eotmori", "jd_jungjungmori")
    sparse = g.id in ("jd_jinyang", "jd_gutgeori", "jd_salpuri")
    gak_sub = g.nsub // g.tier["gak_count"]
    for c in range(g.cycles):
        for i, ch in enumerate(pat):
            t = g.t(c, i)
            seed = c * 31 + i
            if sparse:
                if i % gak_sub == 0:
                    L.place(voice("kkw_gaeng" if i == 0 else "kkw_gaen", 0.85 if i == 0 else 0.6, seed), t, pan=0.3)
                elif ch in "TgR" and g.id != "jd_jinyang":
                    L.place(voice("kkw_ji", 0.5, seed), t, pan=0.3)
                continue
            if ch == "D":
                L.place(voice("kkw_gaeng", 0.95 if i == 0 else 0.8, seed), t, pan=0.3)
            elif ch == "T":
                L.place(voice("kkw_gaen", 0.7, seed), t, pan=0.3)
            elif ch == "K":
                L.place(voice("kkw_ji", 0.6, seed), t, pan=0.3)
            elif ch == "g":
                L.place(voice("kkw_ji", 0.45, seed), t, pan=0.3)
                L.place(voice("kkw_gaen", 0.65, seed + 1), t + g.sub * 0.5, pan=0.3)
            elif ch == "R":
                for k in range(3):
                    L.place(voice("kkw_ji", 0.5 - 0.08 * k, seed + k), t + k * g.sub / 3, pan=0.3)
            elif ch == "." and dense:
                L.place(voice("kkw_ji", 0.4 * r.uniform(0.85, 1.0), seed), t + r.uniform(-0.002, 0.002), pan=0.3)
    return L.buf


# ------------------------------------------------------------------ 레이어: 제금 (L07)
def layer_jegeum(g: Grid) -> np.ndarray:
    L = Loop(g.n)
    gak_sub = g.nsub // g.tier["gak_count"]
    for c in range(g.cycles):
        if g.cycle >= 3.0:
            for k in range(g.tier["gak_count"]):
                kind = "jeg_chak" if k == 0 else ("jeg_mak" if k % 2 else "jeg_chak")
                L.place(voice(kind, 0.9 if k == 0 else 0.6, c * 4 + k), g.t(c, k * gak_sub), pan=0.25)
        else:
            L.place(voice("jeg_chak" if c % 2 == 0 else "jeg_mak", 0.85 if c % 2 == 0 else 0.6, c), g.t(c, 0), pan=0.25)
            if c % 2 == 1:
                L.place(voice("jeg_mak", 0.45, c + 50), g.t(c, g.nsub // 2), pan=0.25)
        if c % 4 == 3:  # 넘김 쉬머: 다음 장단 첫박으로 문지름 상승
            sh = voice("jeg_shimmer", 0.6, c)
            L.place(sh, g.t(c + 1, 0) - len(sh) / SR * 0.55, pan=0.25)
    return L.buf


# ------------------------------------------------------------------ 레이어: 선율 (L05 메김 + L06 받음 / 보스는 아쟁)
def _ajaeng(notes, total, seed, dist=False):
    """아쟁(저음 찰현, 적 팔레트) 근사: 해금 합성을 한 옥타브 내리고 어둡게, 살형은 드라이브."""
    lowered = [(t0, du, st - 12, v, o) for (t0, du, st, v, o) in notes]
    x = gi.haegeum(lowered, total, seed)
    x = d.lowpass(d.peq(x, 500, 5, 1.0), 2400, 2)
    if dist:
        x = d.saturate(x * 2.5, 8.0) * 0.6
        x = d.lowpass(x, 3500, 2)
    return x


def _play(inst, notes, total, seed):
    if inst in ("piri", "taepyeongso"):
        return gi.reed(notes, total, inst, seed)
    if inst == "daegeum":
        return gi.daegeum(notes, total, seed)
    if inst == "ajaeng":
        return _ajaeng(notes, total, seed)
    if inst == "ajaeng_dist":
        return _ajaeng(notes, total, seed, dist=True)
    raise KeyError(inst)


def layer_melody(g: Grid) -> np.ndarray:
    r = rng(5150 + _h(g.id) % 1000)
    scale = TORI_YUKJA if g.id in BOSS_TIERS else TORI_GYEONG
    if g.gak >= 1.0:
        unit = g.gak * max(1, int(round(2.0 / g.gak)))
    else:
        unit = g.cycle * max(1, int(round(2.0 / g.cycle)))
    nunits = int(round(g.length / unit))
    unit_subs = int(round(unit / g.sub))
    npu = NOTES_PER_UNIT[g.id]
    meok, bat = MELODY_INST[g.id]
    # 리듬 2종(메김 A, 받음 B)을 만들고 반복 — 빠른 장단은 리프처럼 되풀이된다
    def rhythm():
        cand = list(range(1, unit_subs))
        k = min(npu - 1, len(cand))
        on = sorted(r.choice(cand, size=k, replace=False).tolist())
        start = 0 if r.random() < 0.7 else 1  # 30%는 한 소박 늦게 들어가는 엇붙임
        return sorted(set([start] + [o for o in on if o > start]))
    RA, RB = rhythm(), rhythm()
    parts = {meok: [], bat: []}
    idx = 2  # D4 에서 시작
    for u in range(nunits):
        call = (u % 4) in (0, 1)
        inst = meok if call else bat
        on = RA if call else RB
        t_unit = u * unit
        phrase_end = (u % 4) in (1, 3)
        for j, o in enumerate(on):
            nxt = on[j + 1] if j + 1 < len(on) else unit_subs
            du = (nxt - o) * g.sub
            last = (j == len(on) - 1)
            if last and phrase_end:
                du *= 0.78  # 숨 자리
                target = 2 if (u % 4) == 3 else 5  # 받음은 으뜸음 D, 메김 끝은 A(5도)로 열어 둔다
                idx = target
            else:
                step = r.choice([-2, -1, -1, 0, 1, 1, 2], p=[0.08, 0.27, 0.15, 0.1, 0.2, 0.12, 0.08])
                idx = int(np.clip(idx + step, 0, len(scale) - 1))
            st = scale[idx]
            orn = ""
            if du > 0.55:
                orn = "nong"
            if j > 0 and r.random() < 0.25 and du > 0.25:
                orn = "kkeok"
            if last and phrase_end and r.random() < 0.5:
                orn = "toe"
            v = (0.95 if j == 0 else 0.8) * r.uniform(0.9, 1.0)
            parts[inst].append((t_unit + o * g.sub, du * 0.97, st, v, orn))
    L = Loop(g.n)
    total = g.length + 2.0
    for k, (inst, notes) in enumerate(parts.items()):
        if not notes:
            continue
        x = _play(inst, notes, total, k)
        x = x / (np.abs(x).max() + 1e-9)
        pan = -0.15 if k == 0 else 0.15
        L.place(x, 0.0, 0.0 if inst != "taepyeongso" else -3.0, pan=pan)  # 태평소 -3dB 트림(layers 표)
    return L.buf


# ------------------------------------------------------------------ 레이어: 베드 (L01)
def layer_bed(g: Grid) -> np.ndarray:
    if g.id in BOSS_TIERS:
        x = gi.drone(g.length, (-12, -11, 0), seed=3, bright=420.0)  # 단2도 부딪힘(살 쪽 무게)
    elif g.id == "jd_gutgeori":
        x = gi.drone(g.length, (-12, 0, 7), seed=4, bright=500.0)
    else:
        x = gi.drone(g.length, (-12, -5, 0), seed=5, bright=650.0)
    x = d.pad_to(x, g.n)
    L = Loop(g.n)
    L.place(d.to_stereo(x), 0.0)
    return L.buf


# ------------------------------------------------------------------ 공간·마감
SPACE = {"janggu": (-17, 1.2), "buk": (-15, 1.6), "jing": (-12, 2.6), "kkwaenggwari": (-16, 1.1),
         "jegeum": (-14, 1.5), "melody": (-11, 2.0), "bed": (-14, 3.0)}


def finish(layer: str, buf: np.ndarray, n: int) -> np.ndarray:
    wet, rt = SPACE[layer]
    y = d.circular_reverb(buf, wet, rt, 6000, seed=_h(layer) % 100)
    y = d.highpass(y, 28 if layer in ("buk", "bed") else 45, 2)
    if layer in ("janggu", "buk"):  # 테이프 새추레이션 병렬 2~4dB(6.2)
        sat = d.saturate(y * db(3), 3.0) * db(-3)
        y = y * 0.7 + sat * 0.3
    return y[:n]


def render_tier(tier: dict, data: dict, heung: int, layers: list) -> dict:
    mult = data["heung"]["tiers"][heung]["mult"] if heung < len(tier["bpm_heung"]) else None
    if mult is None:
        return {}
    g = Grid(tier, mult)
    pat = pattern_of(tier["id"], data)
    assert len(pat) == g.nsub, (tier["id"], len(pat), g.nsub)
    bufs = {}
    builders = {"janggu": lambda: layer_janggu(g, pat), "buk": lambda: layer_buk(g), "jing": lambda: layer_jing(g),
                "kkwaenggwari": lambda: layer_kkwaenggwari(g, pat), "jegeum": lambda: layer_jegeum(g),
                "melody": lambda: layer_melody(g), "bed": lambda: layer_bed(g)}
    for ly in layers:
        raw = builders[ly]()
        y = finish(ly, raw, g.n)
        # 레이어 내부 기준: 피크 정규화 후 믹스 상대 레벨 적용
        y = y / (np.abs(y).max() + 1e-9) * db(MIX_DB[ly])
        bufs[ly] = y
    mix = sum(bufs.values())
    gain = db(MIX_TARGET_LUFS - d.loudness(mix))
    peak = np.abs(mix).max() * gain
    if peak > db(-1.0):
        gain *= db(-1.0) / peak  # 리미터 없이 전체 게인으로 피크 -1dBFS 확보(스템 합 = 믹스 유지)
    suffix = "" if heung == 0 else f"_h{heung}"
    files = {}
    for ly, y in list(bufs.items()) + [("mix", mix)]:
        path = os.path.join(OUT, f"{tier['id']}_{ly}{suffix}.ogg")
        d.save(path, y * gain, quality=4.0 if ly != "bed" else 3.0)
        files[ly] = os.path.relpath(path, os.path.join(ROOT, "game")).replace("\\", "/")
    return {"id": tier["id"], "name_ko": tier["name_ko"], "heung": heung, "bpm": round(g.bpm, 3),
            "beat_unit": tier["beat_unit"], "beats_per_cycle": g.bpc, "subbeats_per_beat": g.spb,
            "cycle_s": round(g.cycle, 6), "cycles": g.cycles, "loop_s": round(g.n / SR, 6), "loop_samples": g.n,
            "sample_rate": SR, "pattern": pat, "files": files,
            "mix_loudness_lufs": round(d.loudness(mix * gain), 2),
            "godot": {"loop": True, "bpm": round(g.bpm, 3), "beat_count": g.cycles * g.bpc, "bar_beats": g.bpc}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--heung", type=int, nargs="*", default=[0])
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--layers", nargs="*", default=["janggu", "buk", "jing", "kkwaenggwari", "jegeum", "melody", "bed"])
    a = ap.parse_args()
    data = json.load(open(DATA, encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    idx_path = os.path.join(OUT, "music_index.json")
    index = json.load(open(idx_path, encoding="utf-8")) if os.path.exists(idx_path) else {"tiers": {}}
    for tier in data["tiers"]:
        if a.only and tier["id"] not in a.only:
            continue
        for h in a.heung:
            info = render_tier(tier, data, h, a.layers)
            if info:
                index["tiers"][f"{tier['id']}" + ("" if h == 0 else f"_h{h}")] = info
                print(f"{tier['id']:16s} h{h} bpm {info['bpm']:7.2f} loop {info['loop_s']:7.3f}s x{info['cycles']} "
                      f"mix {info['mix_loudness_lufs']} LUFS")
    index["doc"] = ("장단 루프 스템. 같은 tier 의 모든 레이어는 길이·박 0 위치가 같다 — AudioStreamSynchronized 로 묶어 "
                    "재생하고 레이어 볼륨만 조절. loop=true 로 설정(.ogg 임포트 또는 런타임 stream.loop). "
                    "pattern: D=덩 K=쿵 T=덕 g=기덕 R=더러러러 .=쉼 (프로토, verified=false — tools/audio/build_jangdan.py)")
    index["mix_target_lufs"] = MIX_TARGET_LUFS
    index["layer_mix_db"] = MIX_DB
    json.dump(index, open(idx_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
