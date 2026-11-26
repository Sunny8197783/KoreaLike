import json, glob, os
from PIL import Image
T='C:/Users/김태양/Desktop/KoreaLike/game/assets/tiles/'; P='C:/Users/김태양/Desktop/KoreaLike/game/assets/props/'
# make stone set's all-earth tile byte-identical to the shared earth tile
def bbox(name,val):
  m=json.load(open(T+name+'.metadata.json',encoding='utf-8'))
  for t in m['tileset_data']['tiles']:
    if all(v==val for v in t['corners'].values()):
      b=t['bounding_box']; return (b['x'],b['y'],b['x']+32,b['y']+32)
g=Image.open(T+'tile_guksadang_earth_grass.png').convert('RGBA'); s=Image.open(T+'tile_guksadang_earth_stone.png').convert('RGBA')
s.paste(g.crop(bbox('tile_guksadang_earth_grass','lower')), bbox('tile_guksadang_earth_stone','lower')[:2]); s.save(T+'tile_guksadang_earth_stone.png')
# reserved-white guard: environment may not use the #f2ece0 family (or brighter neutral whites) -> hanji #e9dcc0
RW=(242,236,224); HJ=(233,220,192,255)
def near(p): return sum((a-b)**2 for a,b in zip(p[:3],RW))**0.5 < 14 or (min(p[:3])>236 and max(p[:3])-min(p[:3])<30)
def rl(c):
  def f(u):
    u/=255; return u/12.92 if u<=0.04045 else ((u+0.055)/1.055)**2.4
  r,g,b=[f(x) for x in c[:3]]; return 0.2126*r+0.7152*g+0.0722*b
rep={}
for f in sorted(glob.glob(P+'*.png'))+sorted(glob.glob(T+'*.png'))+[ 'C:/Users/김태양/Desktop/KoreaLike/game/assets/vfx/vfx_candle_flame_s.png']:
  im=Image.open(f).convert('RGBA'); px=im.load(); n=0; L=[]
  for y in range(im.height):
    for x in range(im.width):
      p=px[x,y]
      if not p[3]: continue
      if near(p): px[x,y]=HJ; n+=1
      L.append(rl(px[x,y]))
  if n: im.save(f)
  rep[os.path.basename(f)]=(n, round(sum(L)/max(1,len(L)),3), len(set(im.get_flattened_data())))
for k,v in rep.items(): print(f'{k:45s} whites_fixed={v[0]:4d} mean_rel_lum={v[1]} colors={v[2]}')
