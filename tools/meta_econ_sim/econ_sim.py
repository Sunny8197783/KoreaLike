"""SOULPATH meta-economy run-income model (v2, review fix).
Inputs mirror design/09-meta-economy.md 3.1 and data/meta_economy.json income.
- Kill curve = data/combat_core.json curves_assumption.kills_per_min (target kills/min, sum 4,360).
- Elites = data/waves_stage1.json elites (14 reserved slots) + salgi extra 0.05*floor(salgi/10) per slot.
- Salgi effect = continuous (05 3.4.1): spawn x(1+0.005*salgi). No cleansing (upper estimate).
- Currency unit values = 09 2.3/2.4 (09 owns them). Box contents are fixed 'confirmed extra'.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

def _load(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)

_cc = _load("data/combat_core.json")["curves_assumption"]
K = _cc["kills_per_min"]                                  # 20 values, minute 0..19
N20 = sum(K)                                              # 4,360
_w = _load("data/waves_stage1.json")
ELITE_SLOTS = []
for e in _w["elites"]:
    ELITE_SLOTS += [e["time_sec"]] * e["count"]          # 14 reserved
E20 = len(ELITE_SLOTS)

# ---- 09 unit values (base, before econ_price_scale; per-unit drops are never scaled)
NEOK = {"elite_neokham": 60, "wongwi_neokham": 80, "mboss_haewon": 300, "boss_han": 1500, "trial_gaho": 40}
YEOP = {"elite_box": 330, "wongwi_box": 440, "mboss_box": 1000, "boss_sal_boxes": 1800, "trial_wieom": 40}
EOULLIM = 0.15
BOW_MULT = 1.5
TRIAL_MULT_MAX = 0.5          # saja trial: B x (1 + 0.5 * p)
DWITJEON_TOECHI_SCALE = 0.2   # minute 19: mostly haewon (08 15.2)
WONGWI_PER_EVENT = 3
ECON_PRICE_SCALE = 2.1         # prices & one-time rewards are listed at scale 1.0 (09 3.1)
KILL_FEEDBACK = 0.0025       # half of the salgi spawn bonus (0.005/salgi) turns into kills

# arch: (normal haewon ratio, elite haewon ratio, ring share of cheondo, gaho share of trials, saja trial progress p)
ARCH = {
    "H": (0.90, 0.85, 0.35, 0.8, 0.0),
    "M": (0.50, 0.50, 0.30, 0.5, 0.80),
    "T": (0.10, 0.10, 0.15, 0.2, 0.85),
}

def run_income(arch, t_end=20.0, clear=True, skill=1.0, force_form=None):
    hr, ehr, rs, gaho, p_trial = ARCH[arch]
    salgi = 0.0
    hae = toe = 0.0
    e_hae = e_toe = 0.0
    w_hae = w_toe = 0.0
    wongwi_events = 0
    mb_hae = mb_toe = 0.0
    thresholds = [25, 50, 75]
    slots = sorted(ELITE_SLOTS)
    si = 0
    steps_per_min = 60
    t_end_s = t_end * 60
    for m in range(20):
        for s in range(steps_per_min):
            t = m * 60 + s
            if t >= t_end_s:
                break
            k = K[m] / 60.0 * skill * (1 + KILL_FEEDBACK * salgi)
            tr = (1 - hr) * (DWITJEON_TOECHI_SCALE if m == 19 else 1.0)
            hae += k * (1 - tr); toe += k * tr
            salgi += k * tr * 0.02
            while si < len(slots) and slots[si] <= t:
                n = 1 + 0.05 * int(salgi // 10)
                e_hae += n * ehr; e_toe += n * (1 - ehr); salgi += n * (1 - ehr)
                si += 1
            if t == 600:
                mb_hae += ehr; mb_toe += 1 - ehr; salgi += 5 * (1 - ehr)
            while thresholds and salgi >= thresholds[0]:
                thresholds.pop(0); wongwi_events += 1
                w = WONGWI_PER_EVENT
                wh = w * ehr * 0.6
                w_hae += wh; w_toe += w - wh; salgi += (w - wh)
    neok = hae * (2 + rs) + e_hae * NEOK["elite_neokham"] + w_hae * NEOK["wongwi_neokham"] + mb_hae * NEOK["mboss_haewon"]
    yeop = e_toe * YEOP["elite_box"] + w_toe * YEOP["wongwi_box"] + mb_toe * YEOP["mboss_box"]
    trials = min(5, int(t_end // 3)) + (1 if t_end >= 18 else 0)
    neok += trials * gaho * NEOK["trial_gaho"]
    yeop += trials * (1 - gaho) * YEOP["trial_wieom"]
    form = None
    if clear:
        form = force_form or ("han" if hr >= 0.55 else "sal" if hr <= 0.45 else ("sal" if salgi >= 50 else "han"))
        if form == "han": neok += NEOK["boss_han"]
        else: yeop += YEOP["boss_sal_boxes"]
    g, b = neok, yeop
    if 0.35 <= hr <= 0.65:
        g *= 1 + EOULLIM; b *= 1 + EOULLIM
    if clear:
        if form == "han": g *= BOW_MULT
        else: b *= 1 + TRIAL_MULT_MAX * p_trial
    return {"arch": arch, "t": t_end, "clear": clear, "form": form, "gongdeok": round(g), "bokjeon": round(b),
            "total": round(g + b), "salgi": round(salgi, 1), "elites": round(e_hae + e_toe, 1),
            "wongwi_events": wongwi_events, "haewon": round(hae), "toechi": round(toe)}

if __name__ == "__main__":
    print("N20", N20, "E20", E20)
    for a in "HMT":
        print(run_income(a))
    print(run_income("M", force_form="han"))
    print(run_income("M", force_form="sal"))
    for t in (5, 8, 10, 12, 15, 18):
        row = [run_income(a, t, clear=False) for a in "HMT"]
        print("death", t, [(r["gongdeok"], r["bokjeon"]) for r in row], row[1]["total"])
