# -*- coding: utf-8 -*-
"""04-weapons-evolution 데이터 원본. 이 파일이 문서 표와 data/weapons.json의 단일 진실 원천."""
import math
INF = -1  # pierce 무한

RHO = 0.30      # 기준 밀도 (마리/유닛^2)
AOE_CAP = 40    # 1회 판정당 기대 타격 상한
ENEMY_R = 0.30  # 일반 잡귀 히트 반경(유닛)

def cap(x):
    return min(AOE_CAP, x)

def circle(r):
    return cap(RHO * math.pi * r * r)

def line(L, w, pierce=INF):
    n = RHO * L * (w + 2 * ENEMY_R)
    if pierce != INF:
        n = min(pierce, n)
    return cap(n)

def cone(r, deg):
    return cap(RHO * math.pi * r * r * deg / 360.0)

def ring_band(r, band=0.8):
    return cap(RHO * 2 * math.pi * r * band)

ZONE_OVERLAP = 0.7  # 같은 무구 장판 다중 투척 시 대상 중복 보정
TRAP_REAL = 0.45  # 함정 내구 실현율
CRIT_BASE = 0.05  # stat_gyeoldan 기본
CRIT_MULT = 2.0   # 결단타 배율(풀릴 기색 아닌 대상)

def critf(s):
    c = CRIT_BASE + s.get('crit', 0)
    return 1 + c * (CRIT_MULT - 1)

# ---------------------------------------------------------------------------
# 무구 정의. base = Lv1, deltas = Lv2..Lv8 (설명, {필드: 가산값 또는 ('=',값)})
# ---------------------------------------------------------------------------
WEAPONS = []

def W(**kw):
    WEAPONS.append(kw)

# ============================ 적(赤) 무구 10 ===============================
W(id='wpn_sinkal', name='신칼', hanja='神-', color='red', origin='巫', scope='v1',
  archetype='투척-회수(부메랑)', tags=['projectile', 'metal', 'return', 'auto_aim'],
  pair='psv_baekjisul', evo='evo_sinjangkal',
  targeting='가장 가까운 적(어둑시니 제외) 방향, 없으면 마지막 이동 방향',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('amt', '칼 수'), ('area', '사거리(u)'), ('pierce', '관통/구간'), ('spd', '속도(u/s)')],
  base=dict(dmg=9, cd=1.5, amt=1, area=5.0, pierce=2, spd=10.0, hitbox=0.4, hit_iv=0.0),
  deltas=[('칼 +1 (±12° 산개)', dict(amt=1)),
          ('피해 +2', dict(dmg=2)),
          ('관통 +2', dict(pierce=2)),
          ('사거리 +1.0, 쿨 −0.15', dict(area=1.0, cd=-0.15)),
          ('칼 +1', dict(amt=1)),
          ('피해 +4', dict(dmg=4)),
          ('관통 +2, 쿨 −0.15', dict(pierce=2, cd=-0.15))],
  limits=dict(max_active=12, min_period=0.5, amt_cap=8),
  amount_rule='신장 수 1당 칼 +1 (상한 8자루)',
  model=lambda s: (s['dmg'] * s['amt'] * 2 * critf(s) / s['cd'],
                   s['dmg'] * s['amt'] * 2 * line(s['area'], 2 * s['hitbox'] - 0.6 + 0.6, s['pierce']) * critf(s) / s['cd']),
)

W(id='wpn_woldo', name='월도', hanja='月刀', color='red', origin='巫', scope='v1',
  archetype='근접 360° 회전 베기', tags=['melee', 'aoe_self', 'knockback'],
  pair='psv_obangkkeun', evo='evo_manwoldo',
  targeting='무당 중심(조준 없음)',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('spins', '회전 수'), ('area', '반경(u)'), ('kb', '넉백(u)')],
  base=dict(dmg=12, cd=2.0, spins=1, area=1.8, kb=0.6, spin_time=0.4),
  deltas=[('피해 +4', dict(dmg=4)),
          ('반경 +0.3', dict(area=0.3)),
          ('쿨 −0.25', dict(cd=-0.25)),
          ('2회전(역방향, 0.15초 간격)', dict(spins=1)),
          ('피해 +5', dict(dmg=5)),
          ('반경 +0.3, 넉백 +0.3', dict(area=0.3, kb=0.3)),
          ('피해 +6, 쿨 −0.25', dict(dmg=6, cd=-0.25))],
  limits=dict(max_active=1, min_period=0.8, amt_cap=4),
  amount_rule='신장 수 1당 회전 1회 추가(60% 피해, 상한 +4회)',
  model=lambda s: (s['dmg'] * s['spins'] * critf(s) / s['cd'],
                   s['dmg'] * s['spins'] * cap(RHO * math.pi * (s['area'] ** 2 - 0.36)) * critf(s) / s['cd']),
)

W(id='wpn_samjichang', name='삼지창', hanja='三枝槍', color='red', origin='巫', scope='v1',
  archetype='3갈래 관통 찌르기 + 정예 표식', tags=['melee', 'line', 'mark'],
  pair='psv_sinjangdae', evo='evo_saseulchang',
  targeting='반경 4u 내 8방위 중 적이 가장 많은 방위',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('prongs', '갈래'), ('thrusts', '연속 찌르기'), ('area', '길이(u)'), ('mark', '표식 증폭')],
  base=dict(dmg=10, cd=1.6, prongs=3, thrusts=1, area=3.5, width=0.5, mark=0.15, amt=1),
  deltas=[('길이 +0.5', dict(area=0.5)),
          ('피해 +4', dict(dmg=4)),
          ('쿨 −0.2', dict(cd=-0.2)),
          ('2연속 찌르기(0.2초 간격)', dict(thrusts=1)),
          ('피해 +5', dict(dmg=5)),
          ('길이 +0.5, 표식 증폭 +10%p', dict(area=0.5, mark=0.10)),
          ('피해 +6, 쿨 −0.2', dict(dmg=6, cd=-0.2))],
  limits=dict(max_active=2, min_period=0.6, amt_cap=4),
  amount_rule='신장 수 1당 다음으로 적이 많은 방위에 찌르기 1세트 추가(상한 +4)',
  model=lambda s: (s['dmg'] * s['thrusts'] * min(s['prongs'], 2) * s['amt'] * (1 + s['mark']) * critf(s) / s['cd'],
                   s['dmg'] * s['thrusts'] * s['prongs'] * s['amt'] * line(s['area'], s['width']) * critf(s) / s['cd']),
)

W(id='wpn_jakdu', name='작두', hanja='斫刀', color='red', origin='巫', scope='v1',
  archetype='발밑 설치 + 무적 + 지면 충격파(저정기 역보정)', tags=['aoe_self', 'invuln', 'knockback', 'low_hp'],
  pair='psv_mubok', evo='evo_daejakdu',
  targeting='무당 발밑',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('area', '충격파 반경(u)'), ('invuln', '무적(초)'), ('lowhp_k', '저정기 계수')],
  base=dict(dmg=30, cd=4.0, area=2.5, invuln=0.5, lowhp_k=1.5, waves=1, kb=1.0),
  deltas=[('피해 +8', dict(dmg=8)),
          ('반경 +0.4', dict(area=0.4)),
          ('쿨 −0.5', dict(cd=-0.5)),
          ('저정기 계수 1.5→2.0', dict(lowhp_k=0.5)),
          ('피해 +10', dict(dmg=10)),
          ('반경 +0.4', dict(area=0.4)),
          ('피해 +12, 쿨 −0.5', dict(dmg=12, cd=-0.5))],
  limits=dict(max_active=1, min_period=2.0, amt_cap=2),
  amount_rule='신장 수 1당 0.4초 뒤 후속 충격파 1회(반경 ×1.2, 피해 50%, 상한 +2). 무적 시간은 늘지 않음',
  model=lambda s: (s['dmg'] * s['waves'] * critf(s) / s['cd'],
                   s['dmg'] * s['waves'] * circle(s['area']) * critf(s) / s['cd']),
)

W(id='wpn_sainsageom', name='사인참사검', hanja='四寅斬邪劍', color='red', origin='武', scope='v1',
  archetype='직선 관통 검기(정예·보스 추가 피해)', tags=['projectile', 'line', 'pierce_inf', 'anti_elite', 'auto_aim'],
  pair='psv_santong', evo='evo_isippalsugeom',
  targeting='10u 내 정예 이상 우선, 없으면 이동 방향',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('amt', '검기 수'), ('area', '사거리(u)'), ('width', '폭(u)'), ('elite', '정예+ 배율')],
  base=dict(dmg=18, cd=2.2, amt=1, area=8.0, width=0.8, spd=14.0, elite=1.5, pierce=INF),
  deltas=[('피해 +6', dict(dmg=6)),
          ('폭 +0.2', dict(width=0.2)),
          ('검기 +1(20° 부채꼴)', dict(amt=1)),
          ('쿨 −0.3', dict(cd=-0.3)),
          ('정예+ 배율 ×1.5→×1.8', dict(elite=0.3)),
          ('피해 +8', dict(dmg=8)),
          ('검기 +1, 쿨 −0.3', dict(amt=1, cd=-0.3))],
  limits=dict(max_active=9, min_period=0.8, amt_cap=6),
  amount_rule='신장 수 1당 검기 +1(부채꼴 20° 간격, 상한 6)',
  model=lambda s: (s['dmg'] * s['elite'] * min(s['amt'], 3) * critf(s) / s['cd'],
                   s['dmg'] * s['amt'] * line(s['area'], s['width']) * critf(s) / s['cd']),
)

W(id='wpn_gakgung', name='각궁', hanja='角弓', color='red', origin='武', scope='v1',
  archetype='최근접 자동 정밀 사격', tags=['projectile', 'metal', 'auto_aim', 'fast'],
  pair='psv_jusa', evo='evo_jusahwajeon',
  targeting='가장 가까운 적 n체(서로 다른 대상, 어둑시니 제외)',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('amt', '화살 수'), ('pierce', '관통'), ('area', '사거리(u)'), ('crit', '결단 가산')],
  base=dict(dmg=9, cd=0.9, amt=1, pierce=1, area=12.0, spd=18.0, crit=0.0),
  deltas=[('화살 +1', dict(amt=1)),
          ('피해 +3', dict(dmg=3)),
          ('관통 +1', dict(pierce=1)),
          ('쿨 −0.15', dict(cd=-0.15)),
          ('화살 +1', dict(amt=1)),
          ('피해 +4', dict(dmg=4)),
          ('관통 +1, 결단 +5%p', dict(pierce=1, crit=0.05))],
  limits=dict(max_active=40, min_period=0.3, amt_cap=10),
  amount_rule='신장 수 1당 화살 +1(상한 10)',
  model=lambda s: (s['dmg'] * s['amt'] * critf(s) / s['cd'],
                   s['dmg'] * s['amt'] * line(s['area'], 0.4, s['pierce']) * critf(s) / s['cd']),
)

W(id='wpn_jangchang', name='장창', hanja='長槍', color='red', origin='武', scope='v1',
  archetype='이동 방향 고속 직선 연타', tags=['melee', 'line', 'fast', 'move_dir'],
  pair='psv_mituri', evo='evo_pajinchang',
  targeting='현재(정지 시 마지막) 이동 방향',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('thrusts', '연타 수'), ('area', '길이(u)'), ('width', '폭(u)')],
  base=dict(dmg=6, cd=1.0, thrusts=3, area=4.0, width=0.4, amt=1, thrust_iv=0.1),
  deltas=[('연타 +1', dict(thrusts=1)),
          ('피해 +2', dict(dmg=2)),
          ('길이 +1.0', dict(area=1.0)),
          ('쿨 −0.15', dict(cd=-0.15)),
          ('연타 +1', dict(thrusts=1)),
          ('피해 +3', dict(dmg=3)),
          ('폭 +0.2, 쿨 −0.15', dict(width=0.2, cd=-0.15))],
  limits=dict(max_active=3, min_period=0.4, amt_cap=4),
  amount_rule='신장 수 1당 ±20° 방향 창 1자루 추가(상한 +4)',
  model=lambda s: (s['dmg'] * s['thrusts'] * s['amt'] * critf(s) / s['cd'],
                   s['dmg'] * s['thrusts'] * s['amt'] * line(s['area'], s['width']) * critf(s) / s['cd']),
)

W(id='wpn_pyeongon', name='편곤', hanja='鞭棍', color='red', origin='武', scope='v1',
  archetype='넓은 부채꼴 강타 + 넉백', tags=['melee', 'cone', 'knockback', 'move_dir'],
  pair='psv_myeongjusil', evo='evo_byeongnyeok_pyeongon',
  targeting='이동 방향 부채꼴',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('angle', '각도(°)'), ('area', '반경(u)'), ('kb', '넉백(u)'), ('back', '역타')],
  base=dict(dmg=18, cd=1.6, angle=120, area=2.6, kb=1.2, back=0, windup=0.15),
  deltas=[('피해 +6', dict(dmg=6)),
          ('각도 +30°', dict(angle=30)),
          ('쿨 −0.2', dict(cd=-0.2)),
          ('반경 +0.4', dict(area=0.4)),
          ('피해 +7', dict(dmg=7)),
          ('역타(반대 방향 70% 피해)', dict(back=1)),
          ('피해 +8, 넉백 +0.4', dict(dmg=8, kb=0.4))],
  limits=dict(max_active=2, min_period=0.7, amt_cap=3),
  amount_rule='신장 수 1당 0.2초 뒤 같은 방향 재타격 1회(50% 피해, 상한 +3)',
  model=lambda s: (s['dmg'] * critf(s) / s['cd'],
                   s['dmg'] * cone(s['area'], s['angle']) * (1 + 0.7 * s['back']) * critf(s) / s['cd']),
)

def _cj_model(s):
    active = s['amt'] * s['dur'] / s['cd']
    eff = s['amt'] if active <= s['max_act'] else s['max_act'] * s['cd'] / s['dur']
    crowd = s['dmg'] * eff * s['charges'] * TRAP_REAL * critf(s) / s['cd']
    boss = s['dmg'] * min(s['amt'], 2) * critf(s) / s['cd']
    return boss, crowd

W(id='wpn_cheoljillyeo', name='철질려', hanja='鐵蒺藜', color='red', origin='武', scope='v1',
  archetype='이동 경로 마름쇠 살포(봉박)', tags=['trap', 'metal', 'root', 'trail'],
  pair='psv_jeung', evo='evo_cheoljillyeojin',
  targeting='무당 뒤쪽 1.2u 반경 산포',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('amt', '마름쇠 수'), ('dur', '지속(초)'), ('charges', '내구(타)'), ('root', '봉박(초)'), ('max_act', '동시 상한')],
  base=dict(dmg=6, cd=1.2, amt=4, dur=6.0, charges=3, root=0.6, max_act=40, hitbox=0.35),
  deltas=[('마름쇠 +2', dict(amt=2)),
          ('피해 +2', dict(dmg=2)),
          ('지속 +2초', dict(dur=2.0)),
          ('내구 +2', dict(charges=2)),
          ('봉박 +0.3초', dict(root=0.3)),
          ('피해 +3', dict(dmg=3)),
          ('마름쇠 +2, 동시 상한 60', dict(amt=2, max_act=20))],
  limits=dict(max_active=60, min_period=0.5, amt_cap=12),
  amount_rule='신장 수 1당 마름쇠 +1(상한 +12). 동시 상한은 늘지 않음',
  model=_cj_model,
)

W(id='wpn_hojakdo', name='호작도 세화', hanja='虎鵲圖 歲畵', color='red', origin='畵', scope='v1',
  archetype='등 뒤 세화(까치호랑이 그림) 경악 파동(공포·경직)', tags=['aoe_self', 'fear', 'support', 'back'],
  pair='psv_chotdae', evo='evo_sangun_pohyodo',
  targeting='무당 중심 원형(등 뒤 반원 강화)',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('area', '반경(u)'), ('fear', '공포(초)'), ('fear_amp', '공포 대상 피해 증폭')],
  base=dict(dmg=4, cd=3.0, area=3.0, fear=1.5, fear_amp=0.0, stagger=0.3),
  deltas=[('반경 +0.5', dict(area=0.5)),
          ('피해 +3', dict(dmg=3)),
          ('공포 +0.5초', dict(fear=0.5)),
          ('쿨 −0.4', dict(cd=-0.4)),
          ('반경 +0.5', dict(area=0.5)),
          ('공포 대상 받는 피해 +10%', dict(fear_amp=0.10)),
          ('피해 +4, 쿨 −0.4', dict(dmg=4, cd=-0.4))],
  limits=dict(max_active=1, min_period=1.5, amt_cap=3),
  amount_rule='신장 수 1당 반경 +8%(상한 +24%)',
  model=lambda s: (s['dmg'] * critf(s) / s['cd'],
                   s['dmg'] * 1.5 * circle(s['area']) * critf(s) / s['cd']),
)

# ============================ 백(白) 무구 10 ===============================
W(id='wpn_bangul', name='방울', hanja='-', color='white', origin='巫', scope='v1',
  archetype='주변 지속 음파 오라(맥동)', tags=['aura', 'sound', 'finisher'],
  pair='psv_chohon_jeoksam', evo='evo_cheoneum_bangul',
  targeting='무당 중심 원형',
  cols=[('dmg', '피해/맥동'), ('cd', '맥동 간격(초)'), ('area', '반경(u)'), ('pull_slow', '풀릴 기색 추가 감속')],
  base=dict(dmg=3, cd=0.6, area=2.5, pull_slow=0.0),
  deltas=[('반경 +0.3', dict(area=0.3)),
          ('피해 +1', dict(dmg=1)),
          ('간격 −0.08', dict(cd=-0.08)),
          ('반경 +0.3', dict(area=0.3)),
          ('피해 +1', dict(dmg=1)),
          ('범위 내 풀릴 기색 이속 추가 −20%', dict(pull_slow=0.20)),
          ('피해 +2, 반경 +0.3', dict(dmg=2, area=0.3))],
  limits=dict(max_active=1, min_period=0.25, amt_cap=3),
  amount_rule='신장 수 1당 반경 +6%(상한 +18%)',
  model=lambda s: (s['dmg'] / s['cd'], s['dmg'] * circle(s['area']) / s['cd']),
)

W(id='wpn_buchae', name='부채', hanja='巫扇', color='white', origin='巫', scope='v1',
  archetype='전방 부채꼴 돌풍(넉백, 풀릴 기색은 끌어옴)', tags=['cone', 'knockback', 'pull', 'move_dir'],
  pair='psv_obangkkeun', evo='evo_irwolseonpung',
  targeting='이동 방향 부채꼴',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('angle', '각도(°)'), ('area', '반경(u)'), ('gusts', '연속 돌풍')],
  base=dict(dmg=6, cd=1.4, angle=90, area=3.5, gusts=1, kb=1.5),
  deltas=[('피해 +2', dict(dmg=2)),
          ('각도 +20°', dict(angle=20)),
          ('쿨 −0.2', dict(cd=-0.2)),
          ('반경 +0.5', dict(area=0.5)),
          ('피해 +2', dict(dmg=2)),
          ('2연 돌풍(0.25초 간격)', dict(gusts=1)),
          ('피해 +3, 각도 +20°', dict(dmg=3, angle=20))],
  limits=dict(max_active=2, min_period=0.5, amt_cap=3),
  amount_rule='신장 수 1당 각도 +15°(상한 +45°)',
  model=lambda s: (s['dmg'] * s['gusts'] / s['cd'], s['dmg'] * s['gusts'] * cone(s['area'], s['angle']) / s['cd']),
)

W(id='wpn_neokjeon', name='넋전', hanja='-錢', color='white', origin='巫', scope='v1',
  archetype='종이 넋 인형 공전', tags=['orbit', 'paper', 'duration'],
  pair='psv_wipae', evo='evo_neokkkotbi',
  targeting='무당 주위 공전',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('amt', '넋전 수'), ('dur', '지속(초)'), ('area', '공전 반경(u)'), ('omega', '각속도(°/s)')],
  base=dict(dmg=5, cd=4.0, amt=2, dur=3.0, area=2.0, omega=180, hit_iv=0.5),
  deltas=[('넋전 +1', dict(amt=1)),
          ('피해 +2', dict(dmg=2)),
          ('지속 +1.0', dict(dur=1.0)),
          ('공전 반경 +0.4, 각속도 +20%', dict(area=0.4, omega=36)),
          ('넋전 +1', dict(amt=1)),
          ('피해 +2', dict(dmg=2)),
          ('지속 +1.0, 넋전 +1', dict(dur=1.0, amt=1))],
  limits=dict(max_active=16, min_period=1.0, amt_cap=10),
  amount_rule='신장 수 1당 넋전 +1(상한 10)',
  model=lambda s: (s['dmg'] * s['amt'] * (s['omega'] / 360.0) * min(1, s['dur'] / s['cd']),
                   s['dmg'] * s['amt'] * min(RHO * math.radians(s['omega']) * s['area'] * 1.1, 1 / s['hit_iv'] * 2) * min(1, s['dur'] / s['cd'])),
)

def _jj_model(s):
    per = line(s['area'], 0.25, s['pierce'])
    avail = cone(s['area'], s['angle']) * 3
    hits = min(s['amt'] * per, avail)
    return s['dmg'] * s['amt'] / s['cd'], s['dmg'] * hits / s['cd']

W(id='wpn_jijeon', name='지전', hanja='紙錢', color='white', origin='巫', scope='v1',
  archetype='종이돈 산탄 투척', tags=['projectile', 'paper', 'spread', 'auto_aim'],
  pair='psv_yeopjeon', evo='evo_nojatdon',
  targeting='가장 가까운 적 방향 부채꼴(풀릴 기색 우선)',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('amt', '지전 수'), ('angle', '산개(°)'), ('area', '사거리(u)'), ('pierce', '관통')],
  base=dict(dmg=5, cd=1.3, amt=5, angle=40, area=5.0, pierce=1, spd=9.0),
  deltas=[('지전 +2', dict(amt=2)),
          ('피해 +2', dict(dmg=2)),
          ('관통 +1', dict(pierce=1)),
          ('쿨 −0.2', dict(cd=-0.2)),
          ('지전 +2, 산개 +10°', dict(amt=2, angle=10)),
          ('피해 +2', dict(dmg=2)),
          ('사거리 +1.5, 관통 +1', dict(area=1.5, pierce=1))],
  limits=dict(max_active=60, min_period=0.4, amt_cap=15),
  amount_rule='신장 수 1당 지전 +2(상한 15장)',
  model=_jj_model,
)

W(id='wpn_gilbe', name='길베', hanja='-', color='white', origin='巫', scope='v1',
  archetype='이동 방향 흰 천 직선 장판', tags=['zone', 'line', 'cloth', 'move_dir'],
  pair='psv_mituri', evo='evo_begareugi',
  targeting='이동 방향(Lv5부터 반대 방향 추가)',
  cols=[('dmg', '피해/0.5초'), ('cd', '쿨(초)'), ('amt', '천 수'), ('area', '길이(u)'), ('width', '폭(u)'), ('dur', '지속(초)'), ('slow', '감속')],
  base=dict(dmg=4, cd=2.0, amt=1, area=5.0, width=1.0, dur=2.0, slow=0.0, tick=0.5),
  deltas=[('길이 +1.5', dict(area=1.5)),
          ('피해 +2', dict(dmg=2)),
          ('지속 +1.0', dict(dur=1.0)),
          ('반대 방향 천 +1', dict(amt=1)),
          ('폭 +0.4', dict(width=0.4)),
          ('천 위 적 이속 −25%', dict(slow=0.25)),
          ('피해 +3, 쿨 −0.4', dict(dmg=3, cd=-0.4))],
  limits=dict(max_active=8, min_period=0.8, amt_cap=4),
  amount_rule='신장 수 1당 ±30° 방향 천 +1(상한 +4)',
  model=lambda s: (s['dmg'] * (s['dur'] / s['tick']) * 0.5 / s['cd'],
                   s['dmg'] * s['amt'] * cap(RHO * s['area'] * (s['width'] + 0.6)) * (s['dur'] / s['tick']) * 0.5 / s['cd']),
)

W(id='wpn_ssukmul', name='쑥물 바가지', hanja='-', color='white', origin='巫', scope='v1',
  archetype='정화수 투척 장판(지속 백 피해)', tags=['zone', 'water', 'throw'],
  pair='psv_jeonghwasu', evo='evo_sammul_ssitgim',
  targeting='반경 6u 내 표본 8점 중 적 밀도 최대 지점(풀릴 기색 가중 ×2)',
  cols=[('dmg', '피해/0.5초'), ('cd', '쿨(초)'), ('amt', '바가지 수'), ('area', '장판 반경(u)'), ('dur', '지속(초)')],
  base=dict(dmg=4, cd=3.5, amt=1, area=1.6, dur=3.0, slow=0.15, tick=0.5),
  deltas=[('바가지 +1', dict(amt=1)),
          ('피해 +1', dict(dmg=1)),
          ('반경 +0.3', dict(area=0.3)),
          ('지속 +1.0', dict(dur=1.0)),
          ('피해 +1', dict(dmg=1)),
          ('바가지 +1', dict(amt=1)),
          ('쿨 −0.5, 반경 +0.2', dict(cd=-0.5, area=0.2))],
  limits=dict(max_active=12, min_period=1.5, amt_cap=6),
  amount_rule='신장 수 1당 바가지 +1(상한 6)',
  model=lambda s: ((s['dmg'] / s['tick']) * min(1, s['dur'] / s['cd']),
                   s['dmg'] * s['amt'] * circle(s['area']) * (s['dur'] / s['tick']) * (1 if s['amt'] == 1 else ZONE_OVERLAP) / s['cd']),
)

W(id='wpn_sogeum', name='소금', hanja='-', color='white', origin='巫', scope='v1',
  archetype='원형 소금 결계(밀어내기) + 살 알갱이 정화', tags=['barrier', 'purify', 'knockback'],
  pair='psv_mubok', evo='evo_bujeong_gasim',
  targeting='무당 위치에 고정 설치',
  cols=[('dmg', '피해/0.5초'), ('cd', '쿨(초)'), ('area', '결계 반경(u)'), ('dur', '지속(초)'), ('purge', '정화 반경 배율')],
  base=dict(dmg=5, cd=5.0, area=2.2, dur=3.0, push=0.8, purge=1.0, purge_cap=20, tick=0.5),
  deltas=[('반경 +0.3', dict(area=0.3)),
          ('피해 +2', dict(dmg=2)),
          ('지속 +1.0', dict(dur=1.0)),
          ('쿨 −0.8', dict(cd=-0.8)),
          ('살 알갱이 정화 반경 ×1.5', dict(purge=0.5)),
          ('피해 +3', dict(dmg=3)),
          ('반경 +0.4, 쿨 −0.7', dict(area=0.4, cd=-0.7))],
  limits=dict(max_active=3, min_period=2.5, amt_cap=2),
  amount_rule='신장 수 1당 결계 안쪽에 반경 60% 동심 결계 1겹 추가(상한 +2)',
  model=lambda s: ((s['dmg'] / s['tick']) * 0.5 * min(1, s['dur'] / s['cd']),
                   s['dmg'] * ring_band(s['area']) * (s['dur'] / s['tick']) * 0.7 / s['cd']),
)

W(id='wpn_myeongdu', name='명두', hanja='明圖', color='white', origin='巫', scope='v1',
  archetype='공전 거울 + 광명 빛줄기(어둑시니 특효)', tags=['orbit', 'beam', 'light', 'anti_eodukssini', 'auto_aim'],
  pair='psv_baritdae', evo='evo_irwol_myeongdu',
  targeting='거울마다 7u 내 가장 가까운 적(어둑시니 최우선)',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('mirrors', '거울 수'), ('area', '빛줄기 길이(u)'), ('width', '폭(u)'), ('reflect', '반사'), ('dark', '어둑시니 축소/타')],
  base=dict(dmg=8, cd=1.6, mirrors=2, area=7.0, width=0.5, reflect=0, dark=0.04, orbit_r=2.5),
  deltas=[('피해 +3', dict(dmg=3)),
          ('빛줄기 길이 +1.5', dict(area=1.5)),
          ('쿨 −0.2', dict(cd=-0.2)),
          ('반사 1회(4u 내 다음 적)', dict(reflect=1)),
          ('폭 +0.2', dict(width=0.2)),
          ('피해 +4', dict(dmg=4)),
          ('쿨 −0.2, 어둑시니 축소 −4%→−6%', dict(cd=-0.2, dark=0.02))],
  limits=dict(max_active=12, min_period=0.5, amt_cap=4),
  amount_rule='신장 수 1당 거울 +1(상한 6개)',
  model=lambda s: (s['dmg'] * s['mirrors'] / s['cd'],
                   s['dmg'] * s['mirrors'] * (line(s['area'], s['width']) + 0.9 * s['reflect'] * 1.0) / s['cd']),
)

W(id='wpn_janggu', name='장구', hanja='杖鼓', color='white', origin='巫', scope='v1',
  archetype='주기적 전방위 음파 충격파 "덩"(박 머리 고정)', tags=['aoe_self', 'sound', 'downbeat', 'knockback'],
  pair='psv_gungchae', evo='evo_hapjangdan',
  targeting='무당 중심 확산 고리',
  cols=[('dmg', '피해'), ('cd', '쿨(초)'), ('area', '반경(u)'), ('ring2', '후속 "쿵"')],
  base=dict(dmg=8, cd=2.8, area=3.2, ring2=0, kb=0.6, expand=0.35),
  deltas=[('피해 +2', dict(dmg=2)),
          ('반경 +0.4', dict(area=0.4)),
          ('쿨 −0.3', dict(cd=-0.3)),
          ('후속 "쿵"(반박 뒤, 50% 피해)', dict(ring2=1)),
          ('피해 +3', dict(dmg=3)),
          ('반경 +0.4', dict(area=0.4)),
          ('피해 +4, 쿨 −0.3', dict(dmg=4, cd=-0.3))],
  limits=dict(max_active=2, min_period=0.75, amt_cap=3),
  amount_rule='신장 수 1당 후속 고리 +1(직전 고리의 70% 피해, 상한 +3)',
  model=lambda s: (s['dmg'] * (1 + 0.5 * s['ring2']) / s['cd'],
                   s['dmg'] * circle(s['area']) * (1 + 0.5 * s['ring2']) / s['cd']),
)

W(id='wpn_obanggi', name='오방기', hanja='五方旗', color='white', origin='巫', scope='v1',
  archetype='오색 버프 장판(아군 버프 + 약한 백 피해)', tags=['zone', 'buff', 'flag'],
  pair='psv_sinjangdae', evo='evo_obangjin',
  targeting='무당 중심 3u 내 무작위 지점(무당 위치 가중 50%)',
  cols=[('dmg', '피해/0.5초'), ('cd', '쿨(초)'), ('amt', '깃발 수'), ('area', '반경(u)'), ('dur', '지속(초)'), ('buff', '버프 배율')],
  base=dict(dmg=2, cd=6.0, amt=1, area=2.0, dur=5.0, buff=1.0, tick=0.5),
  deltas=[('반경 +0.4', dict(area=0.4)),
          ('지속 +1.5', dict(dur=1.5)),
          ('깃발 +1', dict(amt=1)),
          ('버프 효과 ×1.25', dict(buff=0.25)),
          ('피해 +1', dict(dmg=1)),
          ('쿨 −1.0', dict(cd=-1.0)),
          ('깃발 +1, 반경 +0.4', dict(amt=1, area=0.4))],
  limits=dict(max_active=6, min_period=3.0, amt_cap=5),
  amount_rule='신장 수 1당 깃발 +1(상한 5). 같은 색 중첩 없음',
  model=lambda s: ((s['dmg'] / s['tick']) * 0.5 * min(1, s['amt'] * s['dur'] / s['cd']),
                   s['dmg'] * s['amt'] * circle(s['area']) * (s['dur'] / s['tick']) * (1 if s['amt'] == 1 else ZONE_OVERLAP) / s['cd']),
)

# ============================ 진화 20 ======================================
EVOS = []

def E(**kw):
    EVOS.append(kw)

E(id='evo_sinjangkal', name='신장칼', hanja='神將-', base='wpn_sinkal', passive='psv_baekjisul', color='red', scope='v1',
  stats=dict(dmg=22, cd=1.2, amt=3, area=7.0, pierce=INF, spd=12.0, hitbox=0.7, catch_r=1.5),
  summary='이북식 1m 대신칼. 왕복 관통 무한, 손에 돌아오는 순간 반경 1.5u 원형 참격(100%).',
  model=lambda s: (s['dmg'] * (s['amt'] * 2 + 1) * critf(s) / s['cd'],
                   s['dmg'] * (s['amt'] * 2 * line(s['area'], 2 * s['hitbox'] - 0.6 + 0.6) + circle(s['catch_r'])) * critf(s) / s['cd']))
E(id='evo_manwoldo', name='만월도', hanja='滿月刀', base='wpn_woldo', passive='psv_obangkkeun', color='red', scope='v1',
  stats=dict(dmg=40, cd=1.5, spins=2, area=2.8, kb=1.0, wave_dmg=18, waves=8, wave_range=6.0, wave_pierce=2, wave_width=1.0, wave_spd=9.0),
  summary='2회전 베기. 마지막 회전이 끝나면 반달 검기 8개를 사방으로 발사(사거리 6u, 관통 2).',
  model=lambda s: ((s['dmg'] * s['spins'] + s['wave_dmg']) * critf(s) / s['cd'],
                   (s['dmg'] * s['spins'] * cap(RHO * math.pi * (s['area'] ** 2 - 0.36)) + s['wave_dmg'] * s['waves'] * line(s['wave_range'], s['wave_width'], s['wave_pierce'])) * critf(s) / s['cd']))
E(id='evo_saseulchang', name='사슬창', hanja='-槍', base='wpn_samjichang', passive='psv_sinjangdae', color='red', scope='v1',
  stats=dict(dmg=30, cd=1.2, prongs=5, thrusts=2, area=5.5, width=0.6, mark=0.30, amt=1, verdict_chance=0.5, verdict_cd=45),
  summary='5갈래(±30°) 2연속 찌르기. 표식 증폭 30%. 표식 정예 퇴치 시 사슬세우기 판결: 50% 길흉 상자(판결 쿨 45초).',
  model=lambda s: (s['dmg'] * s['thrusts'] * 3 * (1 + s['mark']) * critf(s) / s['cd'],
                   s['dmg'] * s['thrusts'] * s['prongs'] * line(s['area'], s['width']) * critf(s) / s['cd']))
E(id='evo_daejakdu', name='대작두', hanja='大斫刀', base='wpn_jakdu', passive='psv_mubok', color='red', scope='v1',
  stats=dict(dmg=70, cd=3.5, area=3.8, invuln=1.0, lowhp_k=2.0, wave2_mult=0.6, wave2_area=1.3, min_period=3.0),
  summary='쌍날 대작두. 무적 1.0초, 충격파 2연(2파: 0.4초 뒤 반경 ×1.3, 피해 60%). 최소 주기 3.0초.',
  model=lambda s: (s['dmg'] * (1 + s['wave2_mult']) * critf(s) / s['cd'],
                   s['dmg'] * (circle(s['area']) + s['wave2_mult'] * circle(s['area'] * s['wave2_area'])) * critf(s) / s['cd']))
E(id='evo_isippalsugeom', name='이십팔수검', hanja='二十八宿劍', base='wpn_sainsageom', passive='psv_santong', color='red', scope='v1',
  stats=dict(dmg=40, cd=1.6, amt=3, area=9.0, width=1.2, elite=2.0, bolt_dmg=24, bolt_r=1.2, bolts_per_wave=3, grand_every=28, grand_bolts=28, grand_dmg=60),
  summary='검기 경로 3u마다 별 표식 3개 → 0.5초 뒤 28수 낙뢰(반경 1.2u). 28번째 검기마다 화면 내 적 28체에 일제 낙뢰.',
  model=lambda s: ((s['dmg'] * s['elite'] * 3 + s['bolt_dmg'] * 1 + s['grand_dmg'] * s['grand_bolts'] / s['grand_every'] / 28 * 3) * critf(s) / s['cd'],
                   (s['dmg'] * s['amt'] * line(s['area'], s['width']) + s['bolt_dmg'] * s['bolts_per_wave'] * s['amt'] * circle(s['bolt_r']) + s['grand_dmg'] * s['grand_bolts'] / s['grand_every']) * critf(s) / s['cd']))
E(id='evo_jusahwajeon', name='주사화전', hanja='朱砂火箭', base='wpn_gakgung', passive='psv_jusa', color='red', scope='v1',
  stats=dict(dmg=18, cd=0.75, amt=4, pierce=3, area=12.0, spd=20.0, crit=0.05, blast_dmg=14, blast_r=1.5, burn_dps=6, burn_dur=3.0),
  summary='경면주사 불화살. 마지막 관통 지점(또는 최대 사거리)에서 폭발(반경 1.5u) + 화공 화상 3초(초당 6, 갱신형).',
  model=lambda s: ((s['dmg'] * s['amt'] + s['blast_dmg'] * s['amt']) * critf(s) / s['cd'] + s['burn_dps'],
                   (s['dmg'] * s['amt'] * line(s['area'], 0.4, s['pierce']) + s['blast_dmg'] * s['amt'] * circle(s['blast_r'])) * critf(s) / s['cd'] + s['burn_dps'] * min(AOE_CAP, s['amt'] * circle(s['blast_r']) * s['burn_dur'] / s['cd'] * 0.5)))
E(id='evo_pajinchang', name='파진창', hanja='破陣槍', base='wpn_jangchang', passive='psv_mituri', color='red', scope='v1',
  stats=dict(dmg=14, cd=0.7, thrusts=5, area=6.0, width=0.8, amt=1, lunge_dmg=10, lunge_range=8.0, lunge_spd=16.0, run_threshold=3.5, domu_scale=1.0, domu_cap=0.6),
  summary='돌진 연타 5회, 관통 무한. 이동 중(3.5u/s 이상)에는 찌를 때마다 창기 잔상(8u, 관통 무한) 발사. 도무 100% 초과분 1%당 피해 +1%(상한 +60%).',
  model=lambda s: (s['dmg'] * s['thrusts'] * critf(s) / s['cd'],
                   (s['dmg'] * s['thrusts'] * line(s['area'], s['width']) + 0.7 * s['lunge_dmg'] * s['thrusts'] * line(s['lunge_range'], 0.6)) * critf(s) / s['cd']))
E(id='evo_byeongnyeok_pyeongon', name='벽력편곤', hanja='霹靂鞭棍', base='wpn_pyeongon', passive='psv_myeongjusil', color='red', scope='v1',
  stats=dict(dmg=44, hp_scale=0.08, cd=1.3, angle=180, area=3.4, kb=1.6, back=1, ring_mult=0.5, ring_r=2.0, ring_offset=2.0, ring_stun=0.6),
  summary='피해 = 44 + 최대 정기의 8%. 180° 내려치기 + 역타, 착지점(2u 앞)에 충격 고리(반경 2u, 50%, 경직 0.6초).',
  model=lambda s: ((s['dmg'] + 8) * (1 + s['ring_mult']) * critf(s) / s['cd'],
                   (s['dmg'] + 8) * (cone(s['area'], s['angle']) * 1.7 + s['ring_mult'] * circle(s['ring_r'])) * critf(s) / s['cd']))

def _cjj_model(s):
    mult = 1 + min(s['salgi_ref'], 100) / 100.0
    per_act = s['amt'] + s['formation'] / 3.0
    active = per_act * s['dur'] / s['cd']
    eff = per_act if active <= s['max_act'] else s['max_act'] * s['cd'] / s['dur']
    return (s['dmg'] * mult * 2 * critf(s) / s['cd'], s['dmg'] * mult * eff * s['charges'] * TRAP_REAL * critf(s) / s['cd'])
E(id='evo_cheoljillyeojin', name='철질려진', hanja='鐵蒺藜陣', base='wpn_cheoljillyeo', passive='psv_jeung', color='red', scope='v1',
  stats=dict(dmg=14, cd=1.2, amt=8, dur=10.0, charges=6, root=1.0, max_act=90, formation=12, formation_r=3.0, salgi_ref=30, salgi_cap=100),
  summary='피해 ×(1+살기/100, 상한 ×2). 3회 발동마다 무당 둘레 반경 3u에 마름쇠 12개 진형 자동 배치.',
  model=_cjj_model)
E(id='evo_sangun_pohyodo', name='산군포효도', hanja='山君咆哮圖', base='wpn_hojakdo', passive='psv_chotdae', color='red', scope='v1',
  stats=dict(dmg=12, cd=2.2, area=6.4, fear=2.5, fear_amp=0.20, stagger=0.5),
  summary='포효 반경 ×1.6(6.4u), 공포 2.5초, 공포 대상 받는 모든 피해 +20%. 정예도 경직 0.5초.',
  model=lambda s: (s['dmg'] * critf(s) / s['cd'], s['dmg'] * 1.5 * circle(s['area']) * critf(s) / s['cd']))

E(id='evo_cheoneum_bangul', name='천음방울', hanja='天音-', base='wpn_bangul', passive='psv_chohon_jeoksam', color='white', scope='v1',
  stats=dict(dmg=9, cd=0.5, area=3.6, res_dmg=5, res_r=6.0, res_beats=2, res_period_ref=1.5, pull_spd=0.8, orb_pull_r=6.0),
  summary='맥동 + 2박마다 공명 파동(반경 6u, 피해 5): 원혼 구슬 흡인, 6u 내 풀릴 기색 적을 초당 0.8u 끌어옴.',
  model=lambda s: (s['dmg'] / s['cd'] + s['res_dmg'] / s['res_period_ref'],
                   s['dmg'] * circle(s['area']) / s['cd'] + s['res_dmg'] * circle(s['res_r']) / s['res_period_ref']))
E(id='evo_irwolseonpung', name='일월선풍', hanja='日月扇風', base='wpn_buchae', passive='psv_obangkkeun', color='white', scope='v1',
  stats=dict(dmg=16, cd=1.2, angle=130, area=4.0, gusts=2, whirl=2, whirl_dmg=8, whirl_tick=0.25, whirl_r=1.2, orbit_r=3.0, dash_every=4.0, pull_r=3.0),
  summary='돌풍 유지 + 일(日)·월(月) 회오리 2개 공전(반경 3u). 4초마다 가장 큰 풀릴 기색 무리로 돌진해 3u 내 대상을 무당 쪽으로 끌고 귀환.',
  model=lambda s: (s['dmg'] * s['gusts'] / s['cd'] + s['whirl'] * s['whirl_dmg'] / s['whirl_tick'] * 0.3,
                   s['dmg'] * s['gusts'] * cone(s['area'], s['angle']) / s['cd'] + s['whirl'] * s['whirl_dmg'] * circle(s['whirl_r']) / s['whirl_tick']))
E(id='evo_neokkkotbi', name='넋꽃비', hanja='-', base='wpn_neokjeon', passive='psv_wipae', color='white', scope='v1',
  stats=dict(dmg=12, amt=6, area=2.6, omega=216, permanent=1, petal_dmg=10, petal_r=1.0, petal_every_beats=2, petal_period_ref=1.5, cd=4.0, hit_iv=0.5),
  summary='상시 공전 6장. 2박마다 넋전마다 꽃잎 1장이 6u 내 적에게 낙하(반경 1u).',
  model=lambda s: (s['dmg'] * s['amt'] * s['omega'] / 360.0 + s['petal_dmg'] * 1 / s['petal_period_ref'],
                   s['dmg'] * s['amt'] * min(RHO * math.radians(s['omega']) * s['area'] * 1.1, 4) + s['petal_dmg'] * s['amt'] * circle(s['petal_r']) / s['petal_period_ref']))
E(id='evo_nojatdon', name='노잣돈', hanja='-', base='wpn_jijeon', passive='psv_yeopjeon', color='white', scope='v1',
  stats=dict(dmg=12, cd=1.1, amt=13, angle=60, area=6.5, pierce=3, chain=1, chain_r=3.0),
  summary='노잣돈으로 해원하면 3u 내 다른 풀릴 기색 1체 즉시 연쇄 해원(연쇄의 연쇄 없음). 해원 시 엽전 드롭 확률 +2%p.',
  model=lambda s: _jj_model(s))
E(id='evo_begareugi', name='베가르기', hanja='-', base='wpn_gilbe', passive='psv_mituri', color='white', scope='v1',
  stats=dict(dmg=14, cd=1.6, amt=2, area=6.5, width=1.4, dur=3.0, slow=0.25, tick=0.5, trail_dmg=10, trail_width=0.8, trail_len_ref=16.0),
  summary='천 펼치기 유지 + 길베 트레일(4초 궤적, 폭 0.8u) 자체가 0.5초마다 백 피해 10.',
  model=lambda s: (s['dmg'] * (s['dur'] / s['tick']) * 0.5 / s['cd'] + s['trail_dmg'] / s['tick'] * 0.3,
                   s['dmg'] * s['amt'] * cap(RHO * s['area'] * (s['width'] + 0.6)) * (s['dur'] / s['tick']) * 0.5 / s['cd'] + s['trail_dmg'] * cap(RHO * s['trail_len_ref'] * (s['trail_width'] + 0.6)) / s['tick']))
E(id='evo_sammul_ssitgim', name='삼물씻김', hanja='三-', base='wpn_ssukmul', passive='psv_jeonghwasu', color='white', scope='v1',
  stats=dict(dmg=8, cd=3.0, amt=2, puddles=3, area=2.2, dur=4.0, tick=0.5, hyang_puri=1.0, ssuk_slow=0.30, malgeun_heal=0.005),
  summary='바가지마다 맑은물→쑥물→향물 장판 3개를 무당 쪽에서 대상 쪽으로 1.5u 간격 직선 배치(0.3초 차, 씻김 순서 고증). 맑은물: 무당 정기 초당 +0.5%·영가 수명 정지, 쑥물: 감속 30%, 향물: 풀이 +1.0.',
  model=lambda s: ((s['dmg'] / s['tick']) * min(1, s['dur'] / s['cd']),
                   s['dmg'] * s['amt'] * s['puddles'] * circle(s['area']) * 0.6 * (s['dur'] / s['tick']) / s['cd']))
E(id='evo_bujeong_gasim', name='부정가심', hanja='不淨-', base='wpn_sogeum', passive='psv_mubok', color='white', scope='v1',
  stats=dict(dmg=14, area=3.2, push=1.0, permanent=1, purge_r=5.0, purge_rate=4, burst_dmg=20, burst_r=1.2, tick=0.5, cd=5.0),
  summary='무당을 따라다니는 상시 결계(반경 3.2u). 5u 내 살 알갱이를 0.25초에 1개씩 정화, 정화마다 흰 폭발(반경 1.2u, 피해 20).',
  model=lambda s: ((s['dmg'] / s['tick']) * 0.5 + s['burst_dmg'] * 0.3,
                   s['dmg'] * ring_band(s['area']) / s['tick'] * 0.7 + s['burst_dmg'] * 1.0 * circle(s['burst_r'])))
E(id='evo_irwol_myeongdu', name='일월명두', hanja='日月明圖', base='wpn_myeongdu', passive='psv_baritdae', color='white', scope='v1',
  stats=dict(dmg=16, cd=1.2, mirrors=4, area=8.5, width=0.7, reflect=3, reflect_decay=0.10, dark=0.08, light_r=2.0),
  summary='거울 4개, 빛줄기 최대 3회 연쇄 반사(5u, 회당 −10%). 거울마다 반경 2u 광명 구역(어둑시니 성장 −50%).',
  model=lambda s: (s['dmg'] * s['mirrors'] / s['cd'],
                   s['dmg'] * s['mirrors'] * (line(s['area'], s['width']) + 0.9 + 0.81 + 0.73) / s['cd']))
E(id='evo_hapjangdan', name='합장단', hanja='合長短', base='wpn_janggu', passive='psv_gungchae', color='white', scope='v1',
  stats=dict(dmg=24, cd=2.1, area=4.8, gideok_dmg=12, gideok_r=3.6, counter_dmg=30, counter_r=3.0, counter_icd=1.0),
  summary='"덩"(반경 4.8u, 24) + 반박 뒤 "기덕" 2연 고리(반경 3.6u, 각 12). 무당 피격·대신 맞기 때마다 반격 파동(반경 3u, 30, 내부 쿨 1초).',
  model=lambda s: ((s['dmg'] + 2 * s['gideok_dmg']) / s['cd'],
                   (s['dmg'] * circle(s['area']) + 2 * s['gideok_dmg'] * circle(s['gideok_r'])) / s['cd']))
E(id='evo_obangjin', name='오방진', hanja='五方陣', base='wpn_obanggi', passive='psv_sinjangdae', color='white', scope='v1',
  stats=dict(dmg=6, cd=5.0, area=3.5, dur=7.0, tick=0.5, stun_beats=1, buff=1.25),
  summary='무당 위치에 중앙황 기둥, 반경 3.5u의 동·서·남·북에 청·백·적·흑 기둥(오방 배치). 진(반경 3.5u 원) 안: 5색 버프 동시(×1.25), 적 0.5초마다 피해 6, 진 완성 순간 진 안 적 1박 경직.',
  model=lambda s: ((s['dmg'] / s['tick']) * min(1, s['dur'] / s['cd']),
                   s['dmg'] * circle(s['area']) * (s['dur'] / s['tick']) / s['cd']))

# ============================ 결합 6 =======================================
UNIONS = []

def U(**kw):
    UNIONS.append(kw)

U(id='union_neoksinkal', name='넋신칼', scope='v1', parts=['evo_sinjangkal', 'evo_neokkkotbi'],
  stats=dict(dmg=34, white_dmg=14, cd=1.1, amt=4, area=7.0, pierce=INF, hitbox=0.7, petal_dmg=10, petal_r=1.0, orbit=3, orbit_dmg=12),
  summary='칼 4자루 왕복(관통 무한). 일반 대상엔 적 피해 34, 풀릴 기색 대상엔 백 피해 14×풀이. 칼 경로에 백지 술 꽃잎(반경 1u, 10). 넋전 3장 상시 공전 유지.',
  model=lambda s: (s['dmg'] * s['amt'] * 2 * critf(s) / s['cd'] + s['orbit_dmg'] * s['orbit'] * 0.6,
                   s['dmg'] * s['amt'] * 2 * line(s['area'], 0.8) * critf(s) / s['cd'] + s['petal_dmg'] * s['amt'] * 2 * circle(s['petal_r']) / s['cd'] + s['orbit_dmg'] * s['orbit'] * 2.0))
U(id='union_sogeumsal', name='소금살', scope='v1', parts=['evo_jusahwajeon', 'evo_bujeong_gasim'],
  stats=dict(dmg=20, white_dmg=9, cd=0.7, amt=5, pierce=3, area=12.0, blast_dmg=16, blast_r=1.8, purge_in_blast=1, aura_r=2.6, aura_dmg=8),
  summary='정화 화살 5발. 폭발(반경 1.8u) 안 살 알갱이 전부 정화(1발당 최대 6개). 일반 대상 적 피해, 풀릴 기색 대상 백 피해. 약화 결계(반경 2.6u, 밀어내기만) 유지.',
  model=lambda s: ((s['dmg'] + s['blast_dmg']) * s['amt'] * critf(s) / s['cd'],
                   (s['dmg'] * s['amt'] * line(s['area'], 0.4, s['pierce']) + s['blast_dmg'] * s['amt'] * circle(s['blast_r'])) * critf(s) / s['cd'] + s['aura_dmg'] * ring_band(s['aura_r']) / 0.5 * 0.7))
U(id='union_jakdu_dari', name='작두다리', scope='v1', parts=['evo_daejakdu', 'evo_begareugi'],
  stats=dict(dmg=80, cd=3.5, area=4.5, invuln=1.0, lowhp_k=2.0, ring_judge=1, trail_dmg=8, trail_width=0.8),
  summary='대작두 충격파 원이 길닦음 고리 판정(효과 1·2)으로 작동: 원 안 풀릴 기색 즉시 해원, 그 밖은 적 피해 80. 영가 천도·만다라·신명 보너스(효과 3·4)는 없음. 길베 트레일 피해 8 유지.',
  model=lambda s: (s['dmg'] * 1.6 * critf(s) / s['cd'] + s['trail_dmg'] / 0.5 * 0.3,
                   s['dmg'] * 1.6 * circle(s['area']) * critf(s) / s['cd'] + s['trail_dmg'] * cap(RHO * 16 * 1.4) / 0.5))
U(id='union_chilseong_myeonggyeonggeom', name='칠성명경검', scope='v1', parts=['evo_isippalsugeom', 'evo_irwol_myeongdu'],
  stats=dict(dmg=38, white_dmg=16, cd=1.5, amt=3, area=9.0, width=1.2, mirrors=4, reflect_mult=0.7, bolt_dmg=28, bolt_r=1.3, dark_shrink=0.15, elite=2.0),
  summary='검기 3 + 공전 거울 4. 검기가 거울을 지나면 반사 검기(70%)로 꺾이고 반사 지점에 칠성 낙뢰(반경 1.3u, 28). 어둑시니 명중 시 크기 −15%(성장 유발 없음).',
  model=lambda s: ((s['dmg'] * s['elite'] * 3 + s['bolt_dmg'] * 2) * critf(s) / s['cd'],
                   (s['dmg'] * s['amt'] * line(s['area'], s['width']) * (1 + s['reflect_mult']) + s['bolt_dmg'] * s['mirrors'] * circle(s['bolt_r'])) * critf(s) / s['cd']))
U(id='union_jin_obangjin', name='진오방진', scope='x1', parts=['evo_cheoljillyeojin', 'evo_obangjin'],
  stats=dict(dmg=16, cd=4.0, area=4.0, dur=8.0, caltrops=20, charges=6, convert_haewon=1, tick=0.5, field_dmg=10),
  summary='1마디(4박)마다 오방 결계(반경 4u) + 둘레 마름쇠 20개. 결계 안에서 일어나는 퇴치는 해원으로 전환(살 알갱이 미발생, 영가 합류).',
  model=lambda s: (s['field_dmg'] / s['tick'] + s['dmg'] * 2 / s['cd'],
                   s['field_dmg'] * circle(s['area']) * (s['dur'] / s['tick']) / s['cd'] * 0.6 + s['dmg'] * s['caltrops'] * s['charges'] * 0.5 / s['cd']))
U(id='union_sanullim', name='산울림', scope='x1', parts=['evo_sangun_pohyodo', 'evo_cheoneum_bangul'],
  stats=dict(dmg=30, cd=3.0, area=7.0, fear=2.5, mass_haewon_cap=30, pulse_dmg=9, pulse_cd=0.5, pulse_r=3.6),
  summary='포효+방울 공명(반경 7u): 공포 2.5초, 범위 안 풀릴 기색 일괄 해원(1회 최대 30체). 맥동 방울 오라 유지.',
  model=lambda s: (s['dmg'] / s['cd'] + s['pulse_dmg'] / s['pulse_cd'],
                   s['dmg'] * circle(s['area']) / s['cd'] + s['pulse_dmg'] * circle(s['pulse_r']) / s['pulse_cd']))

# 공통 의례 기준값 (영가 넋두리 오라, 길닦음 효과 2 계산용)
RITUAL_REF = {1: 10, 2: 12, 3: 14, 4: 16, 5: 18, 6: 21, 7: 24, 8: 28, 'evo': 36, 'union': 40}

# 기준 한(적 HP) 곡선과 기준 신빨
# [리뷰 대응 R1] 곡선 소유자 = 07 (data/enemies.json scaling.T_han). 04는 값을 복제만 한다.
# 기준 잡귀 = 달걀귀신 han_base 12, 살기 0, 표준 모드.
HAN_BASE_REF = 12
T_A, T_B = 0.18, 0.012          # enemies.json scaling.T_han.a / .b (07 3.2)
T_B_LEVER_A = 0.006             # 레버 A(07 이차항 완화) 비교용

def T(t, b=None):
    return 1 + T_A * t + (T_B if b is None else b) * t * t

def H(t, b=None):
    return HAN_BASE_REF * T(t, b)

RED_SHAPE_LEVER_B = 1.5         # 레버 B: 적 진화 1타 ×1.5, 주기 ×1.5 (DPS 중립, k만 ×1.5)

SINPPAL_REF = {0: 1.0, 5: 1.1, 10: 1.3, 15: 1.6, 20: 1.9}

GEORI = [
    ('geori_jutang_bujeong', '주당물림·부정거리', '진양조', 45, '00:00~03:00', 0.25),
    ('geori_gamang_sansin', '가망청배·산신거리', '중모리', 80, '03:00~06:00', 0.5),
    ('geori_byeolsang_daegam_jeseok', '별상·대감·제석거리', '중중모리', 95, '06:00~12:00', 0.5),
    ('geori_janggun_gunung_changbu', '장군·군웅·창부거리', '자진모리', 120, '12:00~18:00', 0.5),
    ('geori_jakdu', '작두거리', '단모리', 160, '18:00~19:00', 0.5),
    ('geori_dwitjeon', '뒷전거리', '단모리(진오방진)', 180, '19:00~20:00', 0.5),
]
