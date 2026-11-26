"""build_sfx_silent.py — 무음이던 SFX 27종 채우기 (KoreaLike / 넋길: 해원굿). 소유: audio.

2026-11-24: [audio] ready ... missing=27 의 정의 27개(파일 없음 + 대체 규칙 없음)를 절차적 합성 + 기존 CC0/CC-BY 샘플 뱅크
(art/audio/src, build_sfx 와 같은 재료) 가공으로 만든다. 새 외부 음원은 받지 않았다.
  python -I tools/audio/build_sfx_silent.py              # 27종 전부
  python -I tools/audio/build_sfx_silent.py sfx_plr_step

규칙(design/12, build_sfx.py 머리말과 같다):
  - 공용 SFX 는 장구·소리북·방울·놋그릇·한지·무명천·나무만. 신령 예약 악기(꽹과리=칠성 등)는 그 신령 시련 소리에만.
  - 적 소리(L3)는 아군 타격음(고역 '탁'·방울)과 대역을 나눈다: 저·중역, 숨·종이·물·불 질감, 비음정.
  - 루프는 끝을 앞과 크로스페이드(build_sfx.loopify)해 경계 무절단, 라우드니스는 integrated 기준(main 이 처리).
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_sfx as B  # noqa: E402
import gugak_dsp as d  # noqa: E402
import gugak_inst as gi  # noqa: E402
from gugak_dsp import n_of, rng, semis  # noqa: E402

_S0, sfx, env_hit, hard_front, sub_drop, noise_sweep = B.S, B.sfx, B.env_hit, B.hard_front, B.sub_drop, B.noise_sweep
loopify, bell_tone = B.loopify, B.bell_tone
D4, D5, D6, TORI = gi.D4, B.D5, B.D6, B.TORI

MINE: list = []


def mine(sid: str, cls: str, note: str = "", loop: bool = False):
    MINE.append(sid)
    return sfx(sid, cls, note, loop)


def onset(x: np.ndarray, thr: float = 0.15) -> np.ndarray:
    a = np.abs(d.mono(x))
    if a.max() <= 0:
        return x
    i = int(np.argmax(a >= thr * a.max()))
    return x[max(0, i - n_of(0.001)):]


def S(key: str, i: int = 0, start: float = 0.0, dur: float | None = None, use: list | None = None, lead: bool = False) -> np.ndarray:
    x = _S0(key, i, start, None, use)
    if lead:
        x = onset(x)
    return d.pad_to(x, n_of(dur)) if dur is not None else x


def tight(x: np.ndarray, sec: float, fout: float = 0.03) -> np.ndarray:
    return d.fade(d.pad_to(x, n_of(sec)), 0.0, min(fout, sec * 0.5))


def tile_to(x: np.ndarray, sec: float) -> np.ndarray:
    n = n_of(sec)
    if len(x) >= n:
        return x[:n]
    reps = int(np.ceil(n / len(x)))
    return np.concatenate([x] * reps)[:n]


def gate_noise(sec: float, rate: float, seed: int, duty: float = 0.5) -> np.ndarray:
    """무작위 게이트(속삭임 음절·지직). rate = 초당 조각 수."""
    r = rng(seed)
    n = n_of(sec)
    g = np.zeros(n)
    t = 0.0
    while t < sec:
        ln = r.uniform(0.4, 1.0) * duty / rate
        a, b = n_of(t), min(n, n_of(t + ln))
        if b > a:
            g[a:b] = np.hanning(b - a) * r.uniform(0.4, 1.0)
        t += r.uniform(0.6, 1.4) / rate
    return g


def bubble(f0: float, f1: float, sec: float, seed: int) -> np.ndarray:
    """물방울·거품 '뽁': 짧은 상행 처프 + 빠른 감쇠."""
    n = n_of(sec)
    return d.sine_sweep(sec, f0, f1) * env_hit(n, sec * 0.35, 0.002) * (0.8 + 0.2 * rng(seed).uniform())


def take_key(v: int) -> str:
    return "" if v == 0 else f"__v{v + 1}"


# =================================================================== 무당 · 굿판
@mine("sfx_plr_step", "L3", "무당 발걸음(버선): 낮은 흙 '툭' + 무복 자락 스침 + 잔 흙알. 6테이크, 런타임 이동속도 비례 간격·−10dB 배경 질감")
def plr_step(use):
    out = {}
    for v in range(6):
        r = rng(9100 + v)
        thud = d.lowpass(d.noise(0.12, r), 420 + 60 * (v % 3), 2) * env_hit(n_of(0.12), 0.022) * 1.6
        sole = d.bandpass(d.noise(0.08, rng(9110 + v)), 700, 2600, 2) * d.env_ar(n_of(0.08), 0.006, 0.06) * 0.5
        grit = d.highpass(S("bamboo_maraca", v, dur=0.06, use=use, lead=True), 3200, 2) * env_hit(n_of(0.06), 0.012)
        cloth = d.bandpass(S("cloth_flap", v, dur=0.14, use=use, lead=True), 300, 3000, 2) * d.env_ar(n_of(0.14), 0.02, 0.1)
        x = d.mix((thud, 0, 0), (sole, 0.004, -8), (grit, 0.006, -24 - 2 * r.uniform()), (cloth, 0.01, -19))
        out[take_key(v)] = tight(d.resample(x, semis(r.uniform(-1.2, 1.2))), 0.18, 0.05)
    return out


@mine("sfx_sys_gilbe_loop", "RIT", "길베 루프 4s: 흰 무명이 바닥을 스치는 '사아—' (대역 노이즈 + 느린 결 LFO + 옅은 천 펄럭). 런타임 볼륨 = 이동속도", loop=True)
def gilbe_loop(use):
    L, XF = 4.0, 0.8
    T = L + XF
    n = n_of(T)
    t = d.t_axis(n)
    r = rng(9200)
    hiss = d.bandpass(d.noise(T, r), 500, 4200, 2)
    lfo = 0.6 + 0.25 * np.sin(2 * np.pi * 1.0 * t) + 0.15 * np.sin(2 * np.pi * 2.5 * t + 1.3)
    grain = d.highpass(d.noise(T, rng(9201)), 3000, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 7.0 * t) ** 2) * 0.25
    flaps = d.mix(*[(d.fade(d.bandpass(S("cloth_flap", k, dur=0.5, use=use), 250, 3500, 2), 0.05, 0.25), 0.4 + k * 1.15, -12 - 2 * (k % 2))
                    for k in range(4)])
    x = d.mix((hiss * lfo, 0, 0), (grain, 0, -6), (d.pad_to(flaps, n), 0, 0))
    return {"": loopify(d.lowpass(x, 6500, 2), L, XF)}


@mine("sfx_sys_doryang", "RIT", "오방 만다라 도량: 방울 오방 차임(토리 5음 상행, 청·적·황·백·흑) + 2.4s 낮은 허밍(D 저음, 서서히 잦아듦)")
def doryang(use):
    bells = d.mix(*[(bell_tone(D5 * semis(st), 1.3, 0.9 - 0.06 * i, 9300 + i, 0.3), 0.02 + i * 0.09, -i * 0.6) for i, st in enumerate(TORI)])
    use += ["korean_bell", "sleigh_bells"]
    hum = gi.drone(2.4, (-24, -12, -5), 93, 420) * d.env_ar(n_of(2.4), 0.5, 1.5) * 0.06
    x = d.mix((bells, 0, 0), (hum, 0.1, -4), (sub_drop(0.6, 73.4, 1.6, 0.02, 0.25), 0.02, -10))
    return {"": d.reverb(x, -11, 2.2)}


@mine("sfx_sys_sinmyeong_tick", "RIT", "신명 25/50/75%: 장구 '기덕' 장식(꽹과리 아님). 기본=25 / __50 기덕+방울 / __75 기기덕+방울 두 음")
def sinmyeong_tick(use):
    t25 = d.mix((gi.janggu_gi(0.45, 1), 0, 0), (gi.janggu_deok(0.7, 2, short=True), 0.07, 0))
    t50 = d.mix((gi.janggu_gi(0.5, 3), 0, 0), (gi.janggu_deok(0.82, 4, short=True), 0.065, 0),
                (bell_tone(D6, 0.7, 0.6, 9310, 0.2), 0.065, -10))
    t75 = d.mix((gi.janggu_gi(0.45, 5), 0, 0), (gi.janggu_gi(0.55, 6), 0.045, 0), (gi.janggu_deok(0.95, 7, short=True), 0.095, 0),
                (bell_tone(D6, 0.8, 0.7, 9311, 0.2), 0.095, -9), (bell_tone(D6 * semis(7), 0.8, 0.6, 9312, 0.2), 0.14, -11))
    use += ["drum_sticks", "drum_hits_dry", "korean_bell"]
    return {"": hard_front(t25), "__50": hard_front(t50), "__75": hard_front(d.reverb(t75, -16, 1.2))}


@mine("sfx_sys_giun_cross", "L3", "굿판의 기운 50% 경계: 넋쪽 = 맑은 방울 한 점(기본) / __sal 살쪽 = 낮은 바람 한 숨. 판정 톤 아님 — 아주 작게")
def giun_cross(use):
    neok = d.reverb(d.mix((bell_tone(D6 * semis(9), 1.1, 0.5, 9320, 0.15), 0, 0),
                          (noise_sweep(0.5, 3000, 7000, 0.5, 9321, "swell"), 0, -16)), -10, 1.8)
    sal = d.mix((noise_sweep(0.8, 900, 220, 0.8, 9322, "swell"), 0, 0), (sub_drop(0.7, 55, 1.3, 0.05, 0.3), 0.05, -8))
    use += ["korean_bell"]
    return {"": neok, "__sal": d.lowpass(sal, 1500, 2)}


# =================================================================== 어둑시니 (정예) 루프
@mine("sfx_sys_eoduk_grow", "L3", "어둑시니 성장 루프 3s: 낮게 들이쉬는 숨(−7반음) + 55Hz 맥동 + 먹먹한 저역 바람(관심을 먹는 소리)", loop=True)
def eoduk_grow(use):
    L, XF = 3.0, 0.6
    T = L + XF
    n = n_of(T)
    t = d.t_axis(n)
    br = d.lowpass(d.resample(tile_to(S("breath_deep", 1, use=use), 2.3), semis(-7)), 900, 2)
    br = d.pad_to(d.fade(br, 0.3, 0.6), n)
    sub = np.sin(2 * np.pi * 55 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * (1 / 1.5) * t) ** 2) * 0.35
    wind = d.lowpass(noise_sweep(T, 200, 500, 0.9, 9330, "flat"), 600, 2) * 0.5
    x = d.saturate(d.mix((br, 0, 0), (sub, 0, -2), (wind, 0, -6)), 3.0)
    return {"": loopify(x, L, XF)}


@mine("sfx_sys_eoduk_shrink", "L3", "어둑시니 축소 루프 2s: 공기 빠지는 고역 '쉬이—'(떨림). 런타임 축소 속도 비례 피치 상승", loop=True)
def eoduk_shrink(use):
    L, XF = 2.0, 0.4
    T = L + XF
    n = n_of(T)
    t = d.t_axis(n)
    hiss = d.bandpass(d.noise(T, rng(9340)), 2200, 8000, 2)
    flutter = 0.65 + 0.35 * np.sin(2 * np.pi * 11.0 * t) * np.sin(2 * np.pi * 0.5 * t)
    body = d.bandpass(d.noise(T, rng(9341)), 600, 1800, 2) * 0.3
    return {"": loopify(d.mix((hiss * flutter, 0, 0), (body, 0, -8)), L, XF)}


# =================================================================== 시련 과제(가호)
@mine("sfx_trl_grm_connect_star", "RIT", "별 잇기(칠성 가호): 꽹과리 '갠' 1음(칠성 예약 악기 — 칠성 시련 전용). 런타임 별 번호마다 토리 상행 피치")
def grm_star(use):
    k = gi.kkwaenggwari("gaen", 0.6, 3)
    use += ["gong_korean_cdrk"]
    sh = bell_tone(D6 * 2, 0.6, 0.35, 9350, 0.1)
    return {"": d.reverb(hard_front(d.mix((k, 0, 0), (sh, 0.004, -14))), -14, 1.4)}


@mine("sfx_trl_grm_install", "RIT", "오방기 세움(장군 가호): 깃대 꽂힘 '쿵'(소리북 + 대나무) + 오색 천 펄럭. 런타임 다섯 자리 = 토리 5음 피치")
def grm_install(use):
    out = {}
    for v in range(2):
        buk = d.lowpass(gi.soribuk(0.85, 40 + v), 1200, 2)
        tak = d.bandpass(S("bamboo_hit", 0, dur=0.12, use=use, lead=True), 400, 5000, 2) * env_hit(n_of(0.12), 0.04)
        fl = d.fade(d.bandpass(S("cloth_flap", 3 + v, dur=0.35, use=use), 300, 6000, 2), 0.01, 0.15)
        use += ["drum_hits_dry"]
        x = d.mix((hard_front(tak), 0, 0), (buk, 0.002, -2), (fl, 0.05, -6), (sub_drop(0.3, 62, 1.8, 0.01, 0.1), 0, -8))
        out[take_key(v)] = d.reverb(x, -15, 1.4)
    return out


@mine("sfx_trl_grm_hold_loop", "RIT", "거점 유지 진척 루프 4s: 산신 쉼터의 낮은 허밍(D 저음 화음, 숨 쉬듯 맥동). 런타임 진척 비례 피치 0→+7반음", loop=True)
def grm_hold(use):
    L = 4.0
    hum = gi.drone(L, (-12, -5, 0), 94, 700)
    air = loopify(d.lowpass(noise_sweep(L + 0.5, 300, 700, 0.8, 9360, "flat"), 900, 2), L, 0.5)
    return {"": d.mix((hum * 0.06, 0, 0), (air * 0.4, 0, -10))}


@mine("sfx_trl_grm_escort_arrive", "RIT", "호송 도착: 넋이 닿을 때 맑은 물방울 + 방울 한 쌍(상행 4도)")
def grm_escort(use):
    out = {}
    for v in range(2):
        wd = d.pad_to(S("water_drop", 2 + v, use=use, lead=True), n_of(0.3)) * env_hit(n_of(0.3), 0.08)
        b1 = bell_tone(D5 * semis(TORI[v + 1]), 1.0, 0.8, 9370 + v, 0.25)
        b2 = bell_tone(D5 * semis(TORI[v + 1] + 5), 1.0, 0.7, 9372 + v, 0.25)
        use += ["korean_bell", "sleigh_bells"]
        x = d.mix((wd, 0, 0), (b1, 0.03, -3), (b2, 0.12, -5))
        out[take_key(v)] = d.reverb(x, -12, 1.8)
    return out


@mine("sfx_evt_gongmulsang", "RIT", "뒷전 공물상 차림 2s: 놋그릇·나무 제기 놓이는 소리 군집 + 잡귀 발 '사락사락' 몰려듦")
def gongmulsang(use):
    out = {}
    for v in range(2):
        r = rng(9380 + v)
        parts = []
        for k in range(9):
            t0 = 0.05 + k * 0.17 + r.uniform(-0.04, 0.04)
            if k % 3 == 2:
                w = d.bandpass(S("wood_blocks", k + v, dur=0.15, use=use, lead=True), 500, 4000, 2) * env_hit(n_of(0.15), 0.04)
                parts.append((w, t0, -6 - r.uniform(0, 3)))
            else:
                bowl = gi.nokgeureut(0.35 + 0.2 * r.uniform(), 10 + k + v * 9, 0.7, 1.6 + 0.3 * r.uniform())
                parts.append((d.fade(bowl, 0, 0.3), t0, -8 - r.uniform(0, 4)))
        use += ["korean_bell"]
        feet = d.mix(*[(d.highpass(S("paper_rustle", j + v, dur=0.12, use=use, lead=True), 1500, 2) * env_hit(n_of(0.12), 0.03),
                        0.6 + j * 0.085 + r.uniform(0, 0.03), -8 - (j % 3) * 2) for j in range(14)])
        x = d.mix(*parts, (feet, 0, -6))
        out[take_key(v)] = d.reverb(d.pad_to(x, n_of(2.2)), -14, 1.6)
    return out


# =================================================================== 적 10종 (L3, 저·중역 비음정)
def _gaekgwi(v, use):        # 객귀: 무의미 음절 속삭임 + 붙는 '스윽'
    br = d.bandpass(tile_to(S("breath_woman", v, start=0.3 * v, use=use), 0.7), 1200, 6500, 2)
    syl = br * gate_noise(0.7, 9.0, 9400 + v, 0.6)
    sw = d.bandpass(S("cloth_flap", v + 2, dur=0.3, use=use, lead=True), 400, 3000, 2) * d.env_ar(n_of(0.3), 0.08, 0.2)
    return d.mix((syl, 0, 0), (sw, 0.35, -5))


def _cheonyeo(v, use):       # 처녀귀신: 머리 휘날림 '사아' + 낮은 '휘잉'(청 계열 저역 쉬익)
    hair = noise_sweep(0.45, 2500, 5000, 0.6, 9410 + v, "swell")
    whine = d.sine_sweep(0.55, 330 * semis(v * 0.5), 190) * d.env_ar(n_of(0.55), 0.06, 0.4) * 0.25
    low = noise_sweep(0.55, 900, 300, 0.7, 9415 + v, "swell")
    return d.mix((d.lowpass(hair, 5000, 2), 0, -13), (whine, 0.08, -5), (d.lowpass(low, 1500, 2), 0.08, 0))


def _mongdal(v, use):        # 몽달귀신: 발 끌기 → 돌진 바람 '휙'
    drag = d.lowpass(S("paper_rustle", v + 5, dur=0.4, use=use), 2500, 2) * d.env_ar(n_of(0.4), 0.05, 0.25)
    scrape = d.bandpass(d.noise(0.4, rng(9420 + v)), 200, 1200, 2) * d.env_ar(n_of(0.4), 0.1, 0.2) * 0.6
    wh = d.fade(d.bandpass(S("whoosh_swing", v, dur=0.3, use=use), 300, 3500, 2), 0.01, 0.12)
    return d.mix((drag, 0, -2), (scrape, 0, -4), (wh, 0.36, 0))


def _mul(v, use):            # 물귀신: 물 고이는 '꾸르륵'(탁한 거품)
    r = rng(9430 + v)
    bub = d.mix(*[(bubble(r.uniform(160, 260), r.uniform(380, 650), r.uniform(0.03, 0.06), 9431 + k), 0.02 + k * r.uniform(0.04, 0.08), -r.uniform(0, 6))
                  for k in range(8)])
    wet = d.lowpass(d.pad_to(S("water_drop", v + 4, use=use, lead=True), n_of(0.3)), 1500, 2)
    wet = d.resample(wet, semis(-6))
    return d.lowpass(d.mix((bub, 0, 0), (wet, 0, -6)), 2200, 2)


def _hosik(v, use):          # 호식 원혼: 낮은 숨(짐승 기척) + 먼 메아리
    br = d.lowpass(d.resample(tile_to(S("breath_deep", v + 2, use=use), 1.0), semis(-5 - v % 2)), 1000, 2)
    br = d.fade(br, 0.08, 0.35)
    growl = d.lowpass(d.noise(0.8, rng(9440 + v)), 220, 3) * d.env_ar(n_of(0.8), 0.2, 0.5) * 1.2
    return tight(d.reverb(d.mix((br, 0, 0), (growl, 0.05, -6)), -14, 2.0, lp_hz=2500), 1.4, 0.4)


def _dokkaebi(v, use):       # 도깨비불: 불꽃 일렁 + 불씨 '팍'
    fl = d.bandpass(S("fire_crackle", 0, start=1.5 + 2.7 * v, dur=0.6, use=use), 300, 4000, 2)
    fl = d.fade(fl, 0.08, 0.25)
    whf = d.fade(d.lowpass(S("candle_wind", 0, start=1.0 + 1.3 * v, dur=0.5, use=use), 1800, 2), 0.1, 0.25)
    pop = d.bandpass(d.noise(0.05, rng(9450 + v)), 900, 5000, 2) * env_hit(n_of(0.05), 0.008) * 1.4
    return d.mix((whf, 0, 0), (fl, 0, -3), (pop, 0.42, -2))


def _yeongsan(v, use):       # 영산: 흉살 장판 '지직' (낮은 버즈 + 지글)
    buzz = d.lowpass(d.noise(0.38, rng(9460 + v)), 700, 2) * gate_noise(0.38, 38.0 + 6 * v, 9461 + v, 0.5) * 1.6
    hum = np.sin(2 * np.pi * (58 + 3 * v) * d.t_axis(n_of(0.38))) * d.env_ar(n_of(0.38), 0.02, 0.3) * 0.4
    return d.saturate(d.mix((buzz, 0, 0), (hum, 0, -4), (sub_drop(0.3, 50, 1.4, 0.01, 0.12), 0, -8)), 5.0)


def _sangmun(v, use):        # 상문: 마른 종이 바스락 + 낮은 단2도 놋그릇 경고
    pap = d.fade(d.bandpass(S("paper_fold", v + 1, dur=0.45, use=use), 700, 6000, 2), 0.01, 0.2)
    b1 = gi.nokgeureut(0.35, 30 + v, 1.0, 0.5)
    b2 = gi.nokgeureut(0.3, 34 + v, 1.0, 0.5 * semis(1))
    use += ["korean_bell"]
    warn = d.lowpass(d.mix((b1, 0, 0), (b2, 0.01, -2)), 1400, 2)
    return d.mix((pap, 0, 0), (d.fade(warn, 0, 0.4), 0.12, -9))


def _subi(v, use):           # 수비: 수십 개 작은 발 사락 군집
    r = rng(9480 + v)
    parts = [(d.highpass(S("bamboo_maraca", k + v, dur=0.04, use=use, lead=True), 1800, 2) * env_hit(n_of(0.04), 0.01),
              r.uniform(0, 0.7), -r.uniform(2, 12)) for k in range(26)]
    taps = [(d.lowpass(d.noise(0.03, rng(9490 + k + v * 40)), 900, 2) * env_hit(n_of(0.03), 0.006), r.uniform(0, 0.7), -r.uniform(4, 12))
            for k in range(14)]
    x = d.mix(*parts, *taps)
    return d.lowpass(x * d.env_ar(len(x), 0.12, 0.3), 5000, 2)


def _hwehwe(v, use):         # 훼훼귀신: 가위눌림 압박 드론(맥놀이) + 먹먹한 공기
    T = 1.0
    t = d.t_axis(n_of(T))
    f = 68 + 4 * v
    dr = (np.sin(2 * np.pi * f * t) + 0.8 * np.sin(2 * np.pi * (f + 3.1) * t) + 0.3 * np.sin(2 * np.pi * f * 2.01 * t))
    dr = d.saturate(dr * d.env_ar(n_of(T), 0.35, 0.5) * 0.4, 6.0)
    muff = d.lowpass(noise_sweep(T, 300, 900, 0.9, 9500 + v, "swell"), 1200, 2)
    return d.mix((dr, 0, 0), (muff, 0, -6))


ENEMIES = {
    "gaekgwi": (_gaekgwi, "객귀: 무의미 음절 속삭임 + 붙는 '스윽'"),
    "cheonyeo_gwisin": (_cheonyeo, "처녀귀신: 머리 휘날림 '사아' + 낮은 '휘잉'(저역 쉬익)"),
    "mongdal_gwisin": (_mongdal, "몽달귀신: 발 끌기 → 돌진 '휙'"),
    "mul_gwisin": (_mul, "물귀신: 물 고이는 탁한 '꾸르륵'"),
    "hosik_wonhon": (_hosik, "호식 원혼: 낮은 짐승 숨 + 먼 메아리"),
    "dokkaebi_bul": (_dokkaebi, "도깨비불: 불꽃 일렁 + 불씨 '팍'"),
    "yeongsan": (_yeongsan, "영산: 흉살 장판 낮은 '지직'"),
    "sangmun": (_sangmun, "상문: 마른 종이 바스락 + 낮은 단2도 놋그릇 경고"),
    "subi": (_subi, "수비: 작은 발 사락 군집"),
    "hwehwe_gwisin": (_hwehwe, "훼훼귀신: 가위눌림 압박 드론(맥놀이) + 먹먹한 공기"),
}


def _make_enemy(name: str, fn, note: str):
    @mine(f"sfx_enm_{name}", "L3", note + " — 4테이크. 런타임: 종 첫 등장 1회 + 종당 6s 간격 기척(−12dB)")
    def _r(use, fn=fn):
        out = {}
        for v in range(4):
            x = fn(v, use)
            out[take_key(v)] = d.fade(d.dc_block(x), 0.0, 0.04)
        return out
    return _r


for _n, (_f, _note) in ENEMIES.items():
    _make_enemy(_n, _f, _note)


# =================================================================== 앰비언스 5종(1스테이지 밖 — 24s 스테레오 루프)
AMB_L, AMB_XF = 24.0, 2.0


def _bed(x: np.ndarray) -> np.ndarray:
    return loopify(x, AMB_L, AMB_XF)


def _wind(key: str, lp: float, use, seed: int = 0) -> np.ndarray:
    w = gi.bank(key)[0]
    use.append(key)
    off = n_of(seed * 3.7) % max(1, len(w) - 1)
    w = np.concatenate([w[off:], w[:off]])
    return d.lowpass(tile_to(w, AMB_L + AMB_XF), lp, 2)


def _sparse(make, count: int, seed: int, lo: float = 0.5, hi: float = AMB_L - 1.0) -> np.ndarray:
    r = rng(seed)
    parts = [(d.to_stereo(make(k), r.uniform(-0.8, 0.8)), r.uniform(lo, hi), -r.uniform(0, 6)) for k in range(count)]
    return d.pad_to(d.mix(*parts), n_of(AMB_L + AMB_XF))


def _waves(T: float, period: float, seed: int, lp: float = 900) -> np.ndarray:
    n = n_of(T)
    t = d.t_axis(n)
    k = max(1, round(AMB_L / period))
    ph = 2 * np.pi * k / AMB_L * t
    env = 0.25 + 0.75 * (0.5 + 0.5 * np.sin(ph)) ** 3
    return d.lowpass(d.noise(T, rng(seed)), lp, 2) * env


@mine("amb_jindo_ssitgim", "AMB", "남도 갯마을 갯벌 24s: 먼 갯바람 + 갯벌 거품 '뽀글' + 갈대 사락 + 드문 바람 방울(파도 없음)", loop=True)
def amb_jindo(use):
    T = AMB_L + AMB_XF
    wind = _wind("wind_night_a", 1400, use, 1)
    reeds = d.highpass(tile_to(gi.bank("bamboo_forest")[0], T), 2500, 2) * 0.35
    use.append("bamboo_forest")
    mud = _sparse(lambda k: bubble(220 + 40 * (k % 5), 520 + 60 * (k % 4), 0.05, 9600 + k), 40, 9601)
    bell = _sparse(lambda k: bell_tone(D6 * semis(TORI[k % 5]), 1.6, 0.25, 9610 + k, 0.4), 2, 9611, 6, 18)
    x = d.mix((d.to_stereo(wind, -0.2), 0, 0), (d.to_stereo(reeds, 0.4), 0, -10), (mud, 0, -14), (bell, 0, -18))
    return {"": _bed(x)}


@mine("amb_east_sea_byeolsin", "AMB", "동해안 별신굿 바닷가 24s: 주기적 파도(8s) + 굿청 천막 펄럭 + 밧줄 삐걱", loop=True)
def amb_east_sea(use):
    T = AMB_L + AMB_XF
    sea = d.mix((d.to_stereo(_waves(T, 8.0, 9620), -0.3), 0, 0), (d.to_stereo(_waves(T, 6.0, 9621, 1400), 0.35), 0, -5))
    tent = _sparse(lambda k: d.fade(d.bandpass(S("cloth_flap", k, dur=0.6, use=use), 200, 3000, 2), 0.02, 0.3), 5, 9622)
    creak = _sparse(lambda k: d.bandpass(d.sine_sweep(0.5, 180 + 30 * k, 240 + 20 * k) * gate_noise(0.5, 25, 9630 + k, 0.7), 150, 1200, 2), 3, 9631, 3, 20)
    x = d.mix((sea, 0, 0), (tent, 0, -12), (creak, 0, -16))
    return {"": _bed(x)}


@mine("amb_jeju_chilmeori", "AMB", "제주 칠머리당 해안 24s: 센 바람(돌풍) + 현무암 파도 + 깃 펄럭", loop=True)
def amb_jeju(use):
    T = AMB_L + AMB_XF
    w1 = _wind("wind_night_b", 3000, use, 2)
    gust = noise_sweep(T, 400, 1600, 0.7, 9640, "flat") * (0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * (3 / AMB_L) * d.t_axis(n_of(T)))) ** 2)
    sea = _waves(T, 6.0, 9641, 700)
    flag = _sparse(lambda k: d.fade(d.bandpass(S("cloth_flap", k + 3, dur=0.5, use=use), 300, 5000, 2), 0.01, 0.25), 6, 9642)
    x = d.mix((d.to_stereo(w1, 0.5), 0, 0), (d.to_stereo(gust, -0.5), 0, -4), (d.to_stereo(sea, 0.0), 0, -6), (flag, 0, -10))
    return {"": _bed(x)}


@mine("amb_myeongbu", "AMB", "명부 저승길 24s: 느린 삼도 물 흐름 + 끝없는 저역 + 먼 방울 + 흰 베 펄럭", loop=True)
def amb_myeongbu(use):
    T = AMB_L + AMB_XF
    t = d.t_axis(n_of(T))
    flow = d.bandpass(d.noise(T, rng(9650)), 180, 900, 2) * (0.6 + 0.4 * np.sin(2 * np.pi * (2 / AMB_L) * t))
    drone = gi.drone(T, (-24, -17, -12), 96, 300) * 0.05
    bells = _sparse(lambda k: d.reverb(bell_tone(D5 * semis(TORI[(k * 2) % 5]), 2.0, 0.3, 9660 + k, 0.4), -4, 3.0), 3, 9661, 2, 19)
    cloth = _sparse(lambda k: d.fade(d.lowpass(S("cloth_flap", k + 5, dur=0.7, use=use), 2500, 2), 0.1, 0.3), 3, 9662)
    use += ["korean_bell", "sleigh_bells"]
    x = d.mix((d.to_stereo(flow, -0.2), 0, 0), (d.to_stereo(drone), 0, -2), (bells, 0, -12), (cloth, 0, -14))
    return {"": _bed(x)}


@mine("amb_island_bungyo", "AMB", "남해 외딴 섬 폐분교 24s: 형광등 험(120Hz 질감) + 바다 바람 + 문 삐걱·물방울 원샷", loop=True)
def amb_island(use):
    T = AMB_L + AMB_XF
    t = d.t_axis(n_of(T))
    hum = sum((1.0 / h) * np.sin(2 * np.pi * 120 * h * t + h) for h in range(1, 7)) * 0.05
    hum = hum * (1 + 0.08 * np.sin(2 * np.pi * (5 / AMB_L) * t)) + d.bandpass(d.noise(T, rng(9670)), 2000, 5000, 2) * 0.01
    wind = _wind("wind_night_a", 900, use, 4)
    door = _sparse(lambda k: d.bandpass(d.sine_sweep(0.9, 260 + 40 * k, 150) * gate_noise(0.9, 30, 9680 + k, 0.8), 120, 1500, 2), 2, 9681, 4, 18)
    drops = _sparse(lambda k: d.pad_to(S("water_drop", k, use=use, lead=True), n_of(0.4)), 5, 9682)
    x = d.mix((d.to_stereo(hum, 0.1), 0, 0), (d.to_stereo(wind, -0.3), 0, -2), (door, 0, -14), (drops, 0, -12))
    return {"": _bed(x)}


if __name__ == "__main__":
    only = set(sys.argv[1:]) or set(MINE)
    B.main(only)
