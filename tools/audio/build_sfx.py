"""build_sfx.py — v1 주요 SFX 제작기 (KoreaLike / 넋길: 해원굿).

CC0/CC-BY 원샷(art/audio/src, prepare_samples.py 결과)을 피치·레이어·엔벨로프로 가공하고
국악 타악·무구 합성 음원(gugak_inst)과 겹쳐 data/audio_sfx.json 의 v1 핵심 SFX 를 만든다.

  python -I tools/audio/build_sfx.py            # 전부
  python -I tools/audio/build_sfx.py sfx_sys_hanpa sfx_ui_nav

출력: game/assets/sfx/<sfx_id>.ogg  (+ 변주/집계 티어 <sfx_id>__<variant>.ogg)
      game/assets/sfx/sfx_index.json  (id → 파일·클래스·LUFS·피크·루프 여부·사용 샘플)

설계 규칙(design/12-audio.md):
  - 11.6 소스 레벨: L1 핵심 피드백 -16 LUFS-S / L2 무구 -20 / L3 적 -24 / L4 배경 -30 / UI -22, 피크 -1(-3/-6)
  - 타격음은 짧고 단단하게: 0~5ms 안에 최대 진폭(첫 프레임이 가장 강함), 꼬리 짧게(물량 400 에서도 뭉개지지 않게)
  - 11.2 히트 집계 티어(1 / 2-5 / 6-20 / 21+): __agg2/__agg3/__agg4 = '여러 개를 동시에 친' 군집 테이크.
    티어 게인 {0,+2,+4,+6}dB 는 런타임이 더한다(파일은 같은 라우드니스로 정규화).
  - 11.1 해원 사다리: sfx_sys_haewon(옥타브0, D5 방울) / __oct1(D6). 런타임 pitch_scale = 2^(semis/12).
  - 예약 악기 준수(6.1): 징=용왕, 대북=산신, 꽹과리=칠성, 태평소=장군, 해금·피리=바리, 제금=제석·대감.
    공용 SFX 에는 장구·소리북·방울·놋그릇·한지·무명천만 쓴다(시련·빙의 스팅어는 예외 허용).
"""
from __future__ import annotations

import json
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gugak_dsp as d  # noqa: E402
import gugak_inst as gi  # noqa: E402
from gugak_dsp import SR, db, n_of, rng, semis  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "sfx")
D4 = gi.D4
D5, D6 = D4 * 2, D4 * 4
TORI = [0, 2, 5, 7, 9]  # 경토리(국사당) 반음 오프셋
LADDER = [TORI[i % 5] + 12 * (i // 5) for i in range(10)]

CLASS = {  # (목표 LUFS-S, 피크 dBFS)
    "L1": (-16.0, -1.0), "L2": (-20.0, -1.0), "L3": (-24.0, -3.0), "L4": (-30.0, -6.0), "UI": (-22.0, -3.0),
    "RIT": (-19.0, -1.0), "STG": (-17.0, -1.0), "AMB": (-34.0, -6.0),
}

USED: dict = {}  # sfx_id → 사용 샘플 키(크레딧 추적)


def S(key: str, i: int = 0, start: float = 0.0, dur: float | None = None, use: list | None = None) -> np.ndarray:
    """샘플 뱅크에서 i번째 테이크 [start, start+dur) 구간."""
    x = gi.pick(key, i)
    if use is not None:
        use.append(key)
    a = n_of(start) if start else 0
    x = x[a:]
    if dur is not None:
        x = d.pad_to(x, n_of(dur))
    return x


def env_hit(n: int, decay: float, attack: float = 0.0004) -> np.ndarray:
    return d.env_exp(n, decay, attack)


def hard_front(x: np.ndarray, ms: float = 4.0) -> np.ndarray:
    """첫 프레임 강조: 앞 ms 구간을 +3dB 올리고 이후 자연 감쇠(트랜지언트 셰이퍼)."""
    n = len(x)
    t = d.t_axis(n)
    g = 1 + (db(3.0) - 1) * np.exp(-t / (ms / 1000))
    return x * (g if x.ndim == 1 else g[:, None])


def bell_tone(freq: float, dur: float = 1.0, vel: float = 1.0, seed: int = 0, jingle: float = 0.35) -> np.ndarray:
    return gi.bangul(freq, vel, seed, dur, jingle)


def sub_drop(dur: float = 0.5, f0: float = 36.7 * 2, ratio: float = 2.2, tau: float = 0.03, decay: float = 0.22) -> np.ndarray:
    n = n_of(dur)
    return d.pitch_drop_sine(dur, f0, ratio, tau) * env_hit(n, decay, 0.001)


def rev_swell(x: np.ndarray, dur: float) -> np.ndarray:
    """역재생 스웰(살·빙의 앞부분)."""
    y = d.reverb(x, -4, 2.0)
    y = d.mono(y)[::-1]
    return d.fade(d.pad_to(y[-n_of(dur):], n_of(dur)), 0.05, 0.01)


def noise_sweep(dur: float, f0: float, f1: float, bw: float = 0.6, seed: int = 0, shape: str = "swell") -> np.ndarray:
    """대역 노이즈 스윕(바람·휘익). 블록별 대역통과로 시간가변 필터 근사."""
    r = rng(seed)
    n = n_of(dur)
    x = r.standard_normal(n)
    blocks = 24
    out = np.zeros(n)
    win = np.hanning(2 * (n // blocks) + 2)
    hop = n // blocks
    for b in range(blocks + 1):
        u = b / blocks
        fc = f0 * (f1 / f0) ** u
        a = max(0, b * hop - hop)
        seg = x[a: a + 2 * hop + 2]
        if len(seg) < 8:
            continue
        y = d.bandpass(seg, fc * (1 - bw / 2), fc * (1 + bw / 2), 2)
        out[a: a + len(y)] += y * win[: len(y)]
    t = d.t_axis(n) / dur
    if shape == "swell":
        e = np.sin(np.pi * np.clip(t, 0, 1)) ** 1.5
    elif shape == "rise":
        e = np.clip(t, 0, 1) ** 2 * np.clip((1 - t) / 0.06, 0, 1)
    elif shape == "fall":
        e = (1 - t) ** 2 * np.clip(t / 0.03, 0, 1)
    else:
        e = np.ones(n)
    return out * e


def agg(make, copies: int, window: float = 0.04, seed: int = 0, spread_st: float = 0.8) -> np.ndarray:
    """히트 집계 군집 테이크: copies 개를 window 안에 흩뿌리고 피치를 ±spread 로 퍼뜨린다(첫 타가 가장 강함)."""
    r = rng(seed)
    parts = []
    for k in range(copies):
        x = make(k)
        x = d.resample(x, semis(r.uniform(-spread_st, spread_st)))
        off = 0.0 if k == 0 else r.uniform(0.002, window)
        gdb = 0.0 if k == 0 else -r.uniform(2, 7)
        parts.append((x, off, gdb))
    y = d.mix(*parts)
    return y


def finish(x: np.ndarray, cls: str, tail_fade: float = 0.01, trim: bool = True) -> np.ndarray:
    x = d.dc_block(x)
    if trim:
        x = d.trim_silence(x, -62, 0.005)
    x = d.fade(x, 0.0, tail_fade)
    tgt, pk = CLASS[cls]
    return d.normalize_lufs(x, tgt, pk)


def loopify(x: np.ndarray, length: float, xf: float = 1.5) -> np.ndarray:
    """앰비언스 루프: 끝 xf 초를 앞부분과 등전력 크로스페이드 → 경계 무절단."""
    n, k = n_of(length), n_of(xf)
    x = d.pad_to(x, n + k)
    body = x[:n].copy()
    w = np.sin(np.linspace(0, np.pi / 2, k))
    head = body[:k]
    tail = x[n:n + k]
    if x.ndim == 1:
        body[:k] = head * w + tail * np.cos(np.linspace(0, np.pi / 2, k))
    else:
        body[:k] = head * w[:, None] + tail * np.cos(np.linspace(0, np.pi / 2, k))[:, None]
    return body


# =================================================================== 레시피
R: dict = {}  # id → (함수, 클래스, 설명)


def sfx(sid: str, cls: str, note: str = "", loop: bool = False):
    def deco(fn):
        R[sid] = (fn, cls, note, loop)
        return fn
    return deco


# ---------------------------------------------------------------- 붉은 타격(퇴치) / 결단타
def _hanpa_one(k: int, use) -> np.ndarray:
    r = rng(100 + k)
    n = n_of(0.34)
    tak = d.bandpass(d.noise(0.34, r), 700, 5200, 2) * env_hit(n, 0.022) * 1.6
    smack = d.pad_to(d.highpass(S("smack_body", k % 6, use=use), 250, 2), n) * env_hit(n, 0.05)
    tear = d.pad_to(d.highpass(S("paper_tear_a", k % 8, dur=0.2, use=use), 1600, 2), n)
    tear = d.fade(tear, 0.002, 0.08) * env_hit(n, 0.07)
    punch = d.pad_to(sub_drop(0.2, 68, 2.0, 0.012, 0.06), n)
    x = d.mix((tak + smack * 0.9, 0.0, 0.0), (tear, 0.012, -5.0), (punch, 0.0, -1.0))
    return hard_front(x, 3)


@sfx("sfx_sys_hanpa", "L1", "붉은 파열: 비음정 '탁' + 종이 찢김 + 저역 펀치. __agg2~4 = 집계 티어")
def hanpa(use):
    return {"": _hanpa_one(0, use), "__v2": _hanpa_one(1, use), "__v3": _hanpa_one(2, use),
            "__agg2": agg(lambda k: _hanpa_one(k + 3, use), 3, 0.035, 1),
            "__agg3": agg(lambda k: _hanpa_one(k + 6, use), 7, 0.04, 2),
            "__agg4": d.mix((agg(lambda k: _hanpa_one(k + 9, use), 12, 0.04, 3), 0, 0),
                            (sub_drop(0.45, 55, 2.4, 0.02, 0.16), 0, -2))}


@sfx("sfx_sys_gyeoldanta", "L1", "결단타: 칼날 '싹' + 금속 여운 0.25s (한 파열보다 고역 +4dB)")
def gyeoldanta(use):
    out = {}
    for v in range(3):
        r = rng(200 + v)
        sw = d.highpass(S("whoosh_sword", v * 2, dur=0.16, use=use), 2500, 3)
        sw = d.fade(sw, 0.0, 0.05) * env_hit(len(sw), 0.06)
        ssak = d.bandpass(d.noise(0.12, r), 4000, 12000, 2) * env_hit(n_of(0.12), 0.03) * 1.4
        ring = d.modal(0.5, [(2350, 1, 0.22), (3790, .6, .16), (5120, .4, .12), (6610, .25, .08)], r) * 0.35
        x = d.mix((ssak, 0, 0), (sw, 0, -2), (ring, 0.004, -4), (_hanpa_one(20 + v, use) * 0.5, 0, -6))
        out["" if v == 0 else f"__v{v + 1}"] = d.shelf(hard_front(x, 3), 3500, 4.0)
    return out


# ---------------------------------------------------------------- 플레이어
@sfx("sfx_plr_hit", "L1", "피격: 둔탁한 천 타격 + 짧은 숨")
def plr_hit(use):
    out = {}
    for v in range(2):
        n = n_of(0.4)
        cloth = d.lowpass(d.pad_to(S("cloth_flap", v, dur=0.25, use=use), n), 2500, 2) * env_hit(n, 0.06)
        thud = d.pad_to(sub_drop(0.3, 90, 1.8, 0.01, 0.07), n)
        sm = d.pad_to(d.lowpass(S("smacks", v + 2, use=use), 3000, 2), n) * env_hit(n, 0.05)
        br = d.fade(d.bandpass(S("breath_deep", v, dur=0.28, use=use), 300, 3000, 2), 0.01, 0.12)
        x = d.mix((cloth, 0, 0), (thud, 0, 0), (sm, 0, -3), (br, 0.03, -6))
        out["" if v == 0 else "__v2"] = hard_front(x)
    return out


@sfx("sfx_plr_hit_blocked", "L1", "호신부 방어: 종이-금속 '챙' + 소멸 꼬리 0.4s")
def plr_blocked(use):
    r = rng(301)
    pap = d.highpass(S("paper_flap", 1, dur=0.15, use=use), 1500, 2)
    chaeng = d.modal(0.7, [(1880, 1, .3), (2950, .7, .22), (4410, .5, .15), (6020, .3, .1)], r) * 0.5
    tail = d.bandpass(d.noise(0.5, r), 3000, 9000, 2) * d.env_ar(n_of(0.5), 0.02, 0.45)
    return {"": hard_front(d.mix((pap, 0, -2), (chaeng, 0, 0), (tail, 0.05, -14)))}


@sfx("sfx_plr_dodge", "L2", "접신 회피: 공기 휘익 + 옅은 방울 1음")
def plr_dodge(use):
    w = noise_sweep(0.25, 900, 3500, 0.7, 7, "swell")
    b = bell_tone(D6 * semis(7), 0.6, 0.4, 3, 0.2)
    return {"": d.mix((w, 0, 0), (b, 0.08, -10))}


@sfx("sfx_plr_death", "L1", "쓰러짐: 무복 천 + 방울 떨어져 3회 튐")
def plr_death(use):
    cloth = d.lowpass(S("cloth_flap", 2, dur=0.6, use=use), 3000, 2)
    thud = sub_drop(0.5, 70, 1.6, 0.02, 0.15)
    parts = [(cloth, 0, 0), (thud, 0.05, -2)]
    t, v = 0.32, 0.9
    for k, gap in enumerate([0.34, 0.21, 0.12]):
        parts.append((bell_tone(D6 * semis(-0.3 * k), 0.8, v, 40 + k, 0.6), t, 0.0))
        t += gap
        v *= 0.62
    parts.append((d.fade(gi.bangul_shake(0.5, 0.25, 5), 0.05, 0.3), t, -8))
    return {"": d.reverb(d.mix(*parts), -16, 1.4)}


@sfx("sfx_plr_levelup_ready", "RIT", "점지 직전(레벨업): 바람 들이쉬는 0.3s 스웰 + 끝 방울")
def levelup(use):
    br = d.bandpass(S("breath_woman", 0, dur=1.2, use=use), 500, 6000, 2)
    br = rev_swell(br, 0.32)
    rise = noise_sweep(0.32, 600, 5000, 0.5, 9, "rise")
    shim = d.mix(*[(bell_tone(D6 * semis(st), 0.5, 0.35, 60 + i, 0.1), 0.18 + i * 0.035, -6)
                   for i, st in enumerate([0, 5, 9])])
    ding = bell_tone(D6 * semis(12), 1.2, 1.0, 66, 0.3)
    return {"": d.reverb(d.mix((br, 0, 0), (rise, 0, -4), (shim, 0, -6), (ding, 0.32, -2)), -14, 1.6)}


# ---------------------------------------------------------------- 해원·풀릴 기색·행렬
@sfx("sfx_sys_pullil_enter", "RIT", "풀릴 기색: 낮은 숨 내쉼 + 방울 장식음 1개(치음 A)")
def pullil(use):
    out = {}
    for v in range(2):
        br = d.lowpass(d.fade(S("breath_deep", 2 + v, dur=0.5, use=use), 0.02, 0.2), 1800, 2)
        b = bell_tone(D5 * semis(7), 0.8, 0.5, 70 + v, 0.15)
        out["" if v == 0 else "__v2"] = d.mix((br, 0, -4), (b, 0.06, 0))
    return out


@sfx("sfx_sys_haewon", "L1", "해원 '딸랑': 놋쇠 방울 단타 D5(옥타브0) / __oct1 D6. 런타임 토리 사다리 pitch_scale")
def haewon(use):
    out = {}
    for v in range(3):
        b = bell_tone(D5, 1.3, 1.0, 80 + v, 0.45)
        sh = gi.mureong(d.highpass(S("sleigh_bells", v, use=use), 3000, 2), 0.2) * env_hit(n_of(0.2), 0.05)
        x = d.reverb(hard_front(d.mix((b, 0, 0), (sh, 0, -9))), -18, 1.2)
        out["" if v == 0 else f"__v{v + 1}"] = x
    out["__oct1"] = d.reverb(hard_front(bell_tone(D6, 1.1, 1.0, 90, 0.35)), -18, 1.2)
    return out


@sfx("sfx_sys_haewon_elite", "L1", "정예 해원: 방울 군 하강 아르페지오 + 숨 한 호흡 + 해금 하모닉 1.2s")
def haewon_elite(use):
    parts = []
    for k, i in enumerate(range(9, -1, -1)):
        parts.append((bell_tone(D5 * semis(LADDER[i]), 1.0, 0.9 - 0.04 * k, 100 + k, 0.2), k * 0.075, 0))
    br = d.fade(d.bandpass(S("breath_woman", 1, dur=1.2, use=use), 300, 5000, 2), 0.1, 0.4)
    hg = gi.haegeum([(0.15, 1.05, 24 + 0, 0.5, "nong")], 1.3, 3)
    hg = d.highpass(hg, 900, 2)
    x = d.mix(*parts, (br, 0.0, -10), (hg, 0, -12))
    return {"": d.reverb(x, -12, 2.2)}


@sfx("sfx_sys_yeongga_join", "RIT", "영가 합류: 작은 종종걸음 3보 + 종이 사락")
def yeongga_join(use):
    out = {}
    for v in range(2):
        steps = []
        for k in range(3):
            st = d.lowpass(S("paper_fold", k + v * 3, dur=0.08, use=use), 3500, 2) * env_hit(n_of(0.08), 0.02)
            tap = d.lowpass(d.noise(0.05, rng(k)), 900, 2) * env_hit(n_of(0.05), 0.008)
            steps.append((d.mix(st, tap), k * 0.085 + 0.004 * k * k, -2 * k))
        sarak = d.fade(d.highpass(S("paper_rustle", 3 + v, dur=0.3, use=use), 1500, 2), 0.03, 0.15)
        out["" if v == 0 else "__v2"] = d.mix(*steps, (sarak, 0.2, -5))
    return out


@sfx("sfx_sys_yeongga_substitute", "RIT", "대신 맞기: 넋전 종이 흩날림 + 놋그릇 '웅'(징 아님)")
def substitute(use):
    pap = d.fade(d.highpass(S("paper_flap", 3, dur=0.6, use=use), 1200, 2), 0.0, 0.3)
    bowl = gi.nokgeureut(1.0, 0, 1.8, pitch=0.8)
    use.append("korean_bell")
    return {"": d.mix((pap, 0, -2), (bowl, 0.01, 0))}


@sfx("sfx_sys_cheondo", "RIT", "천도: 상승하는 바람 + 고음 방울 트레몰로 0.6s")
def cheondo(use):
    wind = noise_sweep(0.8, 500, 3200, 0.6, 11, "rise")
    trem = d.mix(*[(bell_tone(D6 * semis(LADDER[(k % 5)]), 0.4, 0.5 + 0.04 * k, 120 + k, 0.1), 0.05 + k * 0.05, 0)
                   for k in range(12)])
    return {"": d.reverb(d.mix((wind, 0, -3), (trem, 0, -5)), -14, 1.8)}


def _gildakkeum(size: int, use) -> np.ndarray:
    deong = gi.janggu_deong(1.0, size)
    sub = sub_drop(0.9 + 0.3 * size, 36.7 * 2, 2.5, 0.025, 0.25 + 0.12 * size)
    petals = noise_sweep(0.9 + 0.4 * size, 1200, 6500, 0.5, 30 + size, "swell")
    pap = d.highpass(S("paper_flap", 4 + size, dur=0.8, use=use), 2000, 2)
    pap = d.fade(pap, 0.05, 0.4)
    casc = d.mix(*[(bell_tone(D6 * semis(LADDER[i]), 0.6, 0.45, 140 + i, 0.05), 0.12 + 0.06 * k, -2)
                   for k, i in enumerate(range(0, 5 + 2 * size))])
    x = d.mix((hard_front(deong), 0, 0), (sub, 0, -1), (petals, 0.08, -12), (pap, 0.06, -10), (casc, 0, -12 + 2 * size))
    return d.reverb(x, -13, 1.8 + 0.4 * size)


@sfx("sfx_sys_gildakkeum", "L1", "길닦음 '덩'(고리 닫힘): 장구 덩 + 서브 D + 넋전 꽃잎 상승. __m/__l = 고리 면적 중·대")
def gildakkeum(use):
    use.append("drum_hits_low")
    use.append("drum_sticks")
    return {"": _gildakkeum(0, use), "__m": _gildakkeum(1, use), "__l": _gildakkeum(2, use)}


@sfx("sfx_sys_gilbe_close_ready", "RIT", "닫힘 가능 큐: 0.18s 상승 쉬머 → 한국 손종 '팅'(A7, 짧은 감쇠)")
def close_ready(use):
    n = n_of(0.2)
    f = np.linspace(D6, D6 * semis(7), n)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * d.env_ar(n, 0.03, 0.1)
    sh = noise_sweep(0.2, 3000, 7000, 0.4, 12, "rise")
    ting = d.resample(S("korean_bell", 1, use=use), (D6 * semis(7) * 2) / 3074.0)   # 손종 주공명 3.07kHz → A7(3.52kHz) 맑은 팅
    ting = d.shelf(clip_len_s(ting, 0.6, 0.25), 6000, -4.0, True) * env_hit(n_of(0.6), 0.22)
    return {"": d.reverb(d.mix((tone, 0, -6), (sh, 0, -12), (hard_front(ting), 0.16, 0)), -16, 1.0)}


def clip_len_s(x: np.ndarray, sec: float, fout: float) -> np.ndarray:
    return d.fade(d.pad_to(x, n_of(sec)), 0, fout)


def _wongwi(level: int, use) -> np.ndarray:
    sand = d.mix(*[(d.highpass(S("bamboo_maraca", k, use=use), 2000, 2), k * 0.11, -3) for k in range(8)])
    sand = rev_swell(sand, 1.6)
    boom = sub_drop(1.2, 40, 2.0, 0.04, 0.35 + 0.15 * level)
    rbowl = rev_swell(gi.nokgeureut(0.8, 1, 2.0, 0.7), 1.0)
    use.append("korean_bell")
    hit = gi.soribuk(1.0, level)
    x = d.mix((sand, 0, -6), (rbowl, 0.6, -8), (boom, 1.6, -2 + 2 * level), (hit, 1.6, -4))
    return d.reverb(x, -12, 2.4)


@sfx("sfx_sys_wongwi_rise", "RIT", "원귀 회귀: 역재생 모래 상승 → 결집 충격. 기본=25%, __50/__75 저역 강화")
def wongwi(use):
    return {"": _wongwi(0, use), "__50": _wongwi(1, use), "__75": _wongwi(2, use)}


@sfx("sfx_sys_sinmyeong_full", "RIT", "신명 만충: 장구 굴림 1박 → 덩 (추임새 '얼쑤' VO 미포함 — 보이스 녹음 필요)")
def sinmyeong_full(use):
    roll = gi.janggu_roll(0.48, 0.75, 9, 22)
    return {"": d.reverb(d.mix((roll, 0, 0), (gi.janggu_deong(1.0, 3), 0.5, 0)), -16, 1.4)}


@sfx("sfx_sys_oreum_start", "RIT", "신명 오름 시작: 장구 겹채 몰이 0.5s → 다음 박 강타")
def oreum_start(use):
    parts = []
    t = 0.0
    k = 0
    while t < 0.5:
        gap = 0.085 * (1 - 0.55 * t / 0.5)
        parts.append(((gi.janggu_deok(0.5 + 0.5 * t / 0.5, k, True) if k % 2 == 0 else gi.janggu_kung(0.4 + 0.5 * t, k)), t, 0))
        t += gap
        k += 1
    parts.append((hard_front(gi.janggu_deong(1.0, 5)), 0.5, 2))
    parts.append((sub_drop(0.6, 36.7 * 2, 2.5, 0.02, 0.2), 0.5, -2))
    return {"": d.reverb(d.mix(*parts), -15, 1.5)}


@sfx("sfx_sys_oreum_end", "RIT", "신명 오름 종료: 하행 바람 + 장구 마지막 덩(약)")
def oreum_end(use):
    w = noise_sweep(1.0, 3000, 400, 0.6, 13, "fall")
    return {"": d.reverb(d.mix((w, 0, -4), (gi.janggu_deong(0.55, 6), 0.55, 0)), -14, 1.6)}


@sfx("sfx_sys_eoduk_heart", "RIT", "어둑시니 정적 심장: 64BPM 루프(4박), 모노", loop=True)
def eoduk_heart(use):
    beat = 60 / 64
    L = d.n_of(beat * 4)
    buf = np.zeros(L + n_of(1.0))
    hb = [S("heartbeat60", k, dur=0.5, use=use) for k in range(2)]
    for k in range(4):
        h = d.lowpass(hb[k % 2], 220, 3) * (1.0 if k % 2 == 0 else 0.85)
        h = d.mix((h, 0, 0), (sub_drop(0.3, 48, 1.4, 0.01, 0.08), 0, -6))
        i = n_of(k * beat)
        buf[i:i + len(h)] += h
    out = d.fold(buf, L)
    return {"": out}


@sfx("sfx_sys_deungbul", "RIT", "굿판 등불 점화: 촛불 '훅' + 풍경 1음")
def deungbul(use):
    hook = d.fade(S("candle_light", 0, dur=0.6, use=use), 0.0, 0.3)
    pg = gi.pungyeong(None, 0.8, 0, 2.5)
    use.append("chime_single_02")
    return {"": d.mix((hook, 0, -2), (pg, 0.12, -4))}


# ---------------------------------------------------------------- 시련
@sfx("sfx_trl_omen", "RIT", "시련 예고: 먼 바람 + 신장대 방울이 멀리서")
def trl_omen(use):
    wind = d.fade(d.lowpass(S("wind_night_a", 0, start=3.0, dur=3.0, use=use), 1500, 2), 0.6, 1.2)
    bells = d.lowpass(gi.bangul_shake(1.4, 0.7, 3), 5000, 2)
    use.append("sleigh_bells")
    return {"": d.reverb(d.mix((wind, 0, -6), (bells, 0.7, -6)), -6, 3.0)}


@sfx("sfx_trl_sinjangdae", "RIT", "신장대 강림(시련 시작): 대나무 '탁' 꽂힘 + 오색 천 펄럭 + 방울")
def trl_sinjangdae(use):
    tak = d.pad_to(d.highpass(S("bamboo_hit", 0, use=use), 150, 2), n_of(0.5)) * env_hit(n_of(0.5), 0.12)
    st = gi.soribuk(0.9, 2, "tak")
    use.append("wood_blocks")
    cl = d.fade(S("cloth_flap", 3, dur=0.6, use=use), 0.02, 0.3)
    bl = gi.bangul_shake(0.5, 0.6, 7)
    x = d.mix((hard_front(tak), 0, 0), (st, 0, -4), (sub_drop(0.4, 60, 2, 0.01, 0.1), 0, -4), (cl, 0.06, -8), (bl, 0.02, -10))
    return {"": d.reverb(x, -14, 1.6)}


@sfx("sfx_trl_circle_enter", "RIT", "화신 원 진입: 경계 통과 '쉬잉'")
def trl_circle(use):
    w = noise_sweep(0.35, 1500, 6000, 0.35, 14, "swell")
    r = rng(15)
    ring = d.modal(0.4, [(D6 * semis(7), .4, .2), (D6 * semis(19), .2, .12)], r)
    return {"": d.mix((w, 0, 0), (ring, 0.12, -10))}


@sfx("sfx_trl_confirm_ring", "RIT", "확인 링 1s: 토리 5음 상행")
def trl_confirm(use):
    parts = [(bell_tone(D5 * semis(LADDER[i + 2]), 0.6, 0.55 + 0.08 * i, 150 + i, 0.1), i * 0.2, 0) for i in range(5)]
    hum = d.lowpass(gi.drone(1.0, (0, 7), 1, 500), 600, 2) * d.env_ar(n_of(1.0), 0.6, 0.1)
    return {"": d.reverb(d.mix(*parts, (hum, 0, -18)), -15, 1.4)}


@sfx("sfx_trl_wieom_step", "RIT", "위엄 게이지 10%: 소리북 틱(대북 아님). 런타임 토리 사다리 피치")
def trl_wieom(use):
    use += ["drum_hits_dry", "wood_blocks"]
    return {"": d.mix((gi.soribuk(0.8, 4), 0, 0), (gi.soribuk(0.6, 4, "tak"), 0, -6))}


@sfx("sfx_trl_gaho_step", "RIT", "가호 게이지 10%: 높은 방울 틱")
def trl_gaho(use):
    return {"": bell_tone(D6, 0.6, 0.8, 170, 0.15)}


@sfx("sfx_trl_timeout_warn", "RIT", "시련 10초 남음: 장구 '기덕' 2회(1s 주기로 런타임 반복)")
def trl_timeout(use):
    parts = []
    for k in range(2):
        parts += [(gi.janggu_gi(0.6, k), k * 0.25, 0), (gi.janggu_deok(0.8, k + 4), k * 0.25 + 0.07, 0)]
    return {"": d.mix(*parts)}


@sfx("sfx_trl_bingui", "STG", "직접 빙의 1.2s(공용판): 0.6s 역재생 스웰 → 강타 → 0.3s 꼬리. 신령별 시그니처는 __<deity>")
def trl_bingui(use):
    swell = rev_swell(d.mix((gi.nokgeureut(1, 0, 3.0), 0, 0), (gi.bangul_shake(0.8, 0.8, 2), 0, -6)), 0.6)
    use += ["korean_bell", "sleigh_bells"]
    base = lambda hit: d.reverb(d.mix((swell, 0, -2), (hard_front(hit), 0.6, 0), (sub_drop(0.6, 36.7 * 2, 2.4, .02, .2), 0.6, -2)), -12, 1.8)  # noqa: E731
    sig = {
        "": gi.janggu_deong(1.0, 1),
        "__sansin": gi.daebuk(1.0, 1),
        "__yongwang": gi.jing(1.0, 1, 2.0),
        "__chilseong": gi.kkwaenggwari("gaeng", 1.0, 1),
        "__janggun": d.mix((gi.reed([(0, 0.55, 12, 1.0, "kkeok")], 0.6, "taepyeongso", 1), 0, 0), (gi.janggu_deong(0.8, 2), 0, -4)),
        "__barigongju": d.mix((gi.haegeum([(0, 0.6, 7, 1.0, "nong")], 0.65, 1), 0, 0), (gi.janggu_deong(0.7, 3), 0, -6)),
        "__jeseok_daegam": gi.jegeum("chak", 1.0, 0),
    }
    use += ["gong_qubodup", "gong_korean_cdrk", "crash_thrashed20", "splash_6"]
    return {k: base(v) for k, v in sig.items()}


@sfx("sfx_trl_hapil", "STG", "신령 합일 HAPIL_CALL(4신 공용판): 단모리 160BPM 4박, 박마다 1신 강타 → 4박째 전원 + 스웰")
def trl_hapil(use):
    beat = 60 / 160
    hits = [gi.daebuk(1, 2), gi.jing(1, 2, 2.5), gi.kkwaenggwari("gaeng", 1, 2), gi.jegeum("chak", 1, 0)]
    parts = [(hard_front(h), k * beat, 0) for k, h in enumerate(hits)]
    parts.append((gi.janggu_deong(1, 4), 3 * beat, 0))
    for h in hits:
        parts.append((h, 3 * beat, -4))
    parts.append((d.mix((gi.janggu_deong(1, 7), 0, 0)), 0, 0))
    choir = gi.drone(2.4, (-12, 0, 7, 12), 8, 1400) * d.env_ar(n_of(2.4), 1.2, 0.8)
    parts.append((choir, 0.0, -12))
    use += ["drum_hits_low", "gong_qubodup", "gong_korean_cdrk", "crash_thrashed20", "splash_6"]
    return {"": d.reverb(d.mix(*parts), -11, 2.4)}


@sfx("sfx_trl_avatar_smile", "RIT", "화신의 미소(시련 성공·종료): 따뜻한 저음 숨 + 바람 잦아듦 + 먼 풍경")
def trl_smile(use):
    br = d.lowpass(d.fade(S("breath_deep", 4, dur=1.2, use=use), 0.15, 0.6), 1500, 2)
    wind = d.fade(d.lowpass(S("wind_night_b", 0, start=2.0, dur=2.5, use=use), 2500, 2), 0.05, 2.0)
    hum = gi.drone(2.5, (-12, -5, 0), 6, 380) * d.env_ar(n_of(2.5), 0.4, 1.6)
    pg = gi.pungyeong(D6 * semis(7), 0.6, 1, 2.0)
    use.append("bell_1ring")
    return {"": d.reverb(d.mix((br, 0, -2), (wind, 0, -6), (hum, 0, -14), (pg, 0.5, -10)), -10, 2.6)}


@sfx("sfx_trl_grm_ring_capture", "RIT", "고리 포획 성공: 길닦음 덩 재사용 + 굿상 놋그릇 울림")
def trl_ring_capture(use):
    use += ["paper_flap", "gong_qubodup"]
    # 굿상 울림 = 짧게 막은 징(저역 -6dB, 시정수 0.35s) — 싱잉볼 대체(2026-11-24 리뷰)
    n = n_of(1.4)
    jing = d.shelf(gi.jing(0.75, 3, 1.4), 220, -6.0, high=False) * np.exp(-d.t_axis(n) / 0.35)
    return {"": d.mix((_gildakkeum(0, use), 0, 0), (d.fade(jing, 0, 0.2), 0.02, -7))}


# ---------------------------------------------------------------- 적·보스 (L3)
@sfx("sfx_enm_proj_generic", "L3", "적 탄(공용): 저역 쉬익 250Hz-1.5kHz")
def enm_proj(use):
    return {"": noise_sweep(0.2, 700, 380, 0.9, 16, "swell"), "__v2": noise_sweep(0.22, 600, 320, 0.9, 17, "swell")}


@sfx("sfx_enm_dalgyal_gwisin", "L3", "달걀귀신 등장: 매끈한 '뽁'")
def dalgyal(use):
    n = n_of(0.12)
    pop = d.pitch_drop_sine(0.12, 330, 1.9, 0.01) * env_hit(n, 0.03)
    click = d.bandpass(d.noise(0.12, rng(18)), 1500, 5000, 2) * env_hit(n, 0.002)
    return {"": pop + click * 0.4}


@sfx("sfx_elite_wongwi", "L3", "원귀(정예) 등장: 종 소리 -5반음 + 붉은 눈 점등 '칙' + 저역")
def elite_wongwi(use):
    bell = d.resample(S("korean_bell", 0, dur=2.5, use=use), semis(-5))
    chik = d.highpass(S("match_light", 0, dur=0.25, use=use), 2500, 2) * env_hit(n_of(0.25), 0.07)
    low = gi.drone(2.0, (-24, -23), 9, 200) * d.env_ar(n_of(2.0), 0.2, 1.5)
    return {"": d.reverb(d.mix((bell, 0, -2), (chik, 0.05, -4), (low, 0, -8)), -10, 2.2)}


@sfx("sfx_boss_knot_untie", "L1", "고 매듭 풀림 '툭': 무명 매듭 풀림 + 저역 (무가 VO 미포함)")
def knot(use):
    tuk = d.lowpass(S("cloth_flap", 4, dur=0.3, use=use), 2200, 2) * env_hit(n_of(0.3), 0.06)
    pl = d.modal(0.5, [(D4 * semis(-5), .6, .2), (D4 * semis(7), .3, .15)], rng(19))
    sl = d.fade(d.highpass(S("paper_fold", 6, dur=0.4, use=use), 1000, 2), 0.02, 0.2)
    return {"": d.reverb(hard_front(d.mix((tuk, 0, 0), (pl, 0, -8), (sl, 0.08, -8), (sub_drop(0.3, 60, 1.5, .01, .1), 0, -4))), -14, 1.8)}


@sfx("stg_mboss_enter", "STG", "보스/중간보스 등장 1장단(자진모리 120BPM, 2.0s): 역재생 놋쇠 → 장구 덩 + 대북 + 저역")
def mboss_enter(use):
    beat = 0.5
    sw = rev_swell(d.mix((gi.nokgeureut(1, 1, 3, 0.6), 0, 0)), 1.0)
    use.append("korean_bell")
    parts = [(sw, 0, -2)]
    for k in range(4):
        parts.append((gi.janggu_deong(1.0 if k in (0, 3) else 0.8, k), 1.0 + k * beat * (2 / 3 if k else 0), 0))
    parts += [(gi.daebuk(1, 5), 1.0, -2), (sub_drop(1.5, 36.7, 2.6, 0.04, 0.6), 1.0, 0),
              (gi.drone(2.0, (-24, -23, -12), 10, 300) * d.env_ar(n_of(2.0), 0.1, 1.2), 1.0, -8)]
    use += ["drum_hits_low", "drum_sticks"]
    return {"": d.reverb(d.mix(*parts), -10, 2.8)}


@sfx("stg_boss_silence", "STG", "20:00 보스 정적: 심장 2박 → 2.0s 소리북 1타(긴 잔향)")
def boss_silence(use):
    hb = [d.lowpass(S("heartbeat60", k, dur=0.5, use=use), 220, 3) for k in range(2)]
    parts = [(hb[0], 0.5, -6), (hb[1], 1.25, -7), (hard_front(gi.soribuk(1.0, 6)), 2.0, 0),
             (sub_drop(1.2, 36.7 * 2, 2.0, .03, .5), 2.0, -3)]
    use += ["drum_hits_dry"]
    return {"": d.reverb(d.mix(*parts), -8, 3.2)}


@sfx("stg_geori_land", "STG", "거리 전환 착지: 장구 덩 + 서브 드롭(신령 악기는 런타임 합류)")
def geori_land(use):
    use += ["drum_hits_low", "drum_sticks"]
    return {"": d.reverb(d.mix((hard_front(gi.janggu_deong(1.0, 2)), 0, 0), (sub_drop(1.5, 36.7 * 2, 2.6, .03, .5), 0, -1)), -13, 2.0)}


@sfx("stg_death", "STG", "사망: 소리북 1타 + 하행 숨(음악 LPF 는 런타임)")
def stg_death(use):
    br = d.lowpass(d.fade(S("breath_woman", 0, dur=2.0, use=use), 0.1, 1.0), 1200, 2)
    br = d.resample(br, semis(-3))
    use.append("drum_hits_dry")
    return {"": d.reverb(d.mix((gi.soribuk(1.0, 8), 0, 0), (br, 0.2, -8), (sub_drop(1.0, 50, 1.6, .03, .4), 0, -6)), -9, 3.0)}


# ---------------------------------------------------------------- 무구 (L2)
def _sinkal_hit(k, use):
    n = n_of(0.16)
    cut = d.highpass(S("paper_tear_b", k % 8, dur=0.12, use=use), 2000, 2) * env_hit(n_of(0.12), 0.03)
    click = d.bandpass(d.noise(0.16, rng(200 + k)), 3000, 11000, 2) * env_hit(n, 0.006) * 1.6
    return hard_front(d.mix((click, 0, 0), (cut, 0.002, -2), (_hanpa_one(30 + k, use) * 0.3, 0, -10)))


@sfx("sfx_wpn_sinkal", "L2", "신칼 던짐: 백지술 펄럭 휘익 / __return 귀환 역방향 / __hit 종이칼 '싹' + __agg2~4")
def wpn_sinkal(use):
    fl = d.fade(d.highpass(S("paper_flap", 5, dur=0.3, use=use), 1500, 2), 0.01, 0.12)
    wh = noise_sweep(0.28, 1400, 4200, 0.6, 21, "swell")
    th = d.mix((wh, 0, 0), (fl, 0, -5))
    return {"": th, "__return": th[::-1].copy(), "__hit": _sinkal_hit(0, use)}


@sfx("sfx_wpn_sinkal_hit", "L2", "신칼 적중 집계 4티어")
def wpn_sinkal_hit(use):
    return {"": _sinkal_hit(1, use), "__agg2": agg(lambda k: _sinkal_hit(k + 2, use), 3, .04, 4),
            "__agg3": agg(lambda k: _sinkal_hit(k + 5, use), 7, .04, 5), "__agg4": agg(lambda k: _sinkal_hit(k + 9, use), 12, .04, 6)}


def _woldo_hit(k, use):
    sm = d.lowpass(S("smack_body", k % 8, use=use), 4000, 2)
    ring = d.modal(0.35, [(620, .5, .12), (1530, .35, .08), (2410, .2, .05)], rng(220 + k))
    return hard_front(d.mix((sm, 0, 0), (ring, 0, -8), (sub_drop(0.25, 75, 1.8, .01, .07), 0, -3)))


@sfx("sfx_wpn_woldo", "L2", "월도 회전: 반달날 '슈우웅' / __hit 묵직한 '척'")
def wpn_woldo(use):
    sw = d.fade(S("whoosh_heavy", 0, dur=0.6, use=use), 0.02, 0.2)
    swirl = noise_sweep(0.6, 500, 1800, 0.5, 22, "swell")
    return {"": d.mix((sw, 0, 0), (swirl, 0, -6)), "__hit": _woldo_hit(0, use)}


@sfx("sfx_wpn_woldo_hit", "L2", "월도 적중 집계 4티어")
def wpn_woldo_hit(use):
    return {"": _woldo_hit(1, use), "__agg2": agg(lambda k: _woldo_hit(k + 2, use), 3, .04, 7),
            "__agg3": agg(lambda k: _woldo_hit(k + 5, use), 7, .04, 8), "__agg4": agg(lambda k: _woldo_hit(k + 9, use), 12, .04, 9)}


@sfx("sfx_wpn_gakgung", "L2", "각궁 발사: 시위 '팅' + 화살 바람 / __hit '퍽'")
def wpn_gakgung(use):
    # 시위: 카플러스-스트롱 근사(감쇠 사인 묶음)
    r = rng(23)
    ting = d.modal(0.35, [(196 * k, 1 / k, 0.18 / (1 + 0.3 * k)) for k in range(1, 12)], r) * 0.5
    air = noise_sweep(0.3, 2500, 1200, 0.6, 24, "fall")
    hit = hard_front(d.mix((d.lowpass(S("smacks", 4, use=use), 2500, 2), 0, 0), (sub_drop(0.2, 90, 1.6, .01, .05), 0, -4)))
    return {"": d.mix((hard_front(ting), 0, 0), (air, 0.01, -6)), "__hit": hit}


def _bangul_hit(k, use):
    b = bell_tone(D6 * semis(LADDER[k % 5]), 0.35, 0.8, 300 + k, 0.4)
    use.append("sleigh_bells")
    return hard_front(b * env_hit(len(b), 0.12))


@sfx("sfx_wpn_bangul", "L2", "방울 박 펄스: 방울 1타(토리 음, 런타임 피치) / __aura 오라 트레몰로 루프")
def wpn_bangul(use):
    pulse = d.reverb(bell_tone(D6, 0.9, 0.9, 310, 0.5), -16, 1.0)
    aura = loopify(d.mix(*[(gi.bangul_shake(0.4, 0.3 + 0.1 * (k % 3), k), k * 0.25, -6) for k in range(20)]), 4.0, 0.5)
    use.append("sleigh_bells")
    return {"": pulse, "__aura": aura}


@sfx("sfx_wpn_bangul_hit", "L2", "방울 적중 집계 4티어")
def wpn_bangul_hit(use):
    return {"": _bangul_hit(0, use), "__agg2": agg(lambda k: _bangul_hit(k + 1, use), 3, .04, 10, 0),
            "__agg3": agg(lambda k: _bangul_hit(k + 4, use), 6, .04, 11, 0), "__agg4": agg(lambda k: _bangul_hit(k + 7, use), 10, .04, 12, 0)}


def _buchae_hit(k, use):
    h = noise_sweep(0.18, 900, 500, 0.8, 330 + k, "fall")
    p = d.lowpass(S("paper_fold", k % 8, dur=0.12, use=use), 4000, 2)
    return d.mix((h, 0, 0), (p, 0, -4))


@sfx("sfx_wpn_buchae", "L2", "부채 부치기: 한지 부채 '촤악' + 바람 / __hit 부드러운 '훅'")
def wpn_buchae(use):
    ch = d.fade(d.highpass(S("paper_flap", 6, dur=0.35, use=use), 800, 2), 0.005, 0.15)
    wind = noise_sweep(0.45, 600, 2400, 0.7, 25, "swell")
    return {"": hard_front(d.mix((ch, 0, 0), (wind, 0.02, -4))), "__hit": _buchae_hit(0, use)}


@sfx("sfx_wpn_buchae_hit", "L2", "부채 적중 집계 4티어")
def wpn_buchae_hit(use):
    return {"": _buchae_hit(1, use), "__agg2": agg(lambda k: _buchae_hit(k + 2, use), 3, .04, 13),
            "__agg3": agg(lambda k: _buchae_hit(k + 5, use), 6, .04, 14), "__agg4": agg(lambda k: _buchae_hit(k + 9, use), 10, .04, 15)}


@sfx("sfx_wpn_jijeon", "L2", "지전 투척: 종이돈 흩날림 '촤르르' / __hit 종이 '팔락'")
def wpn_jijeon(use):
    parts = [(d.highpass(S("paper_rustle", k, dur=0.15, use=use), 1500, 2) * env_hit(n_of(0.15), 0.05), k * 0.035, -k * 0.8)
             for k in range(8)]
    hit = d.highpass(S("paper_flap", 7, dur=0.14, use=use), 1200, 2) * env_hit(n_of(0.14), 0.04)
    return {"": d.mix(*parts), "__hit": hard_front(hit)}


@sfx("sfx_wpn_myeongdu", "L2", "명두 공전: 놋거울 '우웅' 루프 / __ray 빛줄기 쉬머 + 반사 '띵'", loop=False)
def wpn_myeongdu(use):
    hum = gi.drone(4.0, (0, 12, 19), 11, 2500) * 0.6
    hum = loopify(d.bandpass(hum, 250, 3000, 2), 3.0, 0.8)
    ray = d.mix((noise_sweep(0.4, 4000, 9000, 0.3, 26, "swell"), 0, -6), (bell_tone(D6 * semis(12), 0.8, 0.9, 340, 0.0), 0.05, 0))
    return {"__hum": hum, "": ray}


@sfx("sfx_wpn_janggu", "L2", "장구 충격파: 실제 장구 '덩'(무구 그리드 착지, 음악의 일부)")
def wpn_janggu(use):
    use += ["drum_hits_low", "drum_sticks"]
    return {"": d.mix((hard_front(gi.janggu_deong(1.0, 4)), 0, 0), (sub_drop(0.4, 36.7 * 2, 2.2, .02, .12), 0, -6))}


# ---------------------------------------------------------------- 픽업
def _wonhon(size: int) -> np.ndarray:
    f = D5 * semis([0, 7, 12][size])  # 해원보다 한 옥타브 아래 계열(사다리는 런타임)
    r = rng(400 + size)
    tick = d.modal(0.4 + 0.2 * size, [(f, 1, .12 + .06 * size), (f * 2.76, .35, .06), (f * 5.4, .15, .03)], r)
    air = d.bandpass(d.noise(0.08, r), 3000, 9000, 2) * env_hit(n_of(0.08), 0.01)
    return hard_front(d.mix((tick, 0, 0), (air, 0, -10)))


@sfx("sfx_pick_wonhon", "L4", "원혼 구슬 흡수: 소/__m 중/__l 대. 런타임 토리 사다리(해원보다 -8dB, 한 옥타브 아래)")
def pick_wonhon(use):
    return {"": _wonhon(0), "__m": _wonhon(1), "__l": _wonhon(2)}


@sfx("sfx_pick_yeopjeon", "L2", "엽전 획득: 놋엽전 '짤랑' (도깨비 가짜 엽전은 런타임 -1반음)")
def pick_yeopjeon(use):
    out = {}
    for v in range(3):
        c = d.highpass(S("coins", v, dur=0.35, use=use), 1500, 2)
        out["" if v == 0 else f"__v{v + 1}"] = hard_front(d.fade(c, 0, 0.1))
    return out


@sfx("sfx_pick_neok", "L2", "넋 획득: 부드러운 한지 '사락' + 맑은 바람")
def pick_neok(use):
    s = d.fade(d.highpass(S("paper_rustle", 6, dur=0.3, use=use), 1200, 2), 0.02, 0.15)
    return {"": d.mix((s, 0, 0), (noise_sweep(0.4, 2000, 5000, 0.4, 27, "swell"), 0, -10))}


@sfx("sfx_pick_hosinbu", "L2", "호신부 획득: 붉은 부적 종이 '사락' + 작은 방울")
def pick_hosinbu(use):
    s = d.fade(d.highpass(S("paper_fold", 9, dur=0.3, use=use), 900, 2), 0.01, 0.15)
    return {"": d.mix((s, 0, 0), (bell_tone(D6 * semis(5), 0.5, 0.5, 350, 0.1), 0.05, -8))}


# ---------------------------------------------------------------- UI
@sfx("sfx_ui_nav", "UI", "포커스 이동: 한지 넘기는 아주 짧은 '삭'")
def ui_nav(use):
    s = d.highpass(S("paper_rustle", 8, dur=0.07, use=use), 1800, 2) * env_hit(n_of(0.07), 0.02)
    return {"": hard_front(s)}


@sfx("sfx_ui_confirm", "UI", "확인: 장구 '덕'(채편) 단타")
def ui_confirm(use):
    use.append("drum_sticks")
    return {"": gi.janggu_deok(0.85, 5)}


@sfx("sfx_ui_back", "UI", "뒤로: 장구 '쿵'(북편) 약")
def ui_back(use):
    use.append("drum_hits_low")
    return {"": gi.janggu_kung(0.55, 5)}


@sfx("sfx_ui_error", "UI", "불가: 나무 '톡' 2회(낮게)")
def ui_error(use):
    w = d.resample(S("wood_block_b", 0, dur=0.12, use=use), semis(-7))
    w = w * env_hit(len(w), 0.05)
    return {"": d.mix((w, 0, 0), (w, 0.12, -2))}


@sfx("sfx_ui_jeomji_open", "UI", "점지 화면 열림: 한지 두루마리 펼침 + 방울 1음")
def ui_jeomji(use):
    unroll = d.fade(d.highpass(S("paper_fold", 1, dur=0.45, use=use), 600, 2), 0.04, 0.2)
    return {"": d.reverb(d.mix((unroll, 0, 0), (bell_tone(D6, 1.0, 0.8, 360, 0.2), 0.3, -2)), -16, 1.4)}


@sfx("sfx_ui_card_hover", "UI", "점지 카드 포커스: 기본(빙의 전)=장구 / __red 나무 '탁' / __white 방울")
def ui_card_hover(use):
    use += ["drum_sticks", "wood_blocks", "sleigh_bells"]
    return {"": gi.janggu_deok(0.45, 6, True), "__red": gi.soribuk(0.6, 3, "tak"), "__white": bell_tone(D6 * semis(7), 0.5, 0.5, 370, 0.1)}


@sfx("sfx_ui_card_select", "UI", "점지 선택: 붓 한 획 '쓱' + 인장 찍힘 '톡'")
def ui_card_select(use):
    brush = noise_sweep(0.22, 2500, 1500, 0.9, 28, "swell")
    seal = d.lowpass(S("wood_blocks", 2, dur=0.1, use=use), 3000, 2) * env_hit(n_of(0.1), 0.03)
    return {"": d.mix((brush, 0, -2), (hard_front(seal), 0.22, 0), (sub_drop(0.15, 110, 1.5, .005, .04), 0.22, -6))}


@sfx("sfx_ui_reroll", "UI", "다시 묻기(재점): 산가지 흔들기")
def ui_reroll(use):
    parts = [(S("bamboo_maraca", k, dur=0.2, use=use), k * 0.09, -k) for k in range(4)]
    return {"": d.mix(*parts)}


@sfx("sfx_ui_skip", "UI", "물림: 종이 미끄러지는 '스윽'")
def ui_skip(use):
    return {"": d.mix((noise_sweep(0.3, 3000, 1800, 0.8, 29, "swell"), 0, 0),
                      (d.fade(d.highpass(S("paper_fold", 3, dur=0.25, use=use), 1500, 2), 0.05, 0.1), 0.02, -6))}


@sfx("sfx_ui_banish", "UI", "금기: 붉은 인장 '쿵' + 종이 접힘")
def ui_banish(use):
    use.append("drum_hits_dry")
    return {"": d.mix((gi.soribuk(0.8, 9), 0, 0), (d.fade(S("paper_fold", 4, dur=0.3, use=use), 0.01, 0.1), 0.08, -6))}


@sfx("sfx_ui_pause_in", "UI", "일시정지: 바람 잦아듦")
def ui_pause_in(use):
    return {"": noise_sweep(0.7, 1800, 400, 0.7, 31, "fall")}


@sfx("sfx_ui_pause_out", "UI", "재개: 바람 다시 일어남 + 장구 '덕'")
def ui_pause_out(use):
    use.append("drum_sticks")
    return {"": d.mix((noise_sweep(0.5, 400, 1800, 0.7, 32, "rise"), 0, -2), (gi.janggu_deok(0.8, 7), 0.5, 0))}


@sfx("sfx_ui_unlock", "UI", "해금: 방울 상행 3음 + 종이 '팔락'")
def ui_unlock(use):
    parts = [(bell_tone(D6 * semis(st), 0.8, 0.8, 380 + k, 0.2), k * 0.11, 0) for k, st in enumerate([0, 5, 9])]
    parts.append((d.highpass(S("paper_flap", 8, dur=0.15, use=use), 1500, 2), 0.3, -6))
    return {"": d.reverb(d.mix(*parts), -16, 1.4)}


@sfx("sfx_ui_settle_tick", "UI", "정산 카운트: 놋엽전 틱")
def ui_settle_tick(use):
    return {"": hard_front(d.highpass(S("coins", 5, dur=0.08, use=use), 2500, 2) * env_hit(n_of(0.08), 0.02))}


@sfx("sfx_ui_settle_total", "UI", "정산 합계: 장구 덩 + 방울")
def ui_settle_total(use):
    use += ["drum_hits_low", "drum_sticks"]
    return {"": d.reverb(d.mix((gi.janggu_deong(0.9, 6), 0, 0), (bell_tone(D6, 1.0, 0.8, 390, 0.3), 0.02, -4)), -15, 1.5)}


@sfx("sfx_ui_title_start", "UI", "타이틀 시작: 장구 '덩' 한 번 + 촛불 켜짐")
def ui_title(use):
    use += ["drum_hits_low", "drum_sticks"]
    c = d.fade(S("candle_light", 1, dur=1.0, use=use), 0.0, 0.4)
    return {"": d.reverb(d.mix((gi.janggu_deong(1.0, 0), 0, 0), (c, 0.35, -6)), -12, 2.2)}


# ---------------------------------------------------------------- 앰비언스 (루프)
@sfx("amb_guksadang", "AMB", "국사당 밤 산자락 베드 60s 루프: 소나무 바람 + 풀벌레(원샷은 런타임 풀)", loop=True)
def amb_guksadang(use):
    wind = d.lowpass(d.load(os.path.join(gi.SRC, "wind_foliage.flac")), 1200, 2)
    use.append("wind_foliage")
    crk = d.highpass(d.load(os.path.join(gi.SRC, "crickets_pine.flac")), 1500, 2)
    use.append("crickets_pine")
    L = 60.0
    w = loopify(d.pad_to(wind, n_of(62)), L, 2.0)
    c = loopify(d.pad_to(crk, n_of(62)), L, 2.0)
    x = d.mix((d.to_stereo(w, -0.2), 0, 0), (d.to_stereo(c, 0.25), 0, -8))
    return {"": x}


@sfx("amb_lobby_sindang", "AMB", "신당(로비) 밤 베드 40s 루프: 실내 촛불 + 문밖 풀벌레(풍경 원샷은 런타임)", loop=True)
def amb_lobby(use):
    fire = d.lowpass(d.load(os.path.join(gi.SRC, "fire_crackle.flac")), 5000, 2)
    use.append("fire_crackle")
    crk = d.lowpass(d.highpass(d.load(os.path.join(gi.SRC, "crickets_forest.flac")), 1800, 2), 7000, 2)
    use.append("crickets_forest")
    L = 28.0
    f = loopify(d.pad_to(fire, n_of(30)), L, 1.5)
    c = loopify(d.pad_to(crk, n_of(30)), L, 1.5)
    room = gi.drone(L, (-24, -12), 12, 150) * 0.02
    return {"": d.mix((d.to_stereo(f * 0.5, 0.0), 0, -6), (d.to_stereo(c, -0.3), 0, -10), (d.to_stereo(room), 0, -20))}


@sfx("amb_trial_field", "AMB", "시련 장 오버레이 20s 루프: 저음 허밍 + 공간감", loop=True)
def amb_trial(use):
    L = 20.0
    hum = gi.drone(L, (-12, -5, 0, 7), 13, 500)
    air = d.lowpass(d.load(os.path.join(gi.SRC, "wind_night_b.flac")), 2000, 2)
    use.append("wind_night_b")
    a = loopify(d.pad_to(air, n_of(19)), 16.0, 1.0)
    a = np.concatenate([a, a])[: n_of(L)]
    return {"": d.mix((d.to_stereo(hum), 0, -6), (d.to_stereo(a, 0.1), 0, -10))}


# ---------------------------------------------------------------- 적 P0 보충(아귀·어둑시니·저승사자)
@sfx("sfx_enm_agwi", "L3", "아귀: 공물 근처 '쩝' 씹는 소리(젖은 스맥 저역화) x6 / __steal 공물 그릇 엎어짐(놋그릇+나무)")
def enm_agwi(use):
    out = {}
    for v in range(6):
        r = rng(700 + v)
        sm = d.lowpass(S("smacks", v % 8, dur=0.18, use=use), 1800 + 300 * (v % 3), 2)
        sm = d.resample(sm, semis(-4 - (v % 3)))
        sm = d.fade(sm, 0.0, 0.05) * env_hit(len(sm), 0.06)
        wet = d.bandpass(d.noise(0.08, r), 600, 2400, 2) * env_hit(n_of(0.08), 0.015)
        x = d.mix((sm, 0, 0), (wet, 0.01, -9), (sm * 0.6, 0.11 + 0.01 * (v % 2), -7))  # '쩝-쩝' 두 번 씹기
        out["" if v == 0 else f"__v{v + 1}"] = hard_front(x, 4)
    clank = gi.nokgeureut(0.9, 4, 1.4, 1.3)
    use += ["korean_bell"]
    wood = d.pad_to(S("wood_blocks", 3, use=use), n_of(0.3))
    roll = d.fade(gi.nokgeureut(0.4, 5, 1.0, 1.5)[:n_of(0.6)], 0, 0.3)
    out["__steal"] = d.mix((wood, 0, -3), (clank, 0.02, 0), (roll, 0.18, -8), (roll, 0.29, -12))
    return out


@sfx("sfx_elite_eodukssini", "STG", "어둑시니 등장 2박(휘모리권 0.9s): 저음 드론 피치 하강 + 막힌 공기(고역 감쇄는 런타임 버스 LPF)")
def elite_eoduk(use):
    out = {}
    for v in range(4):
        dur = 1.8
        n = n_of(dur)
        f0 = 98.0 * semis(-v * 0.5)
        tone = d.mix((d.sine_sweep(dur, f0, f0 / 2.0), 0, 0), (d.sine_sweep(dur, f0 * 1.5, f0 * 0.75), 0, -9),
                     (d.sine_sweep(dur, f0 * 2.01, f0 * 1.0), 0, -14))
        tone = d.saturate(tone, 4.0) * d.env_ar(n, 0.04, 1.4)
        air = d.lowpass(noise_sweep(dur, 900, 180, 0.8, 30 + v, "fall"), 900, 2)
        beat1 = d.lowpass(gi.soribuk(0.9, 20 + v), 400, 2)  # 대북은 산신 예약 → 소리북 저역
        beat2 = d.lowpass(gi.soribuk(0.7, 24 + v), 300, 2)
        use += ["drum_hits_dry", "wood_blocks"]
        x = d.mix((tone, 0, 0), (air, 0, -10), (beat1, 0, -3), (beat2, 0.45, -6))
        out["" if v == 0 else f"__v{v + 1}"] = d.reverb(x, -12, 2.4, lp_hz=1800)
    return out


def _saja_step(k: int, use, stop: bool = False) -> np.ndarray:
    """저승사자 한 걸음: 묵직한 발(낮은 북 저역) + 갓끈·도포 스침."""
    n = n_of(0.7)
    foot = d.lowpass(d.pad_to(S("drum_hits_low", k % 6, use=use), n), 260, 3) * env_hit(n, 0.12)
    foot = d.resample(foot, semis(-5))[:n]
    cloth = d.bandpass(S("cloth_flap", (k + 1) % 8, dur=0.45, use=use), 300, 4500, 2)
    cloth = d.fade(cloth, 0.03, 0.15)
    rust = d.highpass(S("paper_rustle", k % 8, dur=0.2, use=use), 2500, 2) * 0.5  # 갓 테 스침(대나무·한지)
    parts = [(d.pad_to(foot, n), 0.0, 0), (cloth, 0.0 if not stop else 0.05, -6), (rust, 0.06, -14)]
    return d.mix(*parts)


@sfx("sfx_chaser_saja_step", "L3", "저승사자 걸음 4변주(살 거둠, 휘모리 박 정렬은 런타임 Q) / __threestep 명부 문 이동 3보")
def saja_step(use):
    out = {}
    for v in range(4):
        out["" if v == 0 else f"__v{v + 1}"] = d.reverb(_saja_step(v, use), -14, 2.0, lp_hz=3000)
    beat = 60 / 120 * 2 / 3  # 휘모리 소박 근사
    out["__threestep"] = d.reverb(d.mix(*[(_saja_step(4 + k, use), k * beat * 1.5, -k * 1.5) for k in range(3)]), -12, 2.2, lp_hz=3000)
    return out


@sfx("sfx_chaser_saja_eup", "RIT", "사자의 읍: 도포 숙이는 천(옅게) + 깊은 숨 + 소리북 1타(엄숙 — 방울 없음, 2026-11-24)")
def saja_eup(use):
    cloth = d.lowpass(S("cloth_flap", 5, dur=0.9, use=use), 3000, 2)
    cloth = d.fade(d.resample(cloth, semis(-3)), 0.08, 0.3)
    br = d.fade(d.bandpass(S("breath_deep", 2, dur=1.4, use=use), 200, 2500, 2), 0.15, 0.6)
    buk = d.lowpass(gi.soribuk(0.9, 31), 1600, 2)
    use += ["drum_hits_dry", "wood_blocks"]
    x = d.mix((cloth, 0, -8), (br, 0.1, -3), (hard_front(buk), 0.95, 0), (sub_drop(0.6, 55, 1.5, 0.02, 0.2), 0.95, -8))
    return {"": d.reverb(x, -11, 2.6, lp_hz=3500)}


# ---------------------------------------------------------------- main
def main(only):
    os.makedirs(OUT, exist_ok=True)
    idx_path = os.path.join(OUT, "sfx_index.json")
    index = json.load(open(idx_path, encoding="utf-8")) if os.path.exists(idx_path) else {}
    for sid, (fn, cls, note, loop) in R.items():
        if only and sid not in only:
            continue
        use: list = []
        variants = fn(use)
        files = {}
        for var, x in variants.items():
            name = sid + var
            is_loop = loop or var in ("__aura", "__hum")
            if is_loop:
                tgt, pk = CLASS[cls]
                y = d.normalize_lufs(d.dc_block(x), tgt if cls == "AMB" else tgt - 6, pk, mode="integrated")
            else:
                y = finish(x, cls)
            path = os.path.join(OUT, name + ".ogg")
            d.save(path, y, quality=5.0)
            files[name] = {"path": "assets/sfx/" + name + ".ogg", "dur_s": round(len(y) / SR, 3),
                           "lufs_s": round(d.short_term_max(y), 1), "peak_db": round(20 * np.log10(np.abs(y).max() + 1e-12), 1),
                           "stereo": bool(y.ndim == 2), "loop": is_loop}
        index[sid] = {"class": cls, "note": note, "files": files, "samples": sorted(set(use))}
        print(f"{sid:28s} {cls:4s} {len(files)} file(s)  {', '.join(f'{v['dur_s']}s' for v in files.values())}")
    json.dump(index, open(idx_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main(set(sys.argv[1:]))
