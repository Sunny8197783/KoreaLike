"""Builds a labelled contact sheet of PNGs. Usage: python contact_sheet.py OUT.png img1.png img2.png ... [--scale N]"""
import sys
from PIL import Image, ImageDraw
args = sys.argv[1:]
scale = 2
if "--scale" in args:
    i = args.index("--scale"); scale = int(args[i + 1]); del args[i:i + 2]
out, files = args[0], args[1:]
ims = [Image.open(f).convert("RGBA") for f in files]
ims = [im.resize((im.width * scale, im.height * scale), Image.NEAREST) for im in ims]
cols = min(4, len(ims)); rows = (len(ims) + cols - 1) // cols
cw = max(i.width for i in ims) + 8; ch = max(i.height for i in ims) + 22
sheet = Image.new("RGBA", (cw * cols, ch * rows), (40, 36, 48, 255))
d = ImageDraw.Draw(sheet)
for n, (im, f) in enumerate(zip(ims, files)):
    x, y = (n % cols) * cw + 4, (n // cols) * ch + 4
    sheet.alpha_composite(im, (x, y)); d.text((x, y + im.height + 2), f.split("/")[-1], fill=(230, 220, 190, 255))
sheet.save(out)
