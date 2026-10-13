"""Second half of make_prison_trees_blender.py: raw 3x renders -> 314 x 359 sprites with a soft ground shadow (same recipe as make_trees_extra.py) in assets/trees."""
import os
from PIL import Image, ImageDraw, ImageFilter
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "docs/experiments/prison/blender")
W, H = 314, 359
for name in ("tree_21", "tree_22", "tree_23", "tree_24"):
    im = Image.open(os.path.join(RAW, name + "_raw.png")).convert("RGBA").resize((W, H), Image.LANCZOS)
    # the foot of the sprite sits at y 338 like the others: shift by the lowest opaque row
    bb = im.getchannel("A").getbbox()
    dy = 336 - bb[3]
    im2 = Image.new("RGBA", (W, H), (0, 0, 0, 0)); im2.alpha_composite(im, (0, dy))
    base = Image.new("L", (W, H), 0)
    ImageDraw.Draw(base).ellipse([80, 308, 250, 356], fill=90)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0)); sh.putalpha(base.filter(ImageFilter.GaussianBlur(8)))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0)); out.alpha_composite(sh); out.alpha_composite(im2)
    out.save(os.path.join(ROOT, "assets/trees", name + ".png"))
