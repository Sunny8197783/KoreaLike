"""gugak_dsp — numpy + ffmpeg 만으로 쓰는 오프라인 오디오 DSP 유틸 (scipy 불필요).

KoreaLike(넋길: 해원굿) 오디오 빌드 공용 모듈. build_jangdan.py / build_sfx.py 가 import 한다.
- 입출력: ffmpeg 파이프(f32le) — 디코드/OGG Vorbis 인코드
- 필터: 영위상 FFT 필터(버터워스 크기 응답), 피킹 EQ, 셸프
- 공간: 합성 노이즈 IR 컨볼루션 리버브(스테레오 비상관)
- 레벨: ITU-R BS.1770 K-가중 근사 라우드니스(LUFS), 피크 리미트
- 루프: 원형(circular) 렌더 버퍼 — 루프 끝을 넘는 꼬리를 앞쪽에 접어 더해 경계 클릭·무음 없이 이음
"""
from __future__ import annotations

import os
import subprocess
import numpy as np

SR = 44100
FFMPEG = os.environ.get("FFMPEG", "ffmpeg")


# ---------------------------------------------------------------- I/O
def load(path: str, sr: int = SR, mono: bool = True, start: float = 0.0, dur: float | None = None) -> np.ndarray:
    """ffmpeg 로 아무 포맷이나 float32 로 디코드. mono=False 면 (n,2)."""
    args = [FFMPEG, "-nostdin", "-loglevel", "error"]
    if start > 0:
        args += ["-ss", f"{start:.4f}"]
    if dur is not None:
        args += ["-t", f"{dur:.4f}"]
    args += ["-i", path, "-f", "f32le", "-ac", "1" if mono else "2", "-ar", str(sr), "-"]
    r = subprocess.run(args, capture_output=True, check=True)
    x = np.frombuffer(r.stdout, dtype=np.float32).astype(np.float64)
    if not mono:
        x = x.reshape(-1, 2)
    return x


def save(path: str, x: np.ndarray, sr: int = SR, quality: float = 5.0) -> None:
    """확장자로 포맷 결정(.ogg=libvorbis q, .flac, .wav). x: (n,) 또는 (n,2)."""
    x = np.asarray(x, dtype=np.float32)
    ch = 1 if x.ndim == 1 else x.shape[1]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    ext = os.path.splitext(path)[1].lower()
    codec = {".ogg": ["-c:a", "libvorbis", "-q:a", f"{quality:g}"],
             ".flac": ["-c:a", "flac"],
             ".wav": ["-c:a", "pcm_s16le"]}[ext]
    args = [FFMPEG, "-nostdin", "-y", "-loglevel", "error", "-f", "f32le", "-ac", str(ch), "-ar", str(sr),
            "-i", "-", *codec, "-map_metadata", "-1", path]
    subprocess.run(args, input=np.clip(x, -1, 1).tobytes(), check=True)


def ebur128(path: str) -> dict:
    """ffmpeg ebur128 로 통합 라우드니스(I)·트루피크 측정(검증용)."""
    r = subprocess.run([FFMPEG, "-nostdin", "-hide_banner", "-nostats", "-i", path, "-af",
                        "ebur128=peak=true:framelog=quiet", "-f", "null", "-"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = {}
    for line in r.stderr.splitlines():
        s = line.strip()
        if s.startswith("I:"):
            out["I"] = float(s.split()[1])
        elif s.startswith("Peak:"):
            out["TP"] = float(s.split()[1])
    return out


# ---------------------------------------------------------------- helpers
def t_axis(n: int, sr: int = SR) -> np.ndarray:
    return np.arange(n) / sr


def n_of(sec: float, sr: int = SR) -> int:
    return max(1, int(round(sec * sr)))


def db(x: float) -> float:
    return 10 ** (x / 20.0)


def to_stereo(x: np.ndarray, pan: float = 0.0) -> np.ndarray:
    """등전력 패닝. pan -1(좌)..+1(우)."""
    if x.ndim == 2:
        return x
    a = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * np.sqrt(2)


def mono(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=1) if x.ndim == 2 else x


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if len(x) >= n:
        return x[:n]
    shape = (n - len(x),) + x.shape[1:]
    return np.concatenate([x, np.zeros(shape)])


def mix(*parts) -> np.ndarray:
    """(신호, 시작초, 게인dB) 튜플 또는 신호들을 길이 맞춰 합산. 모노/스테레오 혼합 시 스테레오."""
    items = []
    for p in parts:
        if isinstance(p, tuple):
            sig, st, g = (p + (0.0, 0.0))[:3] if len(p) < 3 else p
            items.append((sig, st, g))
        else:
            items.append((p, 0.0, 0.0))
    stereo = any(s.ndim == 2 for s, _, _ in items)
    items = [(s, max(0.0, st), g) for s, st, g in items]
    n = max(int(round(st * SR)) + len(s) for s, st, _ in items)
    out = np.zeros((n, 2)) if stereo else np.zeros(n)
    for s, st, g in items:
        s = to_stereo(s) if stereo else s
        i = int(round(st * SR))
        out[i:i + len(s)] += s * db(g)
    return out


def fade(x: np.ndarray, fin: float = 0.0, fout: float = 0.003) -> np.ndarray:
    x = x.copy()
    a, b = n_of(fin) if fin > 0 else 0, n_of(fout) if fout > 0 else 0
    if a:
        w = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
        x[:a] *= w if x.ndim == 1 else w[:, None]
    if b:
        w = np.cos(np.linspace(0, np.pi / 2, b)) ** 2
        x[-b:] *= w if x.ndim == 1 else w[:, None]
    return x


def trim_silence(x: np.ndarray, thresh_db: float = -60.0, keep_tail: float = 0.01) -> np.ndarray:
    a = np.abs(mono(x))
    pk = a.max() + 1e-12
    idx = np.where(a > pk * db(thresh_db))[0]
    if len(idx) == 0:
        return x
    end = min(len(x), idx[-1] + n_of(keep_tail))
    return fade(x[:end], 0, 0.004)


def resample(x: np.ndarray, ratio: float) -> np.ndarray:
    """ratio>1 = 피치·속도 상승(테이프식). 선형보간(+사전 저역통과로 에일리어싱 억제)."""
    if abs(ratio - 1) < 1e-6:
        return x.copy()
    if ratio > 1:
        x = lowpass(x, 0.45 * SR / ratio, order=8)
    n = int(len(x) / ratio)
    src = np.arange(n) * ratio
    if x.ndim == 1:
        return np.interp(src, np.arange(len(x)), x)
    return np.stack([np.interp(src, np.arange(len(x)), x[:, c]) for c in range(x.shape[1])], axis=1)


def semis(st: float) -> float:
    return 2 ** (st / 12.0)


# ---------------------------------------------------------------- filters (zero-phase FFT)
def _apply_mag(x: np.ndarray, magfn) -> np.ndarray:
    n = len(x)
    nfft = 1 << int(np.ceil(np.log2(max(16, n))))
    f = np.fft.rfftfreq(nfft, 1 / SR)
    H = magfn(f)
    if x.ndim == 1:
        return np.fft.irfft(np.fft.rfft(x, nfft) * H, nfft)[:n]
    return np.stack([np.fft.irfft(np.fft.rfft(x[:, c], nfft) * H, nfft)[:n] for c in range(x.shape[1])], axis=1)


def lowpass(x, fc, order=4):
    return _apply_mag(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=4):
    return _apply_mag(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, lo, hi, order=4):
    return _apply_mag(x, lambda f: (1 / np.sqrt(1 + (f / hi) ** (2 * order))) *
                      (1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))))


def peq(x, fc, gain_db, q=1.0):
    """로그 주파수축 가우시안 피킹 EQ(영위상)."""
    bw = 1.0 / q

    def m(f):
        oc = np.log2(np.maximum(f, 1.0) / fc)
        return db(gain_db * np.exp(-0.5 * (oc / (bw / 2)) ** 2))
    return _apply_mag(x, m)


def shelf(x, fc, gain_db, high=True, slope=1.5):
    def m(f):
        r = np.log2(np.maximum(f, 1.0) / fc) * slope
        s = 1 / (1 + np.exp(-r * 3)) if high else 1 / (1 + np.exp(r * 3))
        return db(gain_db * s)
    return _apply_mag(x, m)


# ---------------------------------------------------------------- generators
_rng = np.random.default_rng(0)


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def noise(sec: float, r: np.random.Generator | None = None) -> np.ndarray:
    r = r or _rng
    return r.standard_normal(n_of(sec)) * 0.3


def env_exp(n: int, decay: float, attack: float = 0.0005) -> np.ndarray:
    t = t_axis(n)
    e = np.exp(-t / max(decay, 1e-4))
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def env_ar(n: int, attack: float, release: float, curve: float = 2.0) -> np.ndarray:
    t = t_axis(n)
    T = n / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1) ** curve
    r = np.clip((T - t) / max(release, 1e-4), 0, 1) ** curve
    return a * r


def sine_sweep(sec: float, f0: float, f1: float, curve: str = "exp", phase: float = 0.0) -> np.ndarray:
    n = n_of(sec)
    t = t_axis(n)
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / sec)
    else:
        f = f0 + (f1 - f0) * (t / sec)
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def pitch_drop_sine(sec: float, f_end: float, drop_ratio: float, tau: float, r=None) -> np.ndarray:
    """막(膜) 타악: 타격 직후 피치가 높았다가 f_end 로 지수 수렴."""
    n = n_of(sec)
    t = t_axis(n)
    f = f_end * (1 + (drop_ratio - 1) * np.exp(-t / tau))
    ph = (r.uniform(0, 2 * np.pi) if r is not None else 0.0)
    return np.sin(2 * np.pi * np.cumsum(f) / SR + ph)


def modal(sec: float, modes, r=None, glide: float = 0.0, glide_tau: float = 0.3, phase: float | None = None) -> np.ndarray:
    """모달 합성: modes = [(freq, amp, decay_s), ...]. 금속·막 공명. glide=상대 피치 변화(징 휨)."""
    n = n_of(sec)
    t = t_axis(n)
    out = np.zeros(n)
    r = r or _rng
    g = 1 + glide * (1 - np.exp(-t / glide_tau)) if glide else 1.0
    for fr, amp, dec in modes:
        if fr >= SR * 0.47:
            continue
        ph = r.uniform(0, 2 * np.pi) if phase is None else phase  # phase 고정 = 모든 모드 동위상(첫 프레임 최대)
        f = fr * g
        phase = 2 * np.pi * np.cumsum(f * np.ones(n)) / SR + ph if glide else 2 * np.pi * fr * t + ph
        out += amp * np.sin(phase) * np.exp(-t / dec)
    return out


def saw_bl(freq: np.ndarray, harmonics: int = 30, odd_bias: float = 0.0) -> np.ndarray:
    """주파수 배열(샘플별)로 대역제한 톱니/유사 리드 파형(가산 합성)."""
    ph = 2 * np.pi * np.cumsum(freq) / SR
    out = np.zeros_like(freq)
    fmax = freq.max()
    for k in range(1, harmonics + 1):
        if k * fmax > SR * 0.45:
            break
        a = 1.0 / k
        if k % 2 == 0:
            a *= (1 - odd_bias)
        out += a * np.sin(k * ph)
    return out


# ---------------------------------------------------------------- space
def reverb_ir(sec: float, decay: float, seed: int = 7, lp_hz: float = 7000, predelay: float = 0.012,
              stereo: bool = True) -> np.ndarray:
    r = rng(seed)
    n = n_of(sec)
    t = t_axis(n)
    chans = []
    for c in range(2 if stereo else 1):
        e = r.standard_normal(n) * np.exp(-t * 6.9 / decay)  # RT60=decay
        e = lowpass(e, lp_hz, 2)
        e[: n_of(predelay)] = 0
        chans.append(e / np.sqrt(np.sum(e ** 2) + 1e-12))
    return np.stack(chans, axis=1) if stereo else chans[0]


def convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    x2 = to_stereo(x) if ir.ndim == 2 else x
    n = len(x2) + len(ir) - 1
    nfft = 1 << int(np.ceil(np.log2(n)))
    if ir.ndim == 1:
        return np.fft.irfft(np.fft.rfft(x2, nfft) * np.fft.rfft(ir, nfft), nfft)[:n]
    return np.stack([np.fft.irfft(np.fft.rfft(x2[:, c], nfft) * np.fft.rfft(ir[:, c], nfft), nfft)[:n]
                     for c in range(2)], axis=1)


_IR_CACHE: dict = {}


def reverb(x: np.ndarray, wet_db: float = -12.0, decay: float = 1.6, lp_hz: float = 6500, seed: int = 7,
           tail: bool = True) -> np.ndarray:
    key = (round(decay, 3), lp_hz, seed)
    if key not in _IR_CACHE:
        _IR_CACHE[key] = reverb_ir(decay * 1.2, decay, seed, lp_hz)
    ir = _IR_CACHE[key]
    wet = convolve(x, ir) * db(wet_db)
    dry = to_stereo(x)
    out = pad_to(dry, len(wet)) + wet
    return out if tail else out[: len(x)]


def circular_reverb(x: np.ndarray, wet_db: float, decay: float, lp_hz: float = 6500, seed: int = 7) -> np.ndarray:
    """루프용: 꼬리를 루프 앞쪽으로 접어 더한다(경계 무손실)."""
    L = len(x)
    y = reverb(x, wet_db, decay, lp_hz, seed)
    return fold(y, L)


def fold(y: np.ndarray, L: int) -> np.ndarray:
    """길이 L 원형 버퍼로 접기."""
    out = y[:L].copy()
    i = L
    while i < len(y):
        seg = y[i:i + L]
        out[: len(seg)] += seg
        i += L
    return out


# ---------------------------------------------------------------- level
def _kweight(x: np.ndarray) -> np.ndarray:
    """BS.1770 K-가중(고역 셸프 +4dB@~1.7k, RLB 고역통과 ~38Hz) 크기 응답 근사."""
    def m(f):
        f = np.maximum(f, 1e-3)
        hs = db(4.0) ** (1 / (1 + (1681.0 / f) ** 2))  # 부드러운 +4dB 셸프
        hp = (f / 38.0) ** 2 / np.sqrt(1 + (f / 38.0) ** 4)
        return hs * hp
    return _apply_mag(x, m)


def loudness(x: np.ndarray, gated: bool = True) -> float:
    """통합 라우드니스 LUFS 근사(400ms 블록, 75% 겹침, 절대 -70·상대 -10 게이트). 짧은 신호는 전체."""
    xs = x[:, None] if x.ndim == 1 else x  # 모노 = 1채널(ffmpeg ebur128 과 같은 기준)
    k = _kweight(xs)
    bl = n_of(0.4)
    hop = bl // 4
    if len(k) <= bl:
        ms = np.mean(k ** 2, axis=0).sum()
        return -0.691 + 10 * np.log10(ms + 1e-15)
    blocks = np.array([np.mean(k[i:i + bl] ** 2, axis=0).sum() for i in range(0, len(k) - bl + 1, hop)])
    lk = -0.691 + 10 * np.log10(blocks + 1e-15)
    if not gated:
        return -0.691 + 10 * np.log10(blocks.mean() + 1e-15)
    b = blocks[lk > -70]
    if len(b) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(b.mean()) - 10
    b2 = blocks[lk > max(rel, -70)]
    return -0.691 + 10 * np.log10(b2.mean() + 1e-15)


def short_term_max(x: np.ndarray) -> float:
    """최대 단기 라우드니스(3s 창) 근사. 3s 보다 짧으면 전체 = 활성 구간 라우드니스."""
    xs = x[:, None] if x.ndim == 1 else x
    k = _kweight(xs)
    w = n_of(3.0)
    if len(k) <= w:
        a = np.abs(k).max(axis=1)
        # 활성 구간(피크 -40dB 이상)만
        idx = np.where(a > a.max() * db(-40))[0]
        seg = k[idx[0]: idx[-1] + 1] if len(idx) else k
        return -0.691 + 10 * np.log10(np.mean(seg ** 2, axis=0).sum() + 1e-15)
    hop = n_of(0.1)
    vals = [np.mean(k[i:i + w] ** 2, axis=0).sum() for i in range(0, len(k) - w + 1, hop)]
    return -0.691 + 10 * np.log10(max(vals) + 1e-15)


def limit(x: np.ndarray, ceiling_db: float = -1.0, release: float = 0.06, lookahead: float = 0.0015,
          circular: bool = False) -> np.ndarray:
    """간단한 룩어헤드 피크 리미터(샘플 피크). circular=True 면 루프 경계 래핑."""
    c = db(ceiling_db) * 0.98  # 인터샘플 여유
    a = np.abs(mono(x)) if x.ndim == 1 else np.abs(x).max(axis=1)
    need = np.minimum(1.0, c / np.maximum(a, 1e-12))
    if need.min() >= 1.0:
        return x
    la = n_of(lookahead)
    if circular:
        need_ext = np.concatenate([need, need[: la + 1]])
    else:
        need_ext = np.concatenate([need, np.ones(la + 1)])
    # 룩어헤드 구간 최소값
    from numpy.lib.stride_tricks import sliding_window_view
    gmin = sliding_window_view(need_ext, la + 1).min(axis=1)[: len(need)]
    # 릴리즈 스무딩(1극) — 파이썬 루프는 블록 단위 벡터화
    coef = np.exp(-1.0 / (release * SR))
    g = np.empty_like(gmin)
    prev = 1.0
    passes = 2 if circular else 1
    for _ in range(passes):
        for i in range(len(gmin)):
            v = gmin[i]
            prev = v if v < prev else v + (prev - v) * coef
            g[i] = prev
    return x * (g if x.ndim == 1 else g[:, None])


def normalize_lufs(x: np.ndarray, target: float, peak_db: float = -1.0, mode: str = "short") -> np.ndarray:
    L = short_term_max(x) if mode == "short" else loudness(x)
    y = x * db(target - L)
    pk = 20 * np.log10(np.abs(y).max() + 1e-12)
    if pk > peak_db:
        y = limit(y, peak_db)
    return y


def normalize_peak(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    return x * db(peak_db) / (np.abs(x).max() + 1e-12)


def dc_block(x: np.ndarray) -> np.ndarray:
    return highpass(x, 18, 2)


def saturate(x: np.ndarray, drive_db: float = 3.0) -> np.ndarray:
    """테이프식 부드러운 포화(병렬로 섞어 쓰기 권장)."""
    d = db(drive_db)
    return np.tanh(x * d) / np.tanh(d)
