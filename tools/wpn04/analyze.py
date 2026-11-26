# -*- coding: utf-8 -*-
import sys, copy, math
sys.path.insert(0, __import__('os').path.dirname(__file__))
from wdata import *

def levels(w):
    out = [copy.deepcopy(w['base'])]
    for desc, d in w['deltas']:
        s = copy.deepcopy(out[-1])
        for k, v in d.items():
            if isinstance(v, tuple):
                s[k] = v[1]
            else:
                s[k] = round(s.get(k, 0) + v, 4)
        out.append(s)
    return out

def k_band(k):
    # 균일 타격 k(=피해/최대한) 기준 결과
    if k >= 1: return '파열(1타)'
    n = math.ceil(0.65 / k - 1e-9)
    return ('파열(%d타)' % n) if n * k >= 1 - 1e-9 else ('풀릴(%d타)' % n)

if __name__ == '__main__':
    evo = {e['id']: e for e in EVOS}
    print('%-18s %6s %6s | %7s %7s | %7s %7s | %7s %7s' % ('id', 'col', '', 'L1b', 'L1c', 'L8b', 'L8c', 'Eb', 'Ec'))
    for w in WEAPONS:
        L = levels(w)
        b1, c1 = w['model'](L[0]); b8, c8 = w['model'](L[7])
        e = evo[w['evo']]; eb, ec = e['model'](e['stats'])
        print('%-18s %6s       | %7.1f %7.1f | %7.1f %7.1f | %7.1f %7.1f  x%.2f' % (w['id'], w['color'], b1, c1, b8, c8, eb, ec, ec / c8))
    for u in UNIONS:
        b, c = u['model'](u['stats'])
        print('%-34s | %7.1f %7.1f' % (u['id'], b, c))
