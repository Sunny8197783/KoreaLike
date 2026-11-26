import json, colorsys, sys
from PIL import Image
T='C:/Users/김태양/Desktop/KoreaLike/game/assets/tiles/'; A='C:/Users/김태양/Desktop/KoreaLike/art/tilesets/'
def tile_px(img, meta, cornerval):
    for t in meta['tileset_data']['tiles']:
        if all(v==cornerval for v in t['corners'].values()):
            b=t['bounding_box']; return img.crop((b['x'],b['y'],b['x']+b['width'],b['y']+b['height']))
g=Image.open(T+'tile_guksadang_earth_grass.png').convert('RGBA'); gm=json.load(open(T+'tile_guksadang_earth_grass.metadata.json',encoding='utf-8'))
earth=tile_px(g,gm,'lower'); ecols=set(earth.getdata())
# needles: grade only non-earth pixels
n=Image.open(A+'tile_guksadang_earth_needles_raw.png').convert('RGBA'); px=n.load(); ch=0
for y in range(n.height):
  for x in range(n.width):
    r,gg,b,a=px[x,y]
    if (r,gg,b,a) in ecols: continue
    h,s,v=colorsys.rgb_to_hsv(r/255,gg/255,b/255)
    s*=0.62; v*=0.70; h=h-0.012 if h>0.02 else h
    r2,g2,b2=colorsys.hsv_to_rgb(h,s,v); px[x,y]=(round(r2*255),round(g2*255),round(b2*255),a); ch+=1
n.save(T+'tile_guksadang_earth_needles.png'); print('needles changed px',ch)
nm=json.load(open(T+'tile_guksadang_earth_needles.metadata.json',encoding='utf-8'))
ne=tile_px(n,nm,'lower'); print('needles lower == grass lower:', list(ne.getdata())==list(earth.getdata()))
