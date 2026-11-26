# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wdata
from analyze import levels

W = {w['id']: w for w in wdata.WEAPONS}
E = {e['id']: e for e in wdata.EVOS}
K = [30, 45, 60, 85, 100, 115, 140, 160, 180, 200, 215, 230, 260, 285, 310, 335, 360, 380, 420, 450]
RHO_T = {3: 0.10, 5: 0.15, 10: 0.30, 15: 0.40, 20: 0.50}
SP = {3: 1.05, 5: 1.1, 10: 1.3, 15: 1.6, 20: 1.9}
PLAN = {
    3: [('wpn_sinkal', 3), ('wpn_bangul', 2), ('wpn_gakgung', 1)],
    5: [('wpn_sinkal', 4), ('wpn_bangul', 3), ('wpn_gakgung', 2)],
    10: [('evo_sinjangkal', 0), ('wpn_bangul', 6), ('wpn_gakgung', 4), ('wpn_jijeon', 2), ('wpn_samjichang', 1)],
    15: [('evo_sinjangkal', 0), ('evo_cheoneum_bangul', 0), ('wpn_gakgung', 7), ('wpn_jijeon', 5), ('wpn_samjichang', 3), ('wpn_neokjeon', 2)],
    20: [('evo_sinjangkal', 0), ('evo_cheoneum_bangul', 0), ('evo_jusahwajeon', 0), ('wpn_jijeon', 8), ('wpn_samjichang', 6), ('wpn_neokjeon', 5)],
}
rows = []
for t, plan in PLAN.items():
    wdata.RHO = RHO_T[t]
    red = white = 0
    for wid, lv in plan:
        if wid.startswith('evo_'):
            e = E[wid]; b, c = e['model'](e['stats']); col = e['color']
        else:
            w = W[wid]; b, c = w['model'](levels(w)[lv - 1]); col = w['color']
        if col == 'red': red += c
        else: white += c
    red *= SP[t]; white *= SP[t]
    inflow = K[t - 1] / 60.0 * wdata.H(t)
    rows.append((t, RHO_T[t], SP[t], red, white, inflow, (red + white) / inflow))
    print(t, RHO_T[t], round(red), round(white), round(inflow, 1), round((red + white) / inflow, 2), plan)
