"""gugak_inst — 국악 타악·무구·관악 음원(샘플 + 모달/가산 합성 하이브리드).

원샷 샘플(art/audio/src, CC0/CC-BY)을 '재료'로 쓰고 국악기 고유 음색은 합성으로 보강한다.
CC0/CC-BY 공개 라이브러리에 장구·꽹과리 원샷 녹음이 사실상 없어서(Freesound/Wikimedia 조사, 2026-11),
장구 궁편/채편은 막 모달 합성 + 실제 북·스틱 타격 샘플 레이어로 만든다. 국악 연희자 녹음이 들어오면
같은 함수 이름으로 샘플만 교체하면 된다(build 스크립트는 수정 불필요).

장구 구음(문헌 기준 — 국립국악원 장단 교육 자료·국악 교과서 표기 관습):
  덩  = 합장단. 궁편(왼손 궁채/손바닥)과 채편(오른손 열채)을 동시에 친다.
  쿵  = 궁편(북편)만 친다. 낮고 둥근 소리.
  덕  = 채편만 열채로 친다. 높고 단단한 소리. (풍물·민요 악보에서는 '따/딱'으로도 적는다)
  기덕 = 채편 꾸밈. 앞꾸밈 '기'(약) + 본음 '덕'.
  더러러러 = 채편 굴림. 열채를 굴려 연타한다.
꽹과리 구음(사물놀이 관습): 갱=열고 친 큰 소리, 갠=짧게 연 소리, 지/객=왼손으로 막은 소리.
"""
from __future__ import annotations

import glob
import os

import numpy as np

import gugak_dsp as d
from gugak_dsp import SR, db, n_of, rng, semis

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art", "audio", "src")

D4 = 293.66  # 기준음 D (A4=440) — design/12-audio.md 6.3
_BANK: dict = {}


def bank(key: str) -> list:
    """art/audio/src/<key>.flac 또는 <key>_NN.flac 목록(강한 순)."""
    if key not in _BANK:
        files = sorted(glob.glob(os.path.join(SRC, f"{key}_[0-9][0-9].flac")))
        if not files and os.path.exists(os.path.join(SRC, f"{key}.flac")):
            files = [os.path.join(SRC, f"{key}.flac")]
        _BANK[key] = [d.load(f) for f in files]
        if not _BANK[key]:
            raise FileNotFoundError(f"sample bank '{key}' missing in {SRC} — run prepare_samples.py")
    return _BANK[key]


def pick(key: str, seed: int, top: int | None = None) -> np.ndarray:
    b = bank(key)
    if top:
        b = b[:top]
    return b[seed % len(b)].copy()


def clip_len(x: np.ndarray, sec: float, fout: float = 0.02) -> np.ndarray:
    return d.fade(d.pad_to(x, n_of(sec)), 0, fout)


def _vel_tone(x: np.ndarray, vel: float, lo: float = 1200, hi: float = 9000) -> np.ndarray:
    """세게 칠수록 밝게(타악 공통)."""
    fc = lo + (hi - lo) * vel ** 1.5
    return d.lowpass(x, fc, 2) * (vel ** 1.2)


# ================================================================ 장구
def janggu_kung(vel: float = 1.0, seed: int = 0) -> np.ndarray:
    """궁편 '쿵' — 느슨한 큰 가죽. 약 95Hz, 타격 직후 피치 하강."""
    r = rng(1000 + seed)
    dur = 0.7
    n = n_of(dur)
    f0 = 96 * semis(r.uniform(-0.25, 0.25))
    body = d.pitch_drop_sine(dur, f0, 1.5, 0.016, r) * d.env_exp(n, 0.21, 0.0008)
    modes = d.modal(dur, [(f0 * 1.59, 0.28, 0.085), (f0 * 2.14, 0.14, 0.05), (f0 * 2.65, 0.08, 0.035)], r)
    thump = d.lowpass(d.noise(dur, r), 700, 2) * d.env_exp(n, 0.010)
    smp = clip_len(d.highpass(pick("drum_hits_low", seed), 45, 2), dur, 0.15)
    smp = d.lowpass(smp, 2500, 2)
    x = body * 1.0 + modes + thump * 0.9 + smp * 0.55
    return _vel_tone(x, vel, 900, 6000)


def janggu_deok(vel: float = 1.0, seed: int = 0, short: bool = False) -> np.ndarray:
    """채편 '덕' — 팽팽한 얇은 가죽을 대나무 열채로. 날카로운 '딱' + 짧은 막 울림."""
    r = rng(2000 + seed)
    dur = 0.22 if short else 0.32
    n = n_of(dur)
    f = 318 * semis(r.uniform(-0.3, 0.3))
    modes = d.modal(dur, [(f, 1.0, 0.065), (f * 1.594, 0.62, 0.05), (f * 2.136, 0.45, 0.04), (f * 2.296, 0.32, 0.034),
                          (f * 2.653, 0.26, 0.03), (f * 2.918, 0.2, 0.026), (f * 3.5, 0.14, 0.02), (f * 4.06, 0.1, 0.016)], r)
    drop = d.pitch_drop_sine(dur, f, 1.18, 0.005, r) * d.env_exp(n, 0.05)
    click = d.bandpass(d.noise(dur, r), 1800, 8000, 2) * d.env_exp(n, 0.0035) * 2.2
    stick = clip_len(d.highpass(pick("drum_sticks", seed, 10), 900, 2), 0.09, 0.04)
    x = modes * 0.55 + drop * 0.5 + click + d.pad_to(stick, n) * 0.8
    if short:
        x *= d.env_exp(n, 0.06)
    return _vel_tone(x, vel, 2200, 12000)


def janggu_gi(vel: float = 0.4, seed: int = 0) -> np.ndarray:
    """기덕의 '기' — 채편 약한 앞꾸밈."""
    return janggu_deok(vel * 0.45, seed + 77, short=True)


def janggu_deong(vel: float = 1.0, seed: int = 0) -> np.ndarray:
    """덩 = 쿵 + 덕 동시(채편 2ms 늦게: 실제 양손 미세 차이)."""
    k = janggu_kung(vel, seed)
    t = janggu_deok(vel * 0.92, seed)
    return d.mix((k, 0.0, 0.0), (t, 0.002, -0.5))


def janggu_roll(length: float, vel: float = 0.7, seed: int = 0, rate: float = 22.0) -> np.ndarray:
    """더러러러 — 열채 굴림. rate 타/초, 점점 여리게(마지막 살짝 살림)."""
    r = rng(3000 + seed)
    k = max(3, int(length * rate))
    parts = []
    for i in range(k):
        u = i / max(1, k - 1)
        v = vel * (0.85 - 0.45 * u + 0.12 * r.uniform(-1, 1))
        parts.append((janggu_deok(max(0.08, v), seed * 31 + i, short=True), i / rate + r.uniform(-0.002, 0.002), 0.0))
    return d.mix(*parts)


# ================================================================ 북 (대북 / 소리북)
def daebuk(vel: float = 1.0, seed: int = 0) -> np.ndarray:
    """대북(산신 레이어) — 35~250Hz, 깊은 '둥'."""
    r = rng(4000 + seed)
    dur = 1.4
    n = n_of(dur)
    f0 = 56 * semis(r.uniform(-0.2, 0.2))
    body = d.pitch_drop_sine(dur, f0, 1.7, 0.03, r) * d.env_exp(n, 0.5, 0.002)
    m2 = d.modal(dur, [(f0 * 1.5, 0.3, 0.22), (f0 * 2.0, 0.15, 0.15), (f0 * 2.44, 0.08, 0.1)], r)
    beat = d.lowpass(d.noise(dur, r), 1100, 2) * d.env_exp(n, 0.014) * 0.9
    smp = d.resample(pick("drum_hits_low", seed + 3), 0.78)
    smp = clip_len(d.lowpass(smp, 1800, 2), dur, 0.3)
    x = body + m2 + beat + smp * 0.6
    return _vel_tone(x, vel, 500, 4000)


def soribuk(vel: float = 1.0, seed: int = 0, part: str = "buk") -> np.ndarray:
    """소리북 — part='buk' 가죽 '쿵', 'tak' 북통(나무) '딱'."""
    r = rng(5000 + seed)
    if part == "tak":
        w = clip_len(pick("wood_blocks", seed, 8), 0.18, 0.05)
        w = d.peq(d.resample(w, 0.8), 900, 4, 1.0)
        body = d.modal(0.18, [(520, 0.4, 0.04), (1130, 0.2, 0.025)], r)
        return _vel_tone(d.pad_to(w, len(body)) + body, vel, 2500, 10000)
    dur = 0.6
    n = n_of(dur)
    f0 = 128 * semis(r.uniform(-0.2, 0.2))
    body = d.pitch_drop_sine(dur, f0, 1.35, 0.012, r) * d.env_exp(n, 0.17)
    modes = d.modal(dur, [(f0 * 1.6, 0.3, 0.07), (f0 * 2.2, 0.15, 0.05)], r)
    smp = clip_len(pick("drum_hits_dry", seed), dur, 0.2)
    slap = d.bandpass(d.noise(dur, r), 500, 4000, 2) * d.env_exp(n, 0.006)
    return _vel_tone(body + modes + smp * 0.6 + slap * 0.6, vel, 1500, 9000)


# ================================================================ 징
def jing(vel: float = 1.0, seed: int = 0, dur: float = 7.0, muted: bool = False) -> np.ndarray:
    """징(용왕 레이어) — 큰 놋쇠 징. 부드러운 채(헝겊 감은 채) → 공격 무름, 긴 '징~' 여운과 맥놀이."""
    r = rng(6000 + seed)
    if muted:
        dur = 0.9
    n = n_of(dur)
    f0 = 148 * semis(r.uniform(-0.15, 0.15))  # D3(146.8) 근처 — 기준음 D 와 어울림
    modes = [(f0, 1.0, 3.4), (f0 * 1.0045, 0.75, 3.6), (f0 * 2.03, 0.42, 2.2), (f0 * 2.04, 0.3, 2.0),
             (f0 * 2.98, 0.3, 1.4), (f0 * 4.12, 0.2, 0.9), (f0 * 5.27, 0.12, 0.6), (f0 * 6.6, 0.07, 0.4)]
    tone = d.modal(dur, modes, r, glide=0.012, glide_tau=0.5)  # 타격 후 살짝 올라가는 '우웅'
    bloom = np.clip(d.t_axis(n) / 0.06, 0, 1) * (1 + 0.25 * np.exp(-((d.t_axis(n) - 0.35) / 0.25) ** 2))
    mallet = d.lowpass(d.noise(dur, r), 500, 2) * d.env_exp(n, 0.02) * 0.6
    smp = d.resample(pick("gong_qubodup", 0), 148 / 201 * 1.0)
    smp = d.pad_to(smp, n) * np.exp(-d.t_axis(n) / (dur * 0.5))
    x = tone * bloom * 0.8 + mallet + d.lowpass(smp, 3500, 2) * 0.55
    if muted:
        x *= d.env_exp(n, 0.18)
    return d.fade(_vel_tone(x, vel, 1200, 5000), 0, 0.3)


# ================================================================ 꽹과리
def kkwaenggwari(kind: str = "gaeng", vel: float = 1.0, seed: int = 0) -> np.ndarray:
    """꽹과리(칠성 레이어) — 2~9kHz 고역 금속. kind: gaeng(갱, 열림) / gaen(갠, 짧게) / ji(지, 막음)."""
    r = rng(7000 + seed)
    dur = {"gaeng": 1.1, "gaen": 0.35, "ji": 0.09}[kind]
    n = n_of(dur)
    f0 = 1046 * semis(r.uniform(-0.2, 0.2))
    ratios = [1.0, 1.52, 2.08, 2.63, 3.17, 3.86, 4.61, 5.33, 6.12, 7.0]
    modes = [(f0 * q, 1.0 / (1 + 0.35 * i), 0.9 / (1 + 0.6 * i)) for i, q in enumerate(ratios)]
    tone = d.modal(dur, modes, r)
    strike = d.bandpass(d.noise(dur, r), 3000, 12000, 2) * d.env_exp(n, 0.003) * 1.5
    smp = pick("gong_korean_cdrk", 0)
    smp = d.pad_to(d.resample(smp, semis(r.uniform(-0.4, 0.4))), n)
    x = tone * 0.5 + strike + smp * 0.75
    damp = {"gaeng": 0.45, "gaen": 0.09, "ji": 0.018}[kind]
    x = x * d.env_exp(n, damp)
    if kind == "ji":
        x = d.lowpass(x, 6000, 2) * 0.8
    return d.fade(d.highpass(_vel_tone(x, vel, 5000, 14000), 700, 3), 0, 0.01)


# ================================================================ 제금(바라)
def jegeum(kind: str = "chak", vel: float = 1.0, seed: int = 0) -> np.ndarray:
    """제금(제석·대감 레이어) — chak(맞부딪침), mak(막음), shimmer(문지름 쉬머 0.8s)."""
    r = rng(8000 + seed)
    if kind == "shimmer":
        dur = 1.0
        nz = d.bandpass(d.noise(dur, r), 4000, 13000, 2)
        e = d.env_ar(n_of(dur), 0.45, 0.5, 1.5)
        return nz * e * vel * 0.9
    if kind == "mak":
        x = pick("crash_mute", 0)
        return clip_len(x, 0.25, 0.08) * vel
    a = pick("crash_thrashed20" if seed % 2 == 0 else "crash_thin16", 0)
    b = pick("splash_6", 0)
    x = d.mix((a, 0.0, 0.0), (b, 0.006, -6.0))  # 두 장 맞부딪침
    x = d.highpass(x, 600, 2)
    return d.fade(_vel_tone(x, vel, 6000, 16000), 0, 0.2)


# ================================================================ 방울·풍경·놋그릇
def bangul(freq: float = 2 * D4 * 2, vel: float = 1.0, seed: int = 0, dur: float = 1.4, jingle: float = 0.5) -> np.ndarray:
    """무녀 방울 '딸랑' — 작은 놋쇠 방울(기준음 D 계열). freq=주 공명."""
    r = rng(9000 + seed)
    n = n_of(dur)
    modes = [(freq, 1.0, 0.55), (freq * 2.32, 0.45, 0.3), (freq * 4.25, 0.28, 0.18), (freq * 6.63, 0.16, 0.1),
             (freq * 1.003, 0.6, 0.6)]
    tone = d.modal(dur, modes, r, phase=0.0)
    click = d.bandpass(d.noise(dur, r), 4000, 12000, 2) * d.env_exp(n, 0.002)
    sl = d.pad_to(mureong(d.highpass(pick("sleigh_bells", seed, 8), 2500, 2), 0.2), n)
    x = tone * 0.6 + click * 0.8 + sl * jingle
    return d.fade(_vel_tone(x, vel, 4000, 15000), 0, 0.1)


def mureong(x: np.ndarray, sec: float = 0.25) -> np.ndarray:
    """썰매방울 원샘플 → 무령(무녀 방울 묶음) 음색(2026-11-24 리뷰): 6kHz 위 -6dB(쨍한 징글 고역 감쇄) +
    흔들림 한 번을 0.25s 안으로 자른다(길게 이어지는 '징글' 꼬리가 크리스마스 썰매를 연상시킨다)."""
    x = d.shelf(x, 6000, -6.0, high=True)
    return clip_len(x, min(sec, 0.25), min(0.1, sec * 0.45))


def bangul_shake(dur: float = 0.6, vel: float = 1.0, seed: int = 0) -> np.ndarray:
    """방울 묶음 흔들기(무구 방울 오라·신장대 방울). 무령 손목 흔들기 = 0.12~0.2s 짧은 '촤랑'을 엇박으로 이어 붙인다
    (한 번이 0.25s 를 넘지 않는다 — 긴 연속 징글 금지)."""
    r = rng(9300 + seed)
    n = n_of(dur)
    out = np.zeros(n)
    t, k, g = 0.0, 0, 1.0
    while t < dur - 0.04:
        ln = min(r.uniform(0.12, 0.2), dur - t)
        x = mureong(d.highpass(pick("sleigh_bells", seed + k), 1500, 2), ln)
        a = n_of(t)
        m = min(len(x), n - a)
        out[a:a + m] += x[:m] * g
        t += r.uniform(0.17, 0.26)
        k += 1
        g *= 0.82
    return d.fade(out * vel, 0.003, min(0.08, dur / 4))


def pungyeong(freq: float | None = None, vel: float = 1.0, seed: int = 0, dur: float = 3.0) -> np.ndarray:
    """풍경(처마 끝 바람종) — 맑은 단음. freq 주면 샘플을 그 음으로 재조율."""
    src = ["chime_single_02", "bell_1ring", "chime_single_04"][seed % 3]
    base = {"chime_single_02": 1221.0, "bell_1ring": 3167.0, "chime_single_04": 486.0 * 2}[src]
    x = pick(src, 0)
    if freq:
        x = d.resample(x, freq / base)
    x = clip_len(x, dur, 0.6)
    return d.highpass(x, 400, 2) * vel


def nokgeureut(vel: float = 1.0, seed: int = 0, dur: float = 4.0, pitch: float = 1.0) -> np.ndarray:
    """놋그릇(굿상 유기) '팅-웅' — 징 대용(징은 용왕 예약). 2026-11-24: 싱잉볼 샘플(긴 명상 서스테인)을 버리고
    놋쇠 사발 모드 합성 + 한국 손종(korean_bell) 한 옥타브 아래 + 채 타격음. 저역 -6dB, 짧은 감쇠(≤1.1s 시정수)."""
    r = rng(9500 + seed)
    n = n_of(dur)
    f0 = 620.0 * pitch * semis(r.uniform(-0.3, 0.3))
    tau = min(1.1, dur * 0.35)
    modes = [(f0, 1.0, tau), (f0 * 1.006, 0.5, tau * 1.1), (f0 * 2.71, 0.45, tau * 0.55),
             (f0 * 5.12, 0.22, tau * 0.3), (f0 * 8.05, 0.1, tau * 0.18)]
    tone = d.modal(dur, modes, r)
    bell = d.resample(pick("korean_bell", seed), 0.5 * pitch)
    bell = d.pad_to(bell, n) * np.exp(-d.t_axis(n) / (tau * 0.6))
    strike = d.bandpass(d.noise(dur, r), 1500, 7000, 2) * d.env_exp(n, 0.004)
    x = tone * 0.8 + bell * 0.45 + strike * 0.3
    x = d.shelf(x, 250, -6.0, high=False)
    return d.fade(x, 0, min(0.3, dur * 0.3)) * vel


# ================================================================ 관악·현악(합성 — 연희자 녹음 전 임시)
def _pitch_curve(notes, total: float, glide: float = 0.045):
    """notes: [(t0, dur, semitone_rel_D4, vel, orn)] → 샘플별 주파수·진폭 곡선.
    orn: '' / 'nong'(농음: 뒤쪽 비브라토) / 'kkeok'(꺾는목: 위에서 꺾어 내림) / 'chu'(추성: 끝 올림) / 'toe'(퇴성: 끝 내림)."""
    n = n_of(total)
    t = d.t_axis(n)
    semi = np.full(n, np.nan)
    amp = np.zeros(n)
    for (t0, du, st, v, orn) in notes:
        a, b = n_of(t0), min(n, n_of(t0 + du))
        if b <= a:
            continue
        tt = t[a:b] - t0
        s = np.full(b - a, float(st))
        if orn == "kkeok":
            s += 2.0 * np.exp(-tt / 0.06)
        if orn == "chu":
            s += 2.0 * np.clip((tt - du * 0.7) / (du * 0.3), 0, 1) ** 2
        if orn == "toe":
            s -= 2.0 * np.clip((tt - du * 0.65) / (du * 0.35), 0, 1) ** 2
        if orn in ("nong", "kkeok", ""):
            depth = (0.45 if orn == "nong" else 0.18) * np.clip((tt - du * 0.35) / max(0.05, du * 0.4), 0, 1)
            s += depth * np.sin(2 * np.pi * 5.2 * tt)
        semi[a:b] = s
        env = np.clip(tt / 0.035, 0, 1) * np.clip((du - tt) / 0.06, 0, 1)
        amp[a:b] = np.maximum(amp[a:b], env * v)
    # 빈 곳은 앞 음 유지(포르타멘토용), 시작 전은 첫 음
    idx = np.where(~np.isnan(semi))[0]
    if len(idx) == 0:
        return np.full(n, D4), amp
    semi[: idx[0]] = semi[idx[0]]
    valid = ~np.isnan(semi)
    last = np.maximum.accumulate(np.where(valid, np.arange(n), 0))
    semi = semi[last]
    # 포르타멘토 스무딩(1극, 벡터화: FFT 저역)
    semi = d.lowpass(semi - semi.mean(), 1 / (2 * np.pi * glide), 1) + semi.mean()
    return D4 * 2 ** (semi / 12), amp


def reed(notes, total: float, kind: str = "piri", seed: int = 0) -> np.ndarray:
    """겹서 관악 합성. kind='piri'(향피리: 굵고 따뜻) / 'taepyeongso'(호적: 밝고 코맹맹)."""
    r = rng(11000 + seed)
    f, a = _pitch_curve(notes, total)
    f = f * (1 + 0.0015 * d.lowpass(r.standard_normal(len(f)), 6, 1))  # 미세 흔들림
    w = d.saw_bl(f, 40, odd_bias=0.35 if kind == "piri" else 0.15)
    if kind == "piri":
        w = d.peq(d.peq(w, 1150, 9, 1.3), 2600, 5, 1.6)
        w = d.lowpass(d.highpass(w, 220, 2), 5200, 3)
    else:
        w = d.peq(d.peq(d.peq(w, 1500, 10, 1.4), 3100, 7, 1.8), 700, -4, 1.0)
        w = d.lowpass(d.highpass(w, 300, 2), 7500, 3)
    breath = d.bandpass(r.standard_normal(len(f)), 1200, 5000, 2) * 0.05
    x = (w / (np.abs(w).max() + 1e-9) + breath) * a
    return x


def daegeum(notes, total: float, seed: int = 0) -> np.ndarray:
    """대금(젓대) 합성 — 사인+약한 배음+숨소리, 청(갈대막) 울림은 고역 버즈로 근사."""
    r = rng(12000 + seed)
    f, a = _pitch_curve(notes, total, glide=0.06)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    cheong = d.bandpass(np.tanh(3 * np.sin(ph * 4)) * 0.3, 2500, 6000, 2) * 0.35
    breath = d.bandpass(r.standard_normal(len(f)), 600, 4500, 2) * 0.12
    return (tone * 0.7 + cheong + breath) * a


def haegeum(notes, total: float, seed: int = 0) -> np.ndarray:
    """해금 합성 — 찰현(활) 톱니 + 비음 포먼트 + 농현."""
    r = rng(13000 + seed)
    f, a = _pitch_curve(notes, total, glide=0.05)
    w = d.saw_bl(f, 40)
    w = d.peq(d.peq(w, 950, 7, 1.2), 2300, 6, 1.6)
    w = d.lowpass(d.highpass(w, 250, 2), 6000, 3)
    bow = d.bandpass(r.standard_normal(len(f)), 2000, 7000, 2) * 0.04
    return (w / (np.abs(w).max() + 1e-9) + bow) * a


def drone(total: float, semis_list=(-12, -5, 0), seed: int = 0, bright: float = 600.0) -> np.ndarray:
    """베드 저역 지속음(아쟁 지속음 + 현대 패드 근사). 루프용으로 시작=끝 위상 연속이 되도록 정수 주기."""
    n = n_of(total)
    t = d.t_axis(n)
    r = rng(14000 + seed)
    out = np.zeros(n)
    for k, st in enumerate(semis_list):
        f = D4 / 2 * semis(st)
        f = round(f * total) / total  # 루프 길이 안에 정수 주기
        for det in (-1, 0, 1):
            ff = f + det / total  # 루프 길이 안 정수 주기로 디튠 → 경계에서 위상 연속
            ph = 2 * np.pi * ff * t + r.uniform(0, 2 * np.pi)
            for h in range(1, 12):
                out += (1.0 / h) * np.sin(h * ph) * (0.6 if det else 1.0)
    out = d.lowpass(out, bright, 2)
    lfo = 1 + 0.15 * np.sin(2 * np.pi * (round(total / 8) / total) * t)
    return out * lfo
