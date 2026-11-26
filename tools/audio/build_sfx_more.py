"""build_sfx_more.py — v1 SFX 보강 (KoreaLike / 넋길: 해원굿). 소유: audio.

build_sfx.py 의 레시피 레지스트리(R)·도구를 그대로 쓰고 아래를 추가/대체한 뒤 build_sfx.main 으로 굽는다.
  python -I tools/audio/build_sfx_more.py            # 이 파일의 레시피 전부
  python -I tools/audio/build_sfx_more.py sfx_sys_pungyeong

추가/대체(2026-11-22, 파일럿 승인 후 '타격감 우선'):
  1. 무구 적중음 20종 재설계 — 짧고 단단하게(기본 테이크 ≤ 0.22s, 첫 5ms 가 최대 진폭, 꼬리 컷), 무구마다 재료가 다르다.
     적(퇴치, 타 打): 비음정 노이즈·나무·가죽·쇠 + 저역 펀치.   백(해원 쪽, 柔): 종이·천·물·방울 — 더 가볍고 둥글게.
     집계 티어 __agg2/3/4 = 3/7/12개를 40ms 안에 흩뿌린 군집 테이크(build_sfx.agg).
  2. 빠져 있던 무구 발동음 12종(삼지창·작두·사인참사검·장창·편곤·철질려·호작도·넋전·길베·쑥물·소금·오방기).
  3. sfx_sys_pungyeong(해원 풍경 한 겹, D6, 4테이크) · sfx_amb_pungyeong(먼 풍경 원샷, 앰비언스)
  4. stg_bridge_gullim(거리 전환 굴림 브리지 3.0s — 장구 굴림 크레셴도 + 바람 라이저, 끝이 T 정각)
  5. sfx_sys_maedeup_lock(매듭 잠금 '툭' — 풀릴 기색 적에게 적 무구가 막힐 때)
예약 악기 준수(6.1): 징·대북·꽹과리·태평소·해금피리·제금은 쓰지 않는다(방울·장구·놋그릇·한지·무명천·나무·쇠).
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

_S0, sfx, agg, env_hit, hard_front, sub_drop, noise_sweep = B.S, B.sfx, B.agg, B.env_hit, B.hard_front, B.sub_drop, B.noise_sweep
D5, D6 = B.D5, B.D6
rev_swell, bell_tone = B.rev_swell, B.bell_tone


def S(key: str, i: int = 0, start: float = 0.0, dur: float | None = None, use: list | None = None) -> np.ndarray:
    """샘플 뱅크 구간 — 앞쪽 온셋 정렬(타격감: 첫 프레임이 가장 강하게)."""
    x = onset(_S0(key, i, start, None, use))
    return d.pad_to(x, n_of(dur)) if dur is not None else x
MORE: list = []


def more(sid: str, cls: str, note: str = "", loop: bool = False):
    MORE.append(sid)
    return sfx(sid, cls, note, loop)


def tight(x: np.ndarray, sec: float, fout: float = 0.03) -> np.ndarray:
    """길이 상한 + 꼬리 페이드(짧고 단단하게)."""
    return d.fade(d.pad_to(x, n_of(sec)), 0.0, min(fout, sec * 0.5))


def onset(x: np.ndarray, thr: float = 0.15) -> np.ndarray:
    """샘플 앞의 무음·완만한 시작을 잘라 첫 타격이 0ms 에 오게 한다(1ms 여유)."""
    a = np.abs(d.mono(x))
    if a.max() <= 0:
        return x
    i = int(np.argmax(a >= thr * a.max()))
    return x[max(0, i - n_of(0.001)):]


def click(sec: float, lo: float, hi: float, decay: float, seed: int, gain: float = 1.6) -> np.ndarray:
    n = n_of(sec)
    return d.bandpass(d.noise(sec, rng(seed)), lo, hi, 2) * env_hit(n, decay) * gain


def ping(sec: float, f: float, seed: int, dec: float = 0.05, partials=(1.0, 2.71, 5.1)) -> np.ndarray:
    modes = [(f * p, 1.0 / (k + 1), dec / (1 + 0.6 * k)) for k, p in enumerate(partials)]
    return d.modal(sec, modes, rng(seed), phase=0.0)


def hit_set(one, seeds=(1, 2, 5, 9), spread: float = 0.8) -> dict:
    """기본 테이크 + 집계 3티어."""
    a, b, c, e = seeds
    return {"": one(a), "__agg2": agg(lambda k: one(b * 10 + k), 3, .04, b, spread),
            "__agg3": agg(lambda k: one(c * 10 + k), 7, .04, c, spread), "__agg4": agg(lambda k: one(e * 10 + k), 12, .04, e, spread)}


# =================================================================== 적 무구 적중 (퇴치 계열, 비음정 '타')
def _sinkal_hit(k, use):          # 신칼: 종이칼 '싹' — 고역 클릭 + 한지 찢김 꼬리 짧게
    cut = d.highpass(S("paper_tear_b", k % 8, dur=0.1, use=use), 2200, 2) * env_hit(n_of(0.1), 0.025)
    return tight(hard_front(d.mix((click(0.12, 3000, 11000, 0.005, 200 + k), 0, 0), (cut, 0.002, -3),
                                  (sub_drop(0.12, 110, 1.6, .006, .03), 0, -9))), 0.16)


def _woldo_hit(k, use):           # 월도: 묵직한 '척' — 몸통 타격 + 반달날 쇠 울림(짧게) + 저역
    sm = d.lowpass(S("smack_body", k % 8, dur=0.2, use=use), 3500, 2) * env_hit(n_of(0.2), 0.05)
    ring = d.modal(0.2, [(620, .5, .05), (1530, .35, .035), (2410, .2, .025)], rng(220 + k))
    return tight(hard_front(d.mix((sm, 0, 0), (ring, 0, -9), (sub_drop(0.18, 72, 1.9, .008, .05), 0, -2))), 0.2)


def _samjichang_hit(k, use):      # 삼지창: 세 갈래 '폭-폭-폭' 미세 3연 관통 + 쇠끝 틱
    r = rng(300 + k)
    parts = [(click(0.06, 1500, 6000, 0.004, 310 + k * 3 + j, 1.4) + ping(0.06, 2350 * semis(r.uniform(-.5, .5)), 320 + k * 3 + j, 0.02) * 0.4,
              j * 0.007, -j * 2.5) for j in range(3)]
    body = d.lowpass(S("smacks", k % 8, dur=0.12, use=use), 2500, 2) * env_hit(n_of(0.12), 0.03)
    return tight(hard_front(d.mix(*parts, (body, 0.0, -6))), 0.15)


def _jakdu_hit(k, use):           # 작두: 지면 충격 '쾅' — 서브 + 흙 + 날 쇠 짧게
    dirt = d.lowpass(d.noise(0.2, rng(330 + k)), 900, 2) * env_hit(n_of(0.2), 0.04)
    blade = ping(0.15, 880 * semis(rng(331 + k).uniform(-.4, .4)), 332 + k, 0.03, (1.0, 2.4, 3.9))
    return tight(hard_front(d.mix((sub_drop(0.22, 55, 2.4, .01, .07), 0, 0), (dirt, 0, -4), (blade, 0.003, -10))), 0.22)


def _sainsageom_hit(k, use):      # 사인참사검: 검기 '챙' — 밝은 노이즈 칼끝 + 고역 핑(짧게)
    sl = d.highpass(S("whoosh_sword", k % 8, dur=0.08, use=use), 3500, 2) * env_hit(n_of(0.08), 0.02)
    return tight(hard_front(d.mix((click(0.1, 4000, 13000, 0.004, 340 + k, 1.8), 0, 0), (sl, 0, -6),
                                  (ping(0.14, 3100, 341 + k, 0.035), 0.001, -11))), 0.14)


def _gakgung_hit(k, use):         # 각궁: 화살 '퍽' — 나무 살대 꽂힘 + 둔탁
    thud = d.lowpass(S("smacks", (k + 3) % 8, dur=0.12, use=use), 2200, 2) * env_hit(n_of(0.12), 0.03)
    wood = d.bandpass(S("wood_blocks", k % 10, dur=0.06, use=use), 800, 4000, 2)
    return tight(hard_front(d.mix((thud, 0, 0), (wood, 0, -5), (sub_drop(0.1, 95, 1.6, .006, .025), 0, -6))), 0.13)


def _jangchang_hit(k, use):       # 장창: 연타 '탁' — 나무 자루 + 작은 쇠, 아주 짧게(연타 대비)
    wood = d.bandpass(S("wood_block_b", k % 10, dur=0.05, use=use), 600, 5000, 2)
    return tight(hard_front(d.mix((wood, 0, 0), (click(0.05, 2500, 9000, 0.003, 350 + k, 1.2), 0, -3),
                                  (ping(0.06, 1900, 351 + k, 0.015), 0, -12))), 0.09)


def _pyeongon_hit(k, use):        # 편곤: 쇠사슬 도리깨 '콱' — 둔중한 몸통 + 사슬 짤랑
    sm = d.lowpass(S("smack_body", (k + 4) % 8, dur=0.2, use=use), 2800, 2) * env_hit(n_of(0.2), 0.06)
    chain = d.highpass(S("coins", k % 12, dur=0.12, use=use), 2500, 2) * env_hit(n_of(0.12), 0.04)
    return tight(hard_front(d.mix((sm, 0, 0), (sub_drop(0.2, 62, 2.0, .008, .06), 0, -2), (chain, 0.012, -8))), 0.2)


def _cheoljillyeo_hit(k, use):    # 철질려: 마름쇠 '팅' — 작고 날카로운 쇠 찔림
    return tight(hard_front(d.mix((ping(0.08, 3600 * semis(rng(360 + k).uniform(-1, 1)), 361 + k, 0.018), 0, -2),
                                  (click(0.05, 5000, 14000, 0.002, 362 + k, 1.4), 0, 0))), 0.08)


def _hojakdo_hit(k, use):         # 호작도 세화: 경악 파동 '훙' — 낮은 가죽 펄스 + 한지 펄럭(공포·경직)
    pulse = d.pitch_drop_sine(0.22, 70, 1.8, 0.02, rng(370 + k)) * env_hit(n_of(0.22), 0.07)
    pap = d.highpass(S("paper_flap", k % 12, dur=0.1, use=use), 1500, 2) * env_hit(n_of(0.1), 0.03)
    return tight(hard_front(d.mix((pulse, 0, 0), (pap, 0.004, -7), (click(0.06, 800, 3000, 0.006, 371 + k, 1.0), 0, -6))), 0.2)


# =================================================================== 백 무구 적중 (해원 쪽, 柔 — 가볍고 둥글게)
def _bangul_hit(k, use):          # 방울: 음파 '찡' 작은 방울 틱
    sh = gi.mureong(d.highpass(S("sleigh_bells", k % 14, dur=0.08, use=use), 3500, 2), 0.08) * env_hit(n_of(0.08), 0.02)
    return tight(hard_front(d.mix((sh, 0, 0), (click(0.05, 3000, 9000, 0.004, 400 + k, 0.8), 0, -4))), 0.11)


def _buchae_hit(k, use):          # 부채: 바람 '훅' — 부드러운 공기 덩어리
    air = d.bandpass(d.noise(0.14, rng(410 + k)), 500, 3500, 2) * d.env_ar(n_of(0.14), 0.004, 0.12)
    pap = d.highpass(S("paper_flap", (k + 2) % 12, dur=0.08, use=use), 1200, 2) * env_hit(n_of(0.08), 0.025)
    return tight(hard_front(d.mix((pap, 0, 0), (air, 0, -2)), 2.0), 0.14)


def _neokjeon_hit(k, use):        # 넋전: 종이 인형 '삭' — 한지 스침
    pap = d.highpass(S("paper_rustle", k % 12, dur=0.09, use=use), 1800, 2) * env_hit(n_of(0.09), 0.025)
    return tight(hard_front(d.mix((pap, 0, 0), (click(0.04, 2500, 8000, 0.003, 420 + k, 0.7), 0, -5))), 0.1)


def _jijeon_hit(k, use):          # 지전: 종이돈 '팔락'
    pap = d.highpass(S("paper_flap", (k + 5) % 12, dur=0.1, use=use), 1500, 2) * env_hit(n_of(0.1), 0.03)
    coin = d.highpass(S("coins", (k + 3) % 12, dur=0.05, use=use), 4000, 2) * env_hit(n_of(0.05), 0.012)
    return tight(hard_front(d.mix((pap, 0, 0), (coin, 0, -12))), 0.11)


def _gilbe_hit(k, use):           # 길베: 흰 무명 '휙' 스침
    cl = d.bandpass(S("cloth_flap", k % 10, dur=0.12, use=use), 400, 6000, 2) * env_hit(n_of(0.12), 0.035)
    return tight(hard_front(d.mix((cl, 0, 0), (click(0.05, 1500, 5000, 0.004, 430 + k, 0.6), 0, -6))), 0.12)


def _ssukmul_hit(k, use):         # 쑥물: 물방울 '톡' — 정화수
    wd = d.pad_to(onset(S("water_drop", k % 8, dur=0.4, use=use)), n_of(0.12)) * env_hit(n_of(0.12), 0.04)
    return tight(hard_front(d.mix((wd, 0, 0), (ping(0.06, 1450 * semis(rng(440 + k).uniform(-1, 1)), 441 + k, 0.02, (1.0, 2.0)), 0, -10))), 0.12)


def _sogeum_hit(k, use):          # 소금: 소금 알갱이 '사각' 튐
    grain = d.highpass(S("bamboo_maraca", k % 10, dur=0.07, use=use), 3000, 2) * env_hit(n_of(0.07), 0.02)
    return tight(hard_front(d.mix((grain, 0, 0), (click(0.05, 5000, 14000, 0.003, 450 + k, 0.9), 0, -2))), 0.09)


def _myeongdu_hit(k, use):        # 명두: 놋거울 반사 '띵'
    return tight(hard_front(d.mix((ping(0.16, 2640 * semis(rng(460 + k).uniform(-.3, .3)), 461 + k, 0.05, (1.0, 2.76, 5.4)), 0, -3),
                                  (click(0.04, 4000, 12000, 0.003, 462 + k, 0.9), 0, 0))), 0.16)


def _janggu_hit(k, use):          # 장구: 충격파 맞음 '덕' — 채편 짧게
    return tight(hard_front(gi.janggu_deok(0.8, 470 + k, short=True)), 0.12)


def _obanggi_hit(k, use):         # 오방기: 오색 천 '팍' 펄럭
    cl = d.bandpass(S("cloth_flap", (k + 4) % 10, dur=0.1, use=use), 600, 5000, 2) * env_hit(n_of(0.1), 0.03)
    return tight(hard_front(d.mix((cl, 0, 0), (d.lowpass(S("smacks", k % 8, dur=0.05, use=use), 2000, 2), 0, -8))), 0.11)


HITS = {
    "sinkal": (_sinkal_hit, "신칼 적중 '싹' 집계 4티어"),
    "woldo": (_woldo_hit, "월도 적중 '척' 집계 4티어"),
    "samjichang": (_samjichang_hit, "삼지창 적중 '폭' 3연 관통 집계 4티어"),
    "jakdu": (_jakdu_hit, "작두 충격 '쾅' 집계 4티어"),
    "sainsageom": (_sainsageom_hit, "사인참사검 검기 '챙' 집계 4티어"),
    "gakgung": (_gakgung_hit, "각궁 화살 '퍽' 집계 4티어"),
    "jangchang": (_jangchang_hit, "장창 연타 '탁' 집계 4티어"),
    "pyeongon": (_pyeongon_hit, "편곤 '콱' + 사슬 집계 4티어"),
    "cheoljillyeo": (_cheoljillyeo_hit, "철질려 마름쇠 '팅' 집계 4티어"),
    "hojakdo": (_hojakdo_hit, "호작도 경악 파동 '훙' 집계 4티어"),
    "bangul": (_bangul_hit, "방울 음파 '찡' 집계 4티어"),
    "buchae": (_buchae_hit, "부채 바람 '훅' 집계 4티어"),
    "neokjeon": (_neokjeon_hit, "넋전 한지 '삭' 집계 4티어"),
    "jijeon": (_jijeon_hit, "지전 종이돈 '팔락' 집계 4티어"),
    "gilbe": (_gilbe_hit, "길베 무명 '휙' 집계 4티어"),
    "ssukmul": (_ssukmul_hit, "쑥물 물방울 '톡' 집계 4티어"),
    "sogeum": (_sogeum_hit, "소금 알갱이 '사각' 집계 4티어"),
    "myeongdu": (_myeongdu_hit, "명두 놋거울 '띵' 집계 4티어"),
    "janggu": (_janggu_hit, "장구 충격파 '덕' 집계 4티어"),
    "obanggi": (_obanggi_hit, "오방기 천 '팍' 집계 4티어"),
}


def _make_hit_recipe(name: str, fn, note: str):
    @more(f"sfx_wpn_{name}_hit", "L2", note)
    def _r(use, fn=fn):
        return hit_set(lambda k: fn(k, use))
    return _r


for _n, (_f, _note) in HITS.items():
    _make_hit_recipe(_n, _f, _note)


# =================================================================== 빠진 무구 발동음 (L2, ≤0.35s)
@more("sfx_wpn_samjichang", "L2", "삼지창 찌르기: 짧은 '쓱' 돌진 + 세 갈래 쇠 끝 반짝")
def wpn_samjichang(use):
    th = noise_sweep(0.2, 900, 3800, 0.5, 501, "rise")
    tip = d.mix(*[(ping(0.15, 2100 * semis(j * 2), 502 + j, 0.03), 0.16 + j * 0.006, -8 - j * 2) for j in range(3)])
    return {"": d.mix((th, 0, 0), (tip, 0, 0))}


@more("sfx_wpn_jakdu", "L2", "작두 설치: 날이 땅에 박히는 '척' + 쇠 떨림")
def wpn_jakdu(use):
    thud = d.lowpass(S("drum_hits_low", 2, dur=0.3, use=use), 600, 2) * env_hit(n_of(0.3), 0.08)
    ring = d.modal(0.35, [(740, .5, .12), (1810, .3, .08), (2960, .15, .05)], rng(511))
    return {"": hard_front(d.mix((thud, 0, 0), (ring, 0.004, -10), (sub_drop(0.3, 50, 2.2, .01, .1), 0, -3)))}


@more("sfx_wpn_sainsageom", "L2", "사인참사검 검기: 칼 뽑는 '스링' + 밝은 휘익")
def wpn_sainsageom(use):
    sw = d.highpass(S("whoosh_sword", 3, dur=0.32, use=use), 1500, 2)
    shing = d.modal(0.3, [(2950, .4, .12), (4420, .25, .08), (6100, .12, .05)], rng(521)) * d.env_ar(n_of(0.3), 0.03, 0.2)
    return {"": d.fade(d.mix((sw, 0, 0), (shing, 0.01, -9)), 0.005, 0.08)}


@more("sfx_wpn_jangchang", "L2", "장창 직선 연타: 짧은 '슉'")
def wpn_jangchang(use):
    return {"": d.fade(noise_sweep(0.16, 1200, 4200, 0.45, 531, "swell"), 0.002, 0.04)}


@more("sfx_wpn_pyeongon", "L2", "편곤 휘두름: 사슬 '찰랑' + 무거운 '부웅'")
def wpn_pyeongon(use):
    sw = d.fade(S("whoosh_heavy", 1, dur=0.38, use=use), 0.01, 0.12)
    chain = d.highpass(S("coins", 5, dur=0.25, use=use), 2200, 2) * d.env_ar(n_of(0.25), 0.02, 0.15)
    return {"": d.mix((sw, 0, 0), (chain, 0.04, -9))}


@more("sfx_wpn_cheoljillyeo", "L2", "철질려 살포: 마름쇠 흩뿌림 '차르륵'")
def wpn_cheoljillyeo(use):
    r = rng(541)
    parts = [(ping(0.08, 3200 * semis(r.uniform(-2, 2)), 542 + j, 0.02), r.uniform(0, 0.16), -r.uniform(2, 9)) for j in range(7)]
    return {"": hard_front(d.mix(*parts))}


@more("sfx_wpn_hojakdo", "L2", "호작도 세화 펼침: 한지 두루마리 '촤락' + 낮은 숨(호랑이 그림의 기세)")
def wpn_hojakdo(use):
    pap = d.fade(d.highpass(S("paper_flap", 7, dur=0.3, use=use), 900, 2), 0.004, 0.1)
    growl = d.lowpass(d.noise(0.35, rng(551)), 300, 3) * d.env_ar(n_of(0.35), 0.06, 0.2) * 1.4
    return {"": d.mix((pap, 0, 0), (growl, 0.03, -6))}


@more("sfx_wpn_neokjeon", "L2", "넋전 공전: 종이 인형 '사르륵'")
def wpn_neokjeon(use):
    return {"": d.fade(d.highpass(S("paper_rustle", 3, dur=0.3, use=use), 1500, 2), 0.02, 0.12)}


@more("sfx_wpn_gilbe", "L2", "길베 펼침: 흰 무명 '촤아' 길게 깔림")
def wpn_gilbe(use):
    cl = d.fade(d.bandpass(S("cloth_flap", 2, dur=0.34, use=use), 300, 7000, 2), 0.01, 0.15)
    air = noise_sweep(0.34, 600, 2200, 0.6, 561, "swell")
    return {"": d.mix((cl, 0, 0), (air, 0, -8))}


@more("sfx_wpn_ssukmul", "L2", "쑥물 바가지 뿌림: 물 '촤' + 방울 둘")
def wpn_ssukmul(use):
    spl = d.bandpass(d.noise(0.3, rng(571)), 800, 7000, 2) * d.env_ar(n_of(0.3), 0.01, 0.22)
    drops = d.mix((S("water_drop", 1, dur=0.2, use=use), 0.08, -4), (S("water_drop", 4, dur=0.2, use=use), 0.15, -7))
    return {"": d.mix((spl, 0, 0), (drops, 0, 0))}


@more("sfx_wpn_sogeum", "L2", "소금 결계: 소금 뿌림 '사르르' 원")
def wpn_sogeum(use):
    sh = d.fade(d.highpass(S("bamboo_maraca", 6, dur=0.32, use=use), 2500, 2), 0.02, 0.12)
    return {"": d.mix((sh, 0, 0), (noise_sweep(0.32, 4000, 9000, 0.4, 581, "swell"), 0, -10))}


@more("sfx_wpn_obanggi", "L2", "오방기 꽂음: 깃발 '펄럭' + 대나무 '탁'")
def wpn_obanggi(use):
    fl = d.fade(d.bandpass(S("cloth_flap", 6, dur=0.32, use=use), 300, 6000, 2), 0.005, 0.12)
    tak = d.bandpass(S("bamboo_hit", 1, dur=0.12, use=use), 400, 5000, 2) * env_hit(n_of(0.12), 0.04)
    return {"": hard_front(d.mix((tak, 0, 0), (fl, 0.02, -3)))}


# =================================================================== 의식 · 연출
@more("sfx_sys_pungyeong", "RIT", "해원 풍경 한 겹: 처마 바람종 D6 단음(런타임 토리 사다리 피치) — 방울 '딸랑' 위에 맑은 여운")
def sys_pungyeong(use):
    out = {}
    for v in range(4):
        x = gi.pungyeong(D6, 1.0, v, 2.2)
        use += ["chime_single", "bell_1ring"]
        tick = d.bandpass(d.noise(0.02, rng(600 + v)), 5000, 12000, 2) * env_hit(n_of(0.02), 0.002) * 0.6
        out["" if v == 0 else f"__v{v + 1}"] = d.reverb(hard_front(d.mix((x, 0, 0), (tick, 0, -10))), -14, 2.2, lp_hz=9000)
    return out


@more("sfx_amb_pungyeong", "L4", "먼 풍경 원샷(앰비언스): 바람에 두세 번 부딪는 처마 바람종, 멀리서")
def amb_pungyeong(use):
    out = {}
    for v in range(4):
        r = rng(620 + v)
        hits = [(gi.pungyeong(D6 * semis([0, 2, 5, 7, 9][(v + j * 2) % 5]), r.uniform(0.5, 0.9), v + j, 2.6),
                 j * r.uniform(0.18, 0.45), -j * 2.5) for j in range(2 + v % 2)]
        x = d.lowpass(d.mix(*hits), 6500, 2)
        use += ["chime_single", "bell_1ring"]
        out["" if v == 0 else f"__v{v + 1}"] = d.reverb(x, -6, 3.0, lp_hz=5000)
    return out


@more("stg_bridge_gullim", "STG", "굴림 브리지 3.0s: 장구 채편 굴림 크레셴도(가속) + 바람 라이저 → 끝 = 거리 경계 T 정각(착지는 stg_geori_land)")
def bridge_gullim(use):
    L = 3.0
    parts = []
    t = 0.0
    i = 0
    while t < L - 0.02:
        u = t / L
        rate = 9.0 + 19.0 * u ** 1.6               # 9 → 28 타/초 가속
        vel = 0.18 + 0.72 * u ** 1.3
        parts.append((gi.janggu_deok(vel, 700 + i, short=True), t, 0.0))
        t += 1.0 / rate
        i += 1
    roll = d.pad_to(d.mix(*parts), n_of(L))
    kung = d.mix(*[(gi.janggu_kung(0.35 + 0.15 * j, 760 + j), L - 1.0 + j * 0.33, -6) for j in range(3)])
    riser = noise_sweep(L, 300, 6000, 0.5, 771, "rise")
    sub = d.sine_sweep(L, 36.7, 73.4) * d.env_ar(n_of(L), L * 0.7, 0.01) * 0.25
    x = d.mix((roll, 0, 0), (d.pad_to(kung, n_of(L)), 0, 0), (riser, 0, -7), (sub, 0, -4))
    x = d.pad_to(x, n_of(L))
    return {"": d.fade(x, 0.15, 0.004)}


@more("sfx_sys_maedeup_lock", "L2", "매듭 잠금 '툭': 무명 매듭이 조여 적 무구를 막는다(나무 둔탁 + 천)")
def maedeup_lock(use):
    out = {}
    for v in range(2):
        knock = d.pad_to(onset(d.lowpass(S("wood_block_b", 3 + v, dur=0.3, use=use), 1800, 2)), n_of(0.1)) * env_hit(n_of(0.1), 0.03)
        cl = d.pad_to(onset(d.bandpass(S("cloth_flap", 7 + v, dur=0.3, use=use), 300, 3000, 2)), n_of(0.08)) * env_hit(n_of(0.08), 0.025)
        out["" if v == 0 else f"__v{v + 1}"] = tight(hard_front(d.mix((knock, 0, 0), (cl, 0, -5),
                                                                     (sub_drop(0.1, 120, 1.5, .006, .03), 0, -8))), 0.13)
    return out


# =================================================================== 이어하기(2026-11-23): 빠져 있던 순간들
@more("sfx_evo_reveal", "STG", "무구 진화·결합 공개 1.7s: 역재생 놋그릇 스웰 0.5s → 장구 덩 + 방울 토리 상행 화음(D-E-G-A-B) + 한지 펄럭")
def evo_reveal(use):
    swell = rev_swell(d.mix((gi.nokgeureut(1, 4, 3.0), 0, 0), (gi.bangul_shake(0.7, 0.7, 5), 0, -8)), 0.5)
    use += ["korean_bell", "sleigh_bells"]
    rise = noise_sweep(0.5, 500, 6000, 0.5, 811, "rise")
    chord = d.mix(*[(bell_tone(D5 * semis(st), 1.4, 1.0 - 0.08 * i, 820 + i, 0.3), 0.5 + i * 0.055, -i * 0.8)
                    for i, st in enumerate([0, 2, 5, 7, 9, 12])])
    flap = d.fade(d.bandpass(S("cloth_flap", 2, dur=0.3, use=use), 400, 7000, 2), 0.003, 0.15)
    x = d.mix((swell, 0, -3), (rise, 0, -8), (hard_front(gi.janggu_deong(1.0, 8)), 0.5, 0), (chord, 0, -2),
              (flap, 0.5, -8), (sub_drop(0.5, 36.7 * 2, 2.2, .02, .18), 0.5, -4))
    return {"": d.reverb(x, -12, 2.0)}


@more("sfx_plr_revive", "STG", "되살아남(명줄): 깊은 들숨 → 방울 상행 3음 + 장구 덩(따뜻하게)")
def plr_revive(use):
    br = rev_swell(d.bandpass(S("breath_deep", 1, dur=1.2, use=use), 200, 4000, 2), 0.6)
    bells = d.mix(*[(bell_tone(D5 * semis(st), 1.2, 0.9, 840 + i, 0.25), 0.6 + i * 0.11, -i) for i, st in enumerate([0, 7, 12])])
    return {"": d.reverb(d.mix((br, 0, -2), (gi.janggu_deong(0.9, 9), 0.6, -1), (bells, 0, -2)), -12, 2.0)}


@more("sfx_trl_avatar_telegraph", "L2", "화신 공격 예고 0.4s: 낮은 가죽 떨림이 올라오고 끝에 나무 '딱'(피하라는 신호 — 비음정)")
def trl_telegraph(use):
    out = {}
    for v in range(2):
        gr = d.sine_sweep(0.36, 70, 150) * d.env_ar(n_of(0.36), 0.3, 0.03) * 0.8
        ns = noise_sweep(0.36, 300, 2400, 0.6, 850 + v, "rise")
        tak = d.pad_to(onset(d.bandpass(S("wood_block_b", v, dur=0.2, use=use), 500, 6000, 2)), n_of(0.08)) * env_hit(n_of(0.08), 0.02)
        out["" if v == 0 else "__v2"] = tight(d.mix((gr, 0, -2), (ns, 0, -6), (hard_front(tak), 0.36, 0)), 0.46)
    return out


@more("sfx_sys_maetim", "RIT", "맺힘 복귀: 풀리던 매듭이 다시 조인다 — 무명 '끼익' 하행 + 둔탁한 '툭'(방울 없음 = 음이 꺼진다)")
def sys_maetim(use):
    cr = d.fade(d.bandpass(S("cloth_flap", 4, dur=0.4, use=use), 200, 2200, 2), 0.01, 0.2)
    dn = noise_sweep(0.35, 2200, 300, 0.5, 861, "fall")
    knock = d.pad_to(onset(d.lowpass(S("wood_block_b", 5, dur=0.3, use=use), 1400, 2)), n_of(0.12)) * env_hit(n_of(0.12), 0.035)
    return {"": d.mix((cr, 0, -4), (dn, 0, -5), (knock, 0.22, 0), (sub_drop(0.2, 90, 1.6, .01, .06), 0.22, -6))}


@more("sfx_sys_sal_drop", "L3", "살 덩어리 떨어짐: 축축하고 낮은 '둑'(비음정, 짧게)")
def sys_sal_drop(use):
    out = {}
    for v in range(2):
        th = d.lowpass(d.noise(0.12, rng(870 + v)), 500, 2) * env_hit(n_of(0.12), 0.03) * 1.5
        out["" if v == 0 else "__v2"] = tight(d.mix((sub_drop(0.16, 62, 1.8, .012, .05), 0, 0), (th, 0, -5)), 0.16)
    return out


if __name__ == "__main__":
    only = set(sys.argv[1:]) or set(MORE)
    B.main(only)
