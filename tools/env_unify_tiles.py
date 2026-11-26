import json, colorsys, shutil
from PIL import Image
T='C:/Users/김태양/Desktop/KoreaLike/game/assets/tiles/'; A='C:/Users/김태양/Desktop/KoreaLike/art/tilesets/'
def lum(c): return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]
def tile(name,val):
  im=Image.open(T+name+'.png').convert('RGBA'); m=json.load(open(T+name+'.metadata.json',encoding='utf-8'))
  for t in m['tileset_data']['tiles']:
    if all(v==val for v in t['corners'].values()):
      b=t['bounding_box']; return im.crop((b['x'],b['y'],b['x']+32,b['y']+32))
# 1) stone set: remap its grey earth palette onto the shared brown earth palette (rank by luminance)
ge=sorted(set(tile('tile_guksadang_earth_grass','lower').get_flattened_data()), key=lum)
se=sorted(set(tile('tile_guksadang_earth_stone','lower').get_flattened_data()), key=lum)
mp={c: ge[min(len(ge)-1, round(i*(len(ge)-1)/max(1,len(se)-1)))] for i,c in enumerate(se)}
shutil.copyfile(T+'tile_guksadang_earth_stone.png', A+'tile_guksadang_earth_stone_greyearth_orig.png')
im=Image.open(T+'tile_guksadang_earth_stone.png').convert('RGBA'); px=im.load(); n=0
for y in range(im.height):
  for x in range(im.width):
    if px[x,y] in mp: px[x,y]=mp[px[x,y]]; n+=1
im.save(T+'tile_guksadang_earth_stone.png'); print('stone earth remapped px',n, len(se),'->',len(ge))
# 2) grass_rock: tone the granite down (grass base pixels untouched so the chain stays exact)
gg=set(tile('tile_guksadang_earth_grass','upper').get_flattened_data())
shutil.copyfile(T+'tile_guksadang_grass_rock.png', A+'tile_guksadang_grass_rock_raw.png')
im=Image.open(T+'tile_guksadang_grass_rock.png').convert('RGBA'); px=im.load()
for y in range(im.height):
  for x in range(im.width):
    p=px[x,y]
    if p in gg or not p[3]: continue
    h,s,v=colorsys.rgb_to_hsv(*[c/255 for c in p[:3]]); r,g,b=colorsys.hsv_to_rgb(h,s*0.8,v*0.78)
    px[x,y]=(round(r*255),round(g*255),round(b*255),p[3])
im.save(T+'tile_guksadang_grass_rock.png')
