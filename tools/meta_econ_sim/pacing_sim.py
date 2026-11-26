import random, statistics
from econ_sim import run_income, ECON_PRICE_SCALE

DAN_MULT = 0.05
STAGE_MULT = {"guksadang":1.0, "jindo":1.1, "east":1.2}
LOBBY_MIN = 3.0; CLEAR_EXTRA = 3.0

# (id, currency, cost, min_run_index condition)
W = [2000,2000,9000,9000,20000,20000,40000]   # base prices (x ECON_PRICE_SCALE in game)
ITEMS = []
# priority interleaving roughly how a player buys
pri = [
 ("wpn_r1a","B",2000,1),("wpn_w1a","G",2000,1),("char_baksu","G",5000,2),("char_dangol","G",5000,3),
 ("wpn_r1b","B",2000,1),("wpn_w1b","G",2000,1),("myd_t1_x4","G",5000,1),("myd_t1_y4","B",5000,1),
 ("gongsu1","B",2000,1),("mullim1","B",1500,1),("geumgi1","B",3000,1),
 ("wpn_r2a","B",9000,1),("wpn_w2a","G",9000,1),("char_simbang","G",20000,4),("char_myeongdu","G",20000,7),
 ("wpn_r2b","B",9000,1),("wpn_w2b","G",9000,1),("myd_t2_x4","G",15000,1),("myd_t2_y4","B",15000,1),
("gongsu2","B",6000,1),("geumgi2","B",8000,1),("mullim2","B",5000,1),
 ("wpn_r3a","B",20000,1),("wpn_w3a","G",20000,1),("hints","G",12000,1),
 ("myd_t1_x4b","G",5000,1),("myd_t1_y4b","B",5000,1),("myd_t2_x4b","G",15000,1),("myd_t2_y4b","B",15000,1),
 ("wpn_r3b","B",20000,1),("wpn_w3b","G",20000,1),("gongsu3","B",12000,1),("geumgi3","B",16000,1),
 ("myd_t3_x2","G",36000,1),("myd_t3_y2","B",36000,1),("mullim3","B",12000,1),
 ("wpn_r4","B",40000,1),("wpn_w4","G",40000,1),("shrine_l2_a","G",15000,1),("shrine_l2_b","G",15000,1),("shrine_l2_c","G",15000,1),("shrine_l2_d","G",15000,1),("shrine_l2_e","G",15000,1),("shrine_l2_f","G",15000,1),
 ("gongsu4","B",22000,1),("geumgi4","B",26000,1),("myd_t4_x2","G",64000,1),("myd_t4_y2","B",64000,1),
 ("gongsu5","B",36000,1),("geumgi5","B",40000,1),("shrine_l3_a","G",30000,1),("shrine_l3_a_jemul","B",20000,1),("shrine_l3_b","G",30000,1),("shrine_l3_b_jemul","B",20000,1),("shrine_l3_c","G",30000,1),("shrine_l3_c_jemul","B",20000,1),("shrine_l3_d","G",30000,1),("shrine_l3_d_jemul","B",20000,1),("shrine_l3_e","G",30000,1),("shrine_l3_e_jemul","B",20000,1),("shrine_l3_f","G",30000,1),("shrine_l3_f_jemul","B",20000,1),
]
import bisect
PTS=[(0,0),(1,4200),(5,47000),(10,105000),(20,200000),(30,262000),(40,310000),(50,341000),(60,357000)]
def onetime(h):
    for (h0,v0),(h1,v1) in zip(PTS,PTS[1:]):
        if h<=h1: return v0+(v1-v0)*(h-h0)/(h1-h0)
    return 357000
TOTAL_G = sum(c for _,cu,c,_ in pri if cu=="G"); TOTAL_B = sum(c for _,cu,c,_ in pri if cu=="B")

def simulate(seed, hours=60, arch="M"):
    rnd = random.Random(seed)
    t=0.0;k=0;dan=0;maxdan=0;clears=0
    sc={"guksadang":0,"jindo":0,"east":0}
    g=b=0.0; spentG=spentB=0; bought=[]; queue=list(pri)
    snap={}; marks=[1,5,10,20,30,40,50,60]
    first_clear_run=None
    og=[0.0]
    while t<hours*60:
        k+=1
        unlocked=["guksadang"]+(["jindo"] if sc["guksadang"] else [])+(["east"] if sc["jindo"] else [])
        st = unlocked[-1] if rnd.random()<0.65 else rnd.choice(unlocked)
        if k<=4:
            clear=False; tdeath=[8,10,12,15][k-1]; skill=0.8+0.04*k
        else:
            base=min(0.95,0.58+0.005*(k-5))
            p=base-0.066*dan-(0.20 if sc[st]==0 else 0)
            p=max(0.04,p)
            clear = rnd.random()<p or k==5
            tdeath=rnd.uniform(9,19.5); skill=min(1.05,0.9+0.003*k)
        if clear:
            r=run_income(arch,20,True,skill); dur=20+CLEAR_EXTRA+LOBBY_MIN
            clears+=1; sc[st]+=1
            if first_clear_run is None: first_clear_run=k
            if dan==maxdan and maxdan<15 and k>5: maxdan+=1
        else:
            r=run_income(arch,tdeath,False,skill); dur=tdeath+1+LOBBY_MIN
        mult=(1+DAN_MULT*dan)*STAGE_MULT[st]
        g+=r["gongdeok"]*mult/ECON_PRICE_SCALE; b+=r["bokjeon"]*mult/ECON_PRICE_SCALE
        # player plays at maxdan most of the time, sometimes 1 lower
        dan = maxdan if rnd.random()<0.8 else max(0,maxdan-1)
        # buy greedily in priority order (skip unaffordable items whose currency differs)
        changed=True
        while changed:
            changed=False
            for it in list(queue):
                iid,cu,c,mk=it
                if k<mk: continue
                if cu=="G" and g-spentG>=c: spentG+=c; bought.append(iid); queue.remove(it); changed=True; break
                if cu=="B" and b-spentB>=c: spentB+=c; bought.append(iid); queue.remove(it); changed=True; break
                # block: stop at first unaffordable of each currency? allow skipping
            
        t+=dur
        ot=onetime(t/60.0); g+=ot/2-og[0]/2; b+=ot/2-og[0]/2; og[0]=ot
        for m in marks:
            if m not in snap and t>=m*60:
                snap[m]=dict(runs=k,clears=clears,maxdan=maxdan,g=round(g),b=round(b),
                             pctG=round(spentG/TOTAL_G*100),pctB=round(spentB/TOTAL_B*100),nbought=len(bought),
                             stages=sum(1 for v in sc.values() if v), fc=first_clear_run, bought=list(bought))
    return snap

res=[simulate(s) for s in range(400)]
print("TOTAL_G",TOTAL_G,"TOTAL_B",TOTAL_B)
for m in [1,5,10,20,30,40,50,60]:
    out={}
    for key in ["runs","clears","maxdan","g","b","pctG","pctB","nbought","stages"]:
        out[key]=statistics.median(r[m][key] for r in res)
    print(m,out)
# p10/p90 of maxdan at 50
print("maxdan@50 p10/p90", sorted(r[50]["maxdan"] for r in res)[40], sorted(r[50]["maxdan"] for r in res)[360])
print("maxdan@20 p10/p90", sorted(r[20]["maxdan"] for r in res)[40], sorted(r[20]["maxdan"] for r in res)[360])

import collections
r=res[7]
for m in [1,5,20,50]:
    print(m, r[m]["runs"], r[m]["maxdan"], r[m]["bought"][-8:])
print("dan@50 dist", collections.Counter(x[50]["maxdan"] for x in res).most_common())
print("hours to 100%:")
