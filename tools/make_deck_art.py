#!/usr/bin/env python3
"""Builds the art for the raised platforms (the walkways behind the wall and the
corner towers) from three reference pictures kept in tools/art_src/: a scaffold
front, a tower base and a ladder, made with Meshy from text prompts.

    python3 tools/make_deck_art.py            # writes into assets/objects/
    DECK_DEBUG=some/dir python3 tools/make_deck_art.py   # also a contact sheet

What it does to the references: cuts the flat magenta background out (and the
magenta out of the edges), warms the wood toward the game's planks, squashes the
pictures vertically the way the game's slightly tilted view squashes everything
that stands up (the game's people are about 0.6 of their height on screen),
fills the open frames with the dark of the space under a deck, and cuts them
into the pieces scripts/render/deck_faces.gd puts together:

    deck_face_bay_0..2.png   one bay of the scaffold between two posts
    deck_face_post_0..1.png  a post with its lashings, drawn over each joint
    deck_face_cap_w/e.png    the left and the right end of a face
    deck_leg.png             one post on its own, for the side walkways
    deck_face_tower.png      the whole base of a corner tower
    deck_ladder_front.png    a ladder hung down a face
    deck_ladder_side_w/e.png a ladder leaning out from the side of the west
                             and the east walkway

The sizes here and the constants at the top of deck_faces.gd go together.
Units: the faces are drawn at 192 pixels to the tile (the game's objects at 96).
"""
import os

import numpy as np
from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "art_src")
OUT = os.path.join(ROOT, "assets", "objects")
PX = 192  # pixels to the tile

# What the faces measure, in tiles. deck_faces.gd has the same numbers.
BAY_W = 1.25
WALKWAY_H = 1.3
TOWER_W = 3.6
TOWER_H = 1.9
LADDER_W = 0.62
LADDER_LEAN = 1.35

OUTLINE = (14, 8, 10)


# ----------------------------------------------------------------- helpers --

def load(name):
    return Image.open(os.path.join(SRC, name)).convert("RGB")


def shift(mask, dy, dx):
    out = np.zeros_like(mask)
    h, w = mask.shape
    out[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)] = \
        mask[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)]
    return out


def dilate(mask, r):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                out |= shift(mask, dy, dx)
    return out


def key_background(im, near=28.0, ring=2):
    """The picture with its flat background made transparent. Only the outline
    at the edge is partly see-through (and takes the outline's colour, so no
    magenta is left in it); everything inside is untouched."""
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    bg = np.median(np.array([a[4, 4], a[4, w - 5], a[h - 5, 4], a[h - 5, w - 5]]), axis=0)
    d = np.linalg.norm(a - bg, axis=2)
    gone = d < near
    edge = dilate(gone, ring) & ~gone
    o = np.array(OUTLINE, np.float32)
    ob = o - bg
    t = np.clip(((a - bg) @ ob) / float(ob @ ob), 0.0, 1.0)
    alpha = np.where(gone, 0.0, 1.0)
    alpha = np.where(edge, np.clip(t * 1.2, 0.0, 1.0), alpha)
    rgb = np.where(edge[..., None], o, a)
    return Image.fromarray(np.dstack([rgb, alpha * 255.0]).round().astype(np.uint8))


def grade(im, gain=(1.0, 1.0, 1.0), lift=0.0):
    """Multiplies the colours (a warmer or darker picture), keeps the alpha."""
    a = np.asarray(im).astype(np.float32)
    rgb = a[..., :3] * np.array(gain, np.float32) + lift
    a[..., :3] = np.clip(rgb, 0, 255)
    return Image.fromarray(a.round().astype(np.uint8))


def flood(rgb, allowed, seed_xy, tolerance):
    """The pixels joined to the seed (x, y) whose colour is within the tolerance
    of the seed's, as a boolean mask."""
    from collections import deque
    h, w, _ = rgb.shape
    sx, sy = seed_xy
    seed = rgb[sy, sx].astype(np.float32)
    near = (np.linalg.norm(rgb.astype(np.float32) - seed, axis=2) < tolerance) & allowed
    seen = np.zeros((h, w), bool)
    todo = deque([(sy, sx)])
    seen[sy, sx] = True
    while todo:
        y, x = todo.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and near[ny, nx]:
                seen[ny, nx] = True
                todo.append((ny, nx))
    return seen


def alpha_over(top, bottom):
    return Image.alpha_composite(bottom, top)


def under_deck(size, y_top, y_bottom, dark=(10, 8, 8), light=(46, 40, 36), a0=1.0, a1=1.0, bend=1.4):
    """What shows through the open frames: the shaded ground under a deck,
    nearly black under the planks and a little lighter at the foot."""
    w, h = size
    ys = np.arange(h, dtype=np.float32)
    t = np.clip((ys - y_top) / max(1.0, float(y_bottom - y_top)), 0.0, 1.0) ** bend
    rgb = np.array(dark, np.float32)[None, :] * (1 - t[:, None]) + np.array(light, np.float32)[None, :] * t[:, None]
    al = (a0 * (1 - t) + a1 * t) * 255.0
    al = np.where((ys >= y_top) & (ys <= y_bottom), al, 0.0)
    arr = np.zeros((h, w, 4), np.float32)
    arr[..., :3] = rgb[:, None, :]
    arr[..., 3] = al[:, None]
    return Image.fromarray(arr.round().astype(np.uint8))


def put(sheet, im, x, y):
    sheet.alpha_composite(im, (int(x), int(y)))


def save(im, name):
    im.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, im.size)


# ---------------------------------------------------------------- walkway ---

# measured on ref_walkway_face.png (1376 x 768): where the posts stand, where the
# face starts and ends
POST_X = [99.5 + 294.25 * i for i in range(5)]
FACE_TOP = 122
FACE_BOTTOM = 667
FASCIA_BOTTOM = 186
FASCIA_LEFT = 68
POST_HALF = 40.45     # half the width of a post piece, in reference pixels


def walkway_sheet():
    """The scaffold front, keyed, warmed and with its openings filled."""
    keyed = key_background(load("ref_walkway_face.png"))
    keyed = grade(keyed, gain=(1.0, 0.93, 0.80))
    fill = np.asarray(under_deck(keyed.size, FASCIA_BOTTOM - 4, FACE_BOTTOM - 2)).copy()
    fill[:, :FASCIA_LEFT, 3] = 0
    return alpha_over(keyed, Image.fromarray(fill))


def walkway_pieces():
    sheet = walkway_sheet()
    sx = BAY_W * PX / 294.25
    h = int(round(WALKWAY_H * PX))
    bays = []
    for i in range(3):
        box = (POST_X[i], FACE_TOP, POST_X[i + 1], FACE_BOTTOM)
        bays.append(sheet.resize((int(round(BAY_W * PX)), h), Image.LANCZOS, box=box))
    pw = int(round(2 * POST_HALF * sx))
    posts = []
    for i in (1, 2):
        box = (POST_X[i] - POST_HALF, FACE_TOP, POST_X[i] + POST_HALF, FACE_BOTTOM)
        posts.append(sheet.resize((pw, h), Image.LANCZOS, box=box))
    cap_l = 44.0
    cap_w = int(round((cap_l + POST_HALF) * sx))
    cap = sheet.resize((cap_w, h), Image.LANCZOS, box=(POST_X[0] - cap_l, FACE_TOP, POST_X[0] + POST_HALF, FACE_BOTTOM))
    return bays, posts, cap


# ------------------------------------------------------------------ tower ---

def tower_piece():
    keyed = key_background(load("ref_tower_face.png"))
    a = np.asarray(keyed).astype(np.int32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    # the picture has the tower's shadow on the ground as a maroon slab: take it out
    slab = flood(a[..., :3], al > 0, (600, 720), tolerance=24.0)
    # and the pink the slab's edge left against it
    pink = dilate(slab, 5) & (r - g > 28) & (b - g > 10) & (r > 70)
    a[..., 3] = np.where(slab | pink, 0, al)
    keyed = Image.fromarray(a.astype(np.uint8))
    x0, y0, x1, y1 = keyed.getbbox()
    keyed = keyed.crop((x0, y0, x1, y1))
    arr = np.asarray(keyed).astype(np.float32)
    h, w, _ = arr.shape
    # the legs splay less: squeeze the rows toward the middle going down
    out = np.zeros_like(arr)
    cx = (w - 1) / 2.0
    xs = np.arange(w, dtype=np.float32)
    pre = arr.copy()
    pre[..., :3] *= (pre[..., 3:4] / 255.0)
    for y in range(h):
        f = 1.0 - 0.20 * (y / float(h - 1))
        src = cx + (xs - cx) / f
        for c in range(4):
            out[y, :, c] = np.interp(src, xs, pre[y, :, c], left=0.0, right=0.0)
    al = out[..., 3:4]
    out[..., :3] = np.where(al > 0, out[..., :3] / np.maximum(al / 255.0, 1e-3), 0.0)
    squeezed = Image.fromarray(np.clip(out, 0, 255).round().astype(np.uint8))
    squeezed = squeezed.crop(squeezed.getbbox())
    h, w = squeezed.size[1], squeezed.size[0]
    squeezed = grade(squeezed, gain=(1.0, 0.93, 0.80))
    # fill the open frame between the legs, from under the slab to the ground
    sa = np.asarray(squeezed)[..., 3] > 8
    fill = np.zeros((h, w), bool)
    slab_bottom = int(h * 0.10)
    ground = int(h * 0.985)
    for y in range(slab_bottom, ground):
        xs_on = np.where(sa[y])[0]
        if xs_on.size:
            fill[y, xs_on.min():xs_on.max() + 1] = True
    under = np.asarray(under_deck((w, h), slab_bottom, ground, light=(52, 45, 40))).copy()
    under[..., 3] = np.where(fill, under[..., 3], 0)
    squeezed = alpha_over(squeezed, Image.fromarray(under))
    # whole-tower bounds: the slab across the top is the deck's width
    slab_cols = np.where(np.asarray(squeezed)[int(h * 0.04), :, 3] > 128)[0]
    slab_w = float(slab_cols.max() - slab_cols.min() + 1)
    k = TOWER_W * PX / slab_w
    final = squeezed.resize((int(round(w * k)), int(round(TOWER_H * PX))), Image.LANCZOS)
    left = slab_cols.min() * k
    right = (w - 1 - slab_cols.max()) * k
    pad = int(round(max(left, right)))
    centred = Image.new("RGBA", (int(round(TOWER_W * PX)) + 2 * pad, final.size[1]), (0, 0, 0, 0))
    centred.alpha_composite(final, (int(round(pad - left)), 0))
    return centred, (pad, slab_w * k)


# ----------------------------------------------------------------- ladders --

def ladder_pieces():
    keyed = key_background(load("ref_ladder.png"))
    keyed = grade(keyed, gain=(1.0, 1.0, 1.0))
    # the picture sees the ladder from the side a little: its rungs slope. Shear
    # it back so the rungs run level, as seen from the front.
    w, h = keyed.size
    slope = 0.31
    x_mid = w / 2.0
    sheared = keyed.transform((w, h + 140), Image.AFFINE, (1, 0, 0, slope, 1, -slope * x_mid + 70), resample=Image.BICUBIC)
    box = sheared.getbbox()
    sheared = sheared.crop(box)
    front = sheared.resize((int(round(LADDER_W * PX)), int(round((WALKWAY_H + 0.22) * PX))), Image.LANCZOS)
    side = sheared.rotate(90, expand=True).resize((int(round(LADDER_LEAN * PX)), int(round(0.56 * PX))), Image.LANCZOS)
    return front, side


def leg_piece():
    """One post on its own (the supports along the side walkways, which show
    their edge to the yard), without the openings filled."""
    keyed = grade(key_background(load("ref_walkway_face.png")), gain=(1.0, 0.93, 0.80))
    half = 24.0
    sx = BAY_W * PX / 294.25
    w = int(round(2 * half * sx))
    return keyed.resize((w, int(round(WALKWAY_H * PX))), Image.LANCZOS, box=(POST_X[2] - half, FACE_TOP, POST_X[2] + half, FACE_BOTTOM))


# -------------------------------------------------------------------- main --

def contact_sheet(parts):
    w = sum(p.size[0] + 20 for p in parts) + 20
    h = max(p.size[1] for p in parts) + 40
    sheet = Image.new("RGBA", (w, h), (118, 116, 112, 255))
    x = 20
    for p in parts:
        put(sheet, p, x, 20)
        x += p.size[0] + 20
    return sheet


def main():
    bays, posts, cap = walkway_pieces()
    for i, b in enumerate(bays):
        save(b, "deck_face_bay_%d.png" % i)
    for i, p in enumerate(posts):
        save(p, "deck_face_post_%d.png" % i)
    leg = leg_piece()
    save(leg, "deck_leg.png")
    save(cap, "deck_face_cap_w.png")
    save(ImageOps.mirror(cap), "deck_face_cap_e.png")
    tower, (slab_x, slab_w) = tower_piece()
    save(tower, "deck_face_tower.png")
    print("tower: slab %.1f px wide, overhang %d px each side" % (slab_w, slab_x))
    front, side = ladder_pieces()
    save(front, "deck_ladder_front.png")
    save(side, "deck_ladder_side_w.png")
    save(ImageOps.mirror(side), "deck_ladder_side_e.png")
    out = os.environ.get("DECK_DEBUG")
    if out:
        os.makedirs(out, exist_ok=True)
        strip = Image.new("RGBA", (cap.size[0] + sum(b.size[0] for b in bays) + 200, bays[0].size[1] + 40), (118, 116, 112, 255))
        x = 20
        put(strip, cap, x, 20)
        x += cap.size[0] - 30
        for i, b in enumerate(bays):
            put(strip, b, x, 20)
            put(strip, posts[i % 2], x - posts[i % 2].size[0] // 2, 20)
            x += b.size[0]
        contact_sheet([strip]).convert("RGB").save(os.path.join(out, "face_strip.png"))
        contact_sheet([tower, front, side]).convert("RGB").save(os.path.join(out, "tower_ladders.png"))


if __name__ == "__main__":
    main()
