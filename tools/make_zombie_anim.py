#!/usr/bin/env python3
"""ROUND 11: baked animation frames for the prison's dead (RimWorld style, PIL only, free). The same layered parts as Round 10 (torso, arms, head; tools/make_rimworld_zombies.py) are posed by
offsets and rotations at 4x, outlined, rim-lit, averaged down to half size and packed per look into one atlas with a JSON index.

    python3 tools/make_zombie_anim.py                    # every set (walker 24 looks, runner 6, brute 4, crawler 4) into assets/pawns/zan/
    python3 tools/make_zombie_anim.py --set=walker --look=3
    python3 tools/make_zombie_anim.py --strips=dir       # contact strips of one look per kind (every pose) into dir
    python3 tools/make_zombie_anim.py --faces=file.png   # the 13 face variants on the 6 skin tones

Files: assets/pawns/zan/<set><look>.png (atlas), assets/pawns/zan/index.json ({set: {look: {"view/anim/k": [x, y, w, h, ox, oy]}}}, in half-size canvas pixels; the canvas is 184 x 164),
assets/pawns/zan/fx.png (damage decals and gibs).
Poses: walk (walker 6 shamble, runner 6 sprint, brute 4 stomp, crawler 6 crawl), idle 4, attack 4, hurt 2 (S, E, N); death_f and death_b 5 each, rise 4 (E only: the dead fall and rise side-on).
"""
import argparse
import json
import math
import multiprocessing as mp
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageChops, ImageDraw, ImageFilter  # noqa: E402

import make_rimworld_zombies as rw  # noqa: E402
import zombie_heads as zh  # noqa: E402
from make_rimworld_zombies import CH, CW, CX, OL, SS, Win, capsule_m, ell_m, flat, line_m, mulc, poly_m, put  # noqa: E402

OUT = os.path.join(rw.PAWNS, "zan")
HALF = (CW // 2, (CH + 1) // 2)     # 184 x 164
FEET = (CX, 276)                     # where the shoes touch the ground (the game's own legs end here)
HIPS = (CX, 252)

WALKER_LOOKS = list(range(24))
RUNNER_LOOKS = [1, 4, 8, 12, 17, 21]
BRUTE_LOOKS = [2, 9, 13, 20]
CRAWLER_LOOKS = [3, 10, 15, 22]
FV = [3, 0, 9, 6, 1, 8, 12, 4, 2, 10, 5, 7, 11, 0, 3, 9, 6, 1, 8, 5, 2, 12, 4, 10]     # the face variant of each look (see zombie_heads.FACE_NAMES)

POSES = {"walk": 6, "idle": 4, "attack": 4, "hurt": 2}
KIND_WALK = {"walker": 6, "runner": 6, "brute": 4, "crawler": 6}


# ------------------------------------------------------------------ compositing
def new_canvas():
    return Image.new("RGBA", (CW * SS, CH * SS), (0, 0, 0, 0))


def place(canvas, img, x0, y0, c=(CX, 252), t=(0, 0), sx=1.0, sy=1.0, th=0.0):
    """Put a window picture (top left at canvas pixel x0,y0) on the canvas, scaled about `c`, turned `th` degrees clockwise about it and moved by `t`."""
    a = math.radians(th)
    co, si = math.cos(a), math.sin(a)
    cx, cy = c
    tx, ty = t
    A = co / sx
    B = si / sx
    C = (cx + (co * (-cx - tx) + si * (-cy - ty)) / sx - x0) * SS
    D = -si / sy
    E = co / sy
    F = (cy + (-si * (-cx - tx) + co * (-cy - ty)) / sy - y0) * SS
    out = img.transform((CW * SS, CH * SS), Image.AFFINE, (A, B, C, D, E, F), resample=Image.BILINEAR)
    canvas.alpha_composite(out)


def xform(p, c=(CX, 252), t=(0, 0), sx=1.0, sy=1.0, th=0.0):
    a = math.radians(th)
    co, si = math.cos(a), math.sin(a)
    dx, dy = (p[0] - c[0]) * sx, (p[1] - c[1]) * sy
    return (c[0] + t[0] + dx * co - dy * si, c[1] + t[1] + dx * si + dy * co)


def darken(img, k):
    r, g, b, a = img.split()
    f = lambda v: int(v * k)
    return Image.merge("RGBA", (r.point(f), g.point(f), b.point(f), a))


# ------------------------------------------------------------------ kinds: the looks as a kind wears them
def skin_sleeves(L):
    L["outer"] = L["skin"]
    L["hivis"] = False
    if L["job"] == "cook":
        L["job"] = ""


def look_for(base, kind):
    L = dict(base)
    if kind == "runner":
        L["torn"] = 1.0
        L["eyes"] = "red" if L["i"] % 2 else L["eyes"]
        L["skin"] = rw.mix(L["skin"], (190, 150, 130), 0.18)
    elif kind == "brute":
        L["style"] = "plain"
        L["torn"] = 0.6
        L["tie"] = None
        L["pattern"] = None
        L["hivis"] = False
        L["job"] = ""
        L["bite"] = ""
        L["ribs"] = False
        L["arm_gone"] = ""
        L["skin"] = rw.mix(L["skin"], (150, 140, 120), 0.2)
        if L["i"] % 2 == 0:
            L["top"], L["outer"] = (66, 70, 76), L["skin"]          # a riot vest on bare arms
        else:
            L["top"], L["outer"] = (198, 194, 176), None            # a straitjacket (sleeves in the same cloth)
        L["hair_col"] = rw.mulc(L["hair_col"], 0.8)
    return L


_BODY = {}


def body_layer(L, view, ls, rs, kind):
    key = (L["i"], view, ls, rs, kind)
    if key not in _BODY:
        rng = random.Random(L["i"] * 101 + ord(view))
        W, m = rw.body(L, view, ls, rs, rng)
        if kind == "runner":
            runner_body(W, L, view, m)
        elif kind == "brute":
            brute_body(W, L, view, m)
        _BODY[key] = W
    return _BODY[key]


def runner_body(W, L, view, m):
    """A runner is a lean, half-stripped figure: ribs and sinew show through a torn-off shirt."""
    sk = L["skin"]
    sd = mulc(sk, 0.78)
    if view != "N":
        flat(W, poly_m(W, [(CX - 40, 176), (CX + 40, 176), (CX + 34, 226), (CX - 34, 226)]), sk, clip=m)
        for k in range(4):
            y = 192 + k * 11
            flat(W, line_m(W, [(CX - 22, y), (CX + 1, y + 3)], 2.6), sd, clip=m)
            flat(W, line_m(W, [(CX + 4, y + 3), (CX + 24, y)], 2.6), sd, clip=m)
        flat(W, line_m(W, [(CX + 2, 180), (CX + 2, 226)], 2.4), sd, clip=m)
        flat(W, poly_m(W, [(CX - 36, 226), (CX + 36, 226), (CX + 40, 250), (CX - 40, 250)]), L["top"], clip=m)
    else:
        flat(W, poly_m(W, [(CX - 40, 176), (CX + 40, 176), (CX + 34, 220), (CX - 34, 220)]), sk, clip=m)
        for k in range(5):
            flat(W, line_m(W, [(CX - 4, 186 + k * 8), (CX + 4, 186 + k * 8)], 2.2), sd, clip=m)
        flat(W, line_m(W, [(CX, 178), (CX, 222)], 2.6), sd, clip=m)
        flat(W, poly_m(W, [(CX - 36, 220), (CX + 36, 220), (CX + 40, 250), (CX - 40, 250)]), L["top"], clip=m)
    flat(W, ell_m(W, CX + 14, 206, 12, 14), rw.BLOOD_D, 170, clip=m)


def brute_body(W, L, view, m):
    k = L["i"] % 2 == 0
    if k:    # riot vest: plates, straps, a buckle
        col = (46, 52, 60)
        put(W, poly_m(W, [(CX - 52, 176), (CX + 52, 176), (CX + 56, 246), (CX - 56, 246)]), col, ow=4, clip=m)
        for sx in (-1, 1):
            put(W, poly_m(W, [(CX + sx * 6, 182), (CX + sx * 36, 182), (CX + sx * 34, 214), (CX + sx * 6, 214)]), (62, 70, 80), ow=3, clip=m)
        flat(W, poly_m(W, [(CX - 52, 222), (CX + 52, 222), (CX + 52, 230), (CX - 52, 230)]), (30, 32, 36), clip=m)
        flat(W, poly_m(W, [(CX - 5, 221), (CX + 5, 221), (CX + 5, 231), (CX - 5, 231)]), (200, 176, 80), clip=m)
        flat(W, poly_m(W, [(CX - 4, 176), (CX + 4, 176), (CX + 4, 246), (CX - 4, 246)]), (28, 30, 34), clip=m)
    else:    # straitjacket: belts across the chest, buckles, loose ties
        for y in (190, 214, 238):
            flat(W, poly_m(W, [(CX - 62, y), (CX + 62, y), (CX + 62, y + 7), (CX - 62, y + 7)]), (86, 70, 56), clip=m)
            flat(W, poly_m(W, [(CX + 18, y - 1), (CX + 27, y - 1), (CX + 27, y + 8), (CX + 18, y + 8)]), (190, 172, 90), clip=m)
        flat(W, line_m(W, [(CX - 50, 180), (CX + 46, 244)], 5), (86, 70, 56), clip=m)
        flat(W, line_m(W, [(CX + 50, 180), (CX - 46, 244)], 5), (86, 70, 56), clip=m)
    flat(W, ell_m(W, CX - 10, 214, 16, 20), rw.BLOOD_D, 140, clip=m)


# ------------------------------------------------------------------ the figure from parts
def rest_points(L, view, ls, rs):
    t = L["tilt"]
    if view == "S":
        return dict(shL=(CX - 50, 198 + ls), shR=(CX + 50, 198 + rs),
                    hL=(CX - 56 - 3 * (t > 0), 250 + (4 if t > 0 else 0)), hR=(CX + 56 + 3 * (t < 0), 250 + (4 if t < 0 else 0)),
                    head=(CX + t * 70, 152), hang=-t * 70)
    if view == "E":
        return dict(shL=(CX - 4, 198), shR=(CX + 12, 194), hL=(CX + 60, 214), hR=(CX + 66, 226), head=(CX + 20 + t * 30, 152), hang=7 - t * 30)
    return dict(shL=(CX - 48, 198 + ls), shR=(CX + 48, 198 + rs), hL=(CX - 62, 246), hR=(CX + 62, 246), head=(CX + t * 60, 164), hang=-t * 60)


def baked_legs(canvas, L, view, kb=0.0, spread=0.0, rest=None):
    """The legs of a baked pose (death and rise): two pants-coloured legs and shoes, a bent knee by `kb`. The walking figures keep the game's own legs."""
    pants = L["pants"]
    W = Win(80, 220, 210, 80)
    shoe = (34, 28, 26)
    if view == "E":
        legs = [(CX - 2, 246, CX + 6 + kb, 262, CX - 6 - spread, 274, 0.84), (CX + 8, 246, CX + 18 + kb, 262, CX + 14 + spread, 274, 1.0)]
    else:
        legs = [(CX - 16, 246, CX - 20 - spread, 262, CX - 18 - spread, 274, 1.0), (CX + 16, 246, CX + 20 + spread, 262, CX + 18 + spread, 274, 1.0)]
    for hx, hy, kx, ky, fx, fy, k in legs:
        col = mulc(pants, k)
        put(W, capsule_m(W, (hx, hy), (kx, ky), 22, 20), col)
        put(W, capsule_m(W, (kx, ky), (fx, fy - 3), 20, 18), col)
        put(W, ell_m(W, fx + (5 if view == "E" else 0), fy + 1, 13 if view == "E" else 11, 8), shoe, ow=4)
    canvas.alpha_composite(W.img, (W.x0 * SS, W.y0 * SS))


def draw_arm(canvas, L, sh, hand, bend, far=False, gone=False, wid=24, th=None):
    pad = 48
    x0, y0 = int(min(sh[0], hand[0]) - pad), int(min(sh[1], hand[1]) - pad)
    w, h = int(abs(sh[0] - hand[0]) + 2 * pad), int(abs(sh[1] - hand[1]) + 2 * pad)
    W = Win(x0, y0, w, h)
    rw.arm(W, L, sh, hand, random.Random(L["i"] * 7), gone, wid, bend)
    img = W.img
    if far:
        img = darken(img, 0.78)
    canvas.alpha_composite(img, (W.x0 * SS, W.y0 * SS)) if (W.x0 >= 0 and W.y0 >= 0 and W.x0 + W.w <= CW and W.y0 + W.h <= CH) else clip_composite(canvas, img, W.x0 * SS, W.y0 * SS)


def clip_composite(canvas, img, x, y):
    tmp = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    tmp.paste(img, (x, y))
    canvas.alpha_composite(tmp)


def figure(L, view, P, kind="walker"):
    """One posed standing figure (the 4x canvas, outfit and arms and head). P: the pose (see DEFAULT). Torso, arms and head are the Round 10 layers moved and turned by P."""
    ls0 = 16 if L["tilt"] < 0 else 0
    rs0 = 16 if L["tilt"] >= 0 else 0
    if view == "E":
        ls0 = rs0 = 4
    ls, rs = ls0 + P["shl"], rs0 + P["shr"]
    ls, rs = int(round(ls / 2.0)) * 2, int(round(rs / 2.0)) * 2
    rp = rest_points(L, view, ls0, rs0)
    bsx = {"runner": 0.9, "brute": 1.24}.get(kind, 1.0) * P.get("bsx", 1.0)
    bsy = {"brute": 1.06}.get(kind, 1.0) * P.get("bsy", 1.0)
    bt = dict(c=HIPS, t=(P["dx"], P["dy"]), sx=bsx, sy=bsy * P["sq"], th=P["rot"])
    canvas = new_canvas()
    if P.get("legs") is not None:
        baked_legs(canvas, L, view, **P["legs"])
    bw = body_layer(L, view, ls, rs, kind)
    awid = {"runner": 19, "brute": 36}.get(kind, 24 if view != "E" else 26)
    head_c = xform(rp["head"], **bt)
    hs = {"brute": 0.8, "runner": 1.0}.get(kind, 1.0) * P.get("hs", 1.0)
    hx, hy = head_c[0] + P["hdx"], head_c[1] + P["hdy"]
    hw = zh.head2(L, view, rp["head"][0], rp["head"][1], P["fv"], P["open"])
    hang = rp["hang"] - P["hrot"] - P["rot"] * 0.7
    tmp = new_canvas()
    place(tmp, hw.img, hw.x0, hw.y0, c=(rp["head"][0], rp["head"][1] + 30), t=(hx - rp["head"][0], hy - rp["head"][1]), sx=hs, sy=hs, th=-hang)
    himg = tmp

    def arm(sh, hand, d, bend, far=False, gone=False):
        s = xform(sh, **bt)
        hnd = xform((hand[0] + d[0], hand[1] + d[1]), **bt)
        draw_arm(canvas, L, s, hnd, bend, far, gone, awid)
    def body():
        if view == "N":
            canvas.alpha_composite(himg)
        place(canvas, bw.img, bw.x0, bw.y0, **bt)
    if view == "S":
        place(canvas, bw.img, bw.x0, bw.y0, **bt)
        arm(rp["shL"], rp["hL"], P["aL"], P["bL"], False, L["arm_gone"] == "L")
        arm(rp["shR"], rp["hR"], P["aR"], P["bR"], False, L["arm_gone"] == "R")
        canvas.alpha_composite(himg)
    elif view == "E":
        arm(rp["shR"], rp["hR"], P["aR"], P["bR"], True)
        place(canvas, bw.img, bw.x0, bw.y0, **bt)
        arm(rp["shL"], rp["hL"], P["aL"], P["bL"], False, L["arm_gone"] == "R")
        canvas.alpha_composite(himg)
    else:
        canvas.alpha_composite(himg)
        arm(rp["shL"], rp["hL"], P["aL"], P["bL"], False, L["arm_gone"] == "L")
        arm(rp["shR"], rp["hR"], P["aR"], P["bR"], False, L["arm_gone"] == "R")
        place(canvas, bw.img, bw.x0, bw.y0, **bt)
    return canvas


# ------------------------------------------------------------------ the poses
def P0(**kw):
    p = dict(rot=0.0, dx=0.0, dy=0.0, sq=1.0, hdx=0.0, hdy=0.0, hrot=0.0, open=0.55, aL=(0, 0), aR=(0, 0), bL=0.0, bR=0.0, shl=0, shr=0, fv=0, legs=None)
    p.update(kw)
    return p


def sn(x):
    return math.sin(x)


def pose_walk(kind, view, k, n, L):
    ph = 2 * math.pi * k / n
    ph += 0.32 * sn(ph + 0.6)          # an uneven rhythm: it lurches
    s, c, a = sn(ph), math.cos(ph), abs(sn(ph))
    sd = 1 if L["tilt"] >= 0 else -1
    lol = 9 * sn(ph * 2 + 0.5 + L["i"])      # the head lolls
    if kind == "walker":
        if view == "E":
            return P0(rot=7 + 3 * c, dy=-3 * a + 3 * max(0, -s), hdx=5 * sn(ph + 1), hdy=3 * a, hrot=lol, open=0.5 + 0.25 * sn(2 * ph + 1),
                      aL=(12 * s, -9 * max(0, s) + 5 * c), aR=(-12 * s, -9 * max(0, -s) - 3 * c), bL=7 * s, bR=-7 * s)
        if view == "S":
            return P0(rot=7 * s, dy=-4 * a, sq=1 - 0.03 * a, hdx=9 * sn(ph + 1), hdy=3 * a, hrot=lol * 1.2, open=0.5 + 0.3 * sn(2 * ph + 1),
                      aL=(9 * s, -30 * max(0, s) - 3), aR=(-9 * s, -30 * max(0, -s) - 3), bL=-10 * s, bR=-10 * s, shl=int(4 * s * sd), shr=int(-4 * s * sd))
        return P0(rot=7 * s, dy=-4 * a, hdx=8 * sn(ph + 1), hdy=2 * a, hrot=lol * 1.2, aL=(-6 * s, -22 * max(0, s)), aR=(6 * s, -22 * max(0, -s)), bL=8 * s, bR=8 * s)
    if kind == "runner":
        if view == "E":
            return P0(rot=26 + 5 * c, dy=-5 * a, dx=6, hdx=14, hdy=7, hrot=-8 + 6 * s, open=0.95,
                      aL=(-30 - 32 * s, 4 - 30 * max(0, -s) + 18 * max(0, s)), aR=(-30 + 32 * s, 4 - 30 * max(0, s) + 18 * max(0, -s)), bL=9, bR=-9)
        if view == "S":
            return P0(rot=6 * s, dy=-5 * a, sq=0.93, hdx=5 * s, hdy=11, hrot=lol * 0.5, open=1.0,
                      aL=(2, -40 * max(0, s) - 4), aR=(-2, -40 * max(0, -s) - 4), bL=-8, bR=-8)
        return P0(rot=6 * s, dy=-5 * a, sq=1.03, hdx=5 * s, hdy=-4, hrot=lol * 0.5, aL=(4, -40 * max(0, s)), aR=(-4, -40 * max(0, -s)), bL=6, bR=6)
    # brute: slow heavy stomp (two stomps in four frames)
    a = abs(sn(ph))
    if view == "E":
        return P0(rot=9 + 2 * c, dy=5 * (1 - a), hdx=4, hdy=3, hrot=4 * s, open=0.5, aL=(8 * s, 6 - 5 * a), aR=(-8 * s, 4 - 5 * a), bL=6, bR=-6)
    return P0(rot=3.5 * s, dy=5 * (1 - a), hdy=3, hrot=3 * s, open=0.5, aL=(-4 * s, 4 - 5 * a), aR=(4 * s, 4 - 5 * a), bL=-5, bR=-5)


def pose_idle(kind, view, k, n, L):
    ph = 2 * math.pi * k / n
    b = sn(ph)
    tw = [0.0, -5.0, 6.0, 1.0][k % 4] if L["i"] % 2 else [0.0, 5.0, -6.0, 1.0][k % 4]
    opn = [0.35, 0.52, 0.78, 0.45][(k + L["i"]) % 4]
    big = 1.4 if kind == "brute" else 1.0
    if view == "E":
        return P0(rot=6 + 2 * b, dy=1.6 * b * big, hdx=3 * b, hdy=1.5 * b, hrot=tw, open=opn, aL=(2 * b, 1.5 * b), aR=(-2 * b, -b), bL=5, bR=-4)
    return P0(rot=1.5 * b, dy=1.6 * b * big, hdy=1.5 * b + 3, hrot=tw, open=opn, aL=(-2 * b, 2 * b), aR=(2 * b, 2 * b), bL=-4, bR=-4, sq=1 - 0.01 * b)


def pose_attack(kind, view, k, n, L):
    fast = 1.25 if kind == "runner" else 1.0
    if kind == "brute":
        # two fists over the head, then slammed down
        E = [P0(rot=-8, dy=-3, hdx=-4, hdy=-3, hrot=-10, open=0.9, aL=(-24, -64), aR=(-30, -66), bL=-6, bR=-6),
             P0(rot=-12, dy=-5, hdx=-6, hdy=-6, hrot=-14, open=1.0, aL=(-34, -78), aR=(-38, -80), bL=-8, bR=-8),
             P0(rot=26, dx=12, dy=8, hdx=16, hdy=12, hrot=16, open=0.8, aL=(34, 12), aR=(30, 16), bL=6, bR=6),
             P0(rot=18, dx=8, dy=6, hdx=12, hdy=10, hrot=12, open=0.4, aL=(26, 18), aR=(22, 22), bL=4, bR=4)]
        S = [P0(sq=1.0, dy=-4, hdy=-2, hrot=-4, open=0.9, aL=(-4, -70), aR=(4, -70), bL=-12, bR=-12),
             P0(sq=1.02, dy=-6, hdy=-6, hrot=-6, open=1.0, aL=(-8, -88), aR=(8, -88), bL=-14, bR=-14),
             P0(sq=0.92, dy=8, hdy=22, open=0.8, aL=(8, -26), aR=(-8, -26), bL=-6, bR=-6),
             P0(sq=0.95, dy=6, hdy=16, open=0.4, aL=(6, -12), aR=(-6, -12), bL=-4, bR=-4)]
    else:
        E = [P0(rot=-4, hdx=-6, hdy=-4, hrot=-10, open=0.85, aL=(-14, -44), aR=(-10, -48), bL=-10, bR=-10),
             P0(rot=1, hdx=-1, hdy=-7, hrot=-12, open=1.0, aL=(-3, -60), aR=(-6, -62), bL=-12, bR=-12),
             P0(rot=22 * fast, dx=10, hdx=22, hdy=11, hrot=15, open=1.0, aL=(26, -8), aR=(22, -2), bL=8, bR=8),
             P0(rot=15, dx=6, hdx=26, hdy=17, hrot=22, open=0.3, aL=(16, 12), aR=(10, 14), bL=6, bR=6)]
        S = [P0(hdy=-3, hrot=-5, open=0.85, aL=(-8, -52), aR=(8, -52), bL=-10, bR=-10),
             P0(hdy=-7, hrot=-7, open=1.0, aL=(-14, -66), aR=(14, -66), bL=-14, bR=-14),
             P0(sq=0.95, hdy=18, hrot=0, open=1.0, aL=(12, -34), aR=(-12, -34), bL=-6, bR=-6, bsx=1.04),
             P0(sq=0.96, hdy=24, open=0.3, aL=(8, -12), aR=(-8, -12), bL=-4, bR=-4)]
    if view == "E":
        return E[k]
    p = S[k]
    if view == "N":
        p = dict(p)
        p["hdy"] = -p["hdy"] * 0.4
        p["aL"] = (p["aL"][0], p["aL"][1] * 0.8)
        p["aR"] = (p["aR"][0], p["aR"][1] * 0.8)
    return p


def pose_hurt(kind, view, k, n, L):
    if view == "E":
        return [P0(rot=-15, dx=-4, hdx=-12, hdy=-4, hrot=-24, open=1.0, aL=(-16, -42), aR=(-10, -48), bL=-12, bR=-12),
                P0(rot=-5, dx=-2, hdx=-5, hrot=-9, open=0.7, aL=(-6, -16), aR=(-4, -14), bL=-6, bR=-6)][k]
    sgn = 1 if L["i"] % 2 else -1
    return [P0(rot=9 * sgn, dx=-4 * sgn, hdy=-4, hdx=-8 * sgn, hrot=-16 * sgn, open=1.0, aL=(-12, -36), aR=(12, -30), bL=-10, bR=-10),
            P0(rot=3 * sgn, hdx=-3 * sgn, hrot=-6 * sgn, open=0.7, aL=(-6, -12), aR=(6, -10), bL=-5, bR=-5)][k]


def pose_fall(kind, k, L, forward=True, rise=False):
    """The standing figure (side view, with legs) at fall progress u; the whole picture is then turned about the feet by fall_turn."""
    u = [0.12, 0.36, 0.62, 0.86, 1.0][k] if not rise else [0.97, 0.74, 0.44, 0.16][k]
    sg = 1.0 if forward else -1.0
    if rise:
        # pushing up off the ground: the arms are down, the head lifts
        return u, P0(rot=0, hdy=-6 * u, hrot=-20 * (1 - u), open=0.8, aL=(-14 * u, 16 * u + 6), aR=(-20 * u, 20 * u + 6), bL=0, bR=0, legs=dict(kb=10 * (1 - u), spread=2))
    flail = sn(u * 5)
    return u, P0(rot=sg * 10 * u, hdx=sg * 6 * u, hdy=4 * u, hrot=sg * 26 * u, open=1.0 if u < 0.7 else 0.5,
                 aL=(sg * (-8 - 22 * flail) * (1 - 0.4 * u), -28 * (1 - u) * (1 if forward else 1.3)), aR=(sg * (-12 + 20 * flail) * (1 - 0.4 * u), -34 * (1 - u)),
                 bL=sg * 8, bR=-sg * 8, legs=dict(kb=sg * 12 * min(1.0, u * 2.5), spread=3 * u), dy=min(1.0, u * 2.2) * 6)


_CORPSE_CENTER = {}


def corpse_center(L, pose):
    key = (L["i"], pose)
    if key not in _CORPSE_CENTER:
        im = Image.open(os.path.join(rw.PAWNS, "zrc%d_%d.png" % (L["i"], pose))).convert("RGBA")
        bb = im.getchannel("A").point(lambda v: 255 if v > 90 else 0).getbbox()
        _CORPSE_CENTER[key] = ((bb[0] + bb[2]) / 2.0, (bb[1] + bb[3]) / 2.0)
    return _CORPSE_CENTER[key]


def fall_turn(canvas, u, forward, L, kind):
    """Turn a standing picture about the feet toward the fall, and slide it to where the corpse lies on the last frame."""
    sg = 1.0 if forward else -1.0
    th = sg * 90.0 * (u ** 1.15) * (1.0 + 0.0)
    out = new_canvas()
    place(out, canvas, 0, 0, c=FEET, t=(0, 0), th=th)
    # lying at the end: head ends on the side it fell toward; the corpse picture is head left (back) or, mirrored, head right
    pose = 1 if forward else 0
    cc = corpse_center(L, pose)
    tcx = cc[0] if not forward else CW - cc[0]
    bb = out.getchannel("A").point(lambda v: 255 if v > 90 else 0).getbbox()
    if bb is None:
        return out
    cur = ((bb[0] + bb[2]) / 2.0 / SS, (bb[1] + bb[3]) / 2.0 / SS)
    w = max(0.0, (u - 0.25) / 0.75) ** 1.4
    t = ((tcx - cur[0]) * w, (cc[1] - cur[1]) * w - 3 * u)
    res = new_canvas()
    place(res, out, 0, 0, c=FEET, t=t)
    return res


# ------------------------------------------------------------------ the crawler
def crawler(L, view, anim, k, n):
    """A torso that has lost its legs: dragged by the arms, the spine trailing. Own drawing (not the standing layers)."""
    rng = random.Random(L["i"] * 53 + ord(view))
    canvas = new_canvas()
    fv = FV[L["i"]]
    skin, top = L["skin"], L["top"]
    sc = rw.sleeve_col(L)
    ph = 2 * math.pi * k / n
    s, c = sn(ph), math.cos(ph)
    if anim == "walk":
        p = dict(lunge=5 * s, dy=-2 * abs(c), arm=s, hd=3 * c, open=0.6)
    elif anim == "idle":
        p = dict(lunge=0, dy=1.5 * s, arm=0.1 * s, hd=2 * s, open=[0.4, 0.55, 0.8, 0.5][k % 4])
    elif anim == "attack":
        q = [(-6, 0), (-10, -8), (18, 10), (10, 14)][k]
        p = dict(lunge=q[0], dy=q[1] * 0.3, arm=[-1.4, -1.6, 1.5, 0.6][k], hd=q[0] * 1.4, open=[0.8, 1.0, 1.0, 0.3][k])
    elif anim == "hurt":
        p = dict(lunge=-8 if k == 0 else -3, dy=-3, arm=-1.2 if k == 0 else -0.4, hd=-9 if k == 0 else -3, open=1.0)
    else:      # death: it sinks flat
        u = [0.2, 0.45, 0.7, 0.9, 1.0][k]
        p = dict(lunge=-12 * u, dy=9 * u, arm=-0.8 * (1 - u), hd=-12 * u, open=0.8 * (1 - u), flat=u)
    fl = p.get("flat", 0.0)
    oy = 230 + p["dy"]
    if view == "E":
        W = Win(30, 150, 308, 150)
        # the torn end, spine and a smear trailing behind
        tx = CX - 66 + p["lunge"] * 0.4
        flat(W, ell_m(W, tx - 30, oy + 30, 56, 9), rw.BLOOD_D, 210)
        put(W, capsule_m(W, (tx, oy), (tx - 48, oy + 22), 8, 5), rw.BONE, ow=3.2, shade=False)
        for q in range(5):
            put(W, ell_m(W, tx - 6 - q * 9, oy + 4 + q * 4.4, 4.6, 4.2), rw.BONE, ow=2.6, shade=False)
        # far arm (dragging), torso, near arm
        fa = (CX + 22 + p["lunge"], oy - 6)
        put_arm = lambda W_, sh, hd, bend, far: rw.arm(W_, L, sh, hd, rng, False, 24, bend)
        Wf = Win(30, 150, 308, 150)
        hand_f = (CX + 70 + 22 * (-p["arm"]) + p["lunge"], oy + 26 - 8 * max(0, -p["arm"]))
        put_arm(Wf, fa, hand_f, 10, True)
        canvas.alpha_composite(darken(Wf.img, 0.78), (Wf.x0 * SS, Wf.y0 * SS))
        tm = rw.poly_m(W, rw.smooth_poly([(tx - 4, oy - 26), (CX + 22 + p["lunge"] * 0.6, oy - 34 + fl * 14), (CX + 36 + p["lunge"] * 0.6, oy - 6), (CX + 20, oy + 22), (tx - 2, oy + 24)], 2))
        put(W, tm, top)
        flat(W, ell_m(W, CX - 18, oy, 22, 14), rw.BLOOD_D, 200, clip=tm)
        flat(W, poly_m(W, [(tx - 4, oy - 26), (tx + 8, oy - 26), (tx + 8, oy + 24), (tx - 4, oy + 24)]), rw.BLOOD, clip=tm)
        canvas.alpha_composite(W.img, (W.x0 * SS, W.y0 * SS))
        Wn = Win(30, 150, 308, 150)
        hand_n = (CX + 62 + 24 * p["arm"] + p["lunge"], oy + 30 - 10 * max(0, p["arm"]))
        put_arm(Wn, (CX + 8 + p["lunge"], oy - 8), hand_n, -10, False)
        canvas.alpha_composite(Wn.img, (Wn.x0 * SS, Wn.y0 * SS))
        hx, hy = CX + 52 + p["lunge"] + p["hd"] * 0.6, oy - 34 + 8 * fl + (6 if anim != "walk" else 2) - fl * 4
        hw = zh.head2(L, "E", hx, hy, fv, p["open"])
        tmp = new_canvas()
        place(tmp, hw.img, hw.x0, hw.y0, c=(hx, hy + 30), th=-(-4 + 0.3 * p["hd"] - 14 * fl), sx=0.92, sy=0.92)
        canvas.alpha_composite(tmp)
    else:
        sgn = 1 if view == "S" else -1
        W = Win(30, 150, 308, 150)
        if view == "N":
            hx, hy = CX + 2, oy - 30 + p["dy"] * 0.2
            hw = zh.head2(L, "N", hx, hy, fv, p["open"])
            tmp = new_canvas()
            place(tmp, hw.img, hw.x0, hw.y0, c=(hx, hy + 30), th=-0.3 * p["hd"], sx=0.9, sy=0.9)
            canvas.alpha_composite(tmp)
        # a trail of spine and a blood smear behind (toward the camera when seen from behind)
        by = oy + (30 if view == "N" else -14)
        flat(W, ell_m(W, CX, by + (14 if view == "N" else -6), 50, 10), rw.BLOOD_D, 200)
        if view == "N":
            for q in range(5):
                put(W, ell_m(W, CX + 2 - q * 2, by + 6 + q * 6, 5.4, 4.6), rw.BONE, ow=2.8, shade=False)
        tm = rw.poly_m(W, rw.smooth_poly([(CX - 52, oy - 22), (CX - 34, oy - 38 + fl * 12), (CX + 34, oy - 38 + fl * 12), (CX + 52, oy - 22), (CX + 46, oy + 12), (CX + 10, oy + 26), (CX - 10, oy + 26), (CX - 46, oy + 12)], 2))
        put(W, tm, top)
        flat(W, ell_m(W, CX + 6, oy, 18, 15), rw.BLOOD_D, 210, clip=tm)
        if view == "S":
            flat(W, poly_m(W, [(CX - 16, oy + 22), (CX + 16, oy + 22), (CX + 22, oy + 30), (CX - 22, oy + 30)]), rw.BLOOD, clip=None)
        canvas.alpha_composite(W.img, (W.x0 * SS, W.y0 * SS))
        for sd in (-1, 1):
            sw = p["arm"] * sd * (1 if view == "S" else -1)
            sh = (CX + sd * 46, oy - 20)
            hd = (CX + sd * (66 + 8 * sw), oy + 24 + (-14 * max(0, sw) if view == "S" else 8 * max(0, sw)) + (18 if view == "S" else -4))
            if view == "N":
                hd = (CX + sd * (64 + 6 * sw), oy + 6 - 10 * max(0, sw))
            Wa = Win(30, 150, 308, 150)
            rw.arm(Wa, L, sh, hd, rng, False, 26, sd * 8)
            canvas.alpha_composite(Wa.img, (Wa.x0 * SS, Wa.y0 * SS))
        if view == "S":
            hx, hy = CX + p["hd"] * 0.4, oy + 2 + p["dy"] * 0.2 + 10 * fl
            hw = zh.head2(L, "S", hx, hy, fv, p["open"])
            tmp = new_canvas()
            place(tmp, hw.img, hw.x0, hw.y0, c=(hx, hy + 30), th=-0.5 * p["hd"], sx=0.9, sy=0.9)
            canvas.alpha_composite(tmp)
    return canvas


# ------------------------------------------------------------------ finishing
def finish(canvas):
    """Dark outer line, a cold rim light on the upper-left edge, a darker ground contact; then half size (averaged down from 4x)."""
    a = canvas.getchannel("A")
    ring = a.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 90 else 0)    # about 1.5 canvas px outside the old outline
    base = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    base.paste(Image.new("RGBA", canvas.size, (16, 11, 9, 255)), mask=ring)
    base.alpha_composite(canvas)
    k = int(2.4 * SS)
    A = base.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rim = ImageChops.subtract(A, ImageChops.offset(A, k, k)).filter(ImageFilter.GaussianBlur(1.6)).point(lambda v: int(v * 0.5))
    base.paste(Image.new("RGBA", canvas.size, (118, 150, 184, 255)), mask=rim)
    return base.resize(HALF, Image.LANCZOS)


def trim(img):
    bb = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bb is None:
        return img.crop((0, 0, 1, 1)), (0, 0)
    bb = (max(0, bb[0] - 1), max(0, bb[1] - 1), min(img.width, bb[2] + 1), min(img.height, bb[3] + 1))
    return img.crop(bb), (bb[0], bb[1])


# ------------------------------------------------------------------ the sets
def frames_for(kind, look, with_views="SEN"):
    """Yields (key, image at the final size) for one look of one kind."""
    L = look_for(rw.load_looks()[look], kind)
    fv = FV[look]
    if kind == "crawler":
        for v in with_views:
            for anim, n in (("walk", 6), ("idle", 4), ("attack", 4), ("hurt", 2)):
                for k in range(n):
                    yield "%s/%s/%d" % (v, anim, k), finish(crawler(L, v, anim, k, n))
        for k in range(5):
            yield "E/death_f/%d" % k, finish(crawler(L, "E", "death", k, 5))
        return
    nwalk = KIND_WALK[kind]
    for v in with_views:
        for anim, n, fn in (("walk", nwalk, pose_walk), ("idle", 4, pose_idle), ("attack", 4, pose_attack), ("hurt", 2, pose_hurt)):
            for k in range(n):
                P = fn(kind, v, k, n, L)
                P["fv"] = fv
                yield "%s/%s/%d" % (v, anim, k), finish(figure(L, v, P, kind))
    for forward, name in ((True, "death_f"), (False, "death_b")):
        for k in range(5):
            u, P = pose_fall(kind, k, L, forward)
            P["fv"] = fv
            c = fall_turn(figure(L, "E", P, kind), u, forward, L, kind)
            yield "E/%s/%d" % (name, k), finish(c)
    for k in range(4):
        u, P = pose_fall(kind, k, L, True, True)
        P["fv"] = fv
        yield "E/rise/%d" % k, finish(fall_turn(figure(L, "E", P, kind), u, True, L, kind))


def pack(frames):
    """Shelf-pack trimmed frames into one atlas: returns (image, index {key: [x, y, w, h, ox, oy]})."""
    items = []
    for key, im in frames:
        t, off = trim(im)
        items.append((key, t, off))
    items.sort(key=lambda it: -it[1].height)
    width = 1024
    x = y = rowh = 0
    pos = {}
    for key, t, off in items:
        if x + t.width > width:
            x, y, rowh = 0, y + rowh, 0
        pos[key] = [x, y, t.width, t.height, off[0], off[1]]
        x += t.width
        rowh = max(rowh, t.height)
    atlas = Image.new("RGBA", (width, y + rowh), (0, 0, 0, 0))
    for key, t, off in items:
        p = pos[key]
        atlas.paste(t, (p[0], p[1]))
    return atlas, pos


def save_q(img, path):
    """A palette PNG (128 colours with alpha): flat-colour art loses nothing and the file is a fifth of the size (Godot decodes it to RGBA like any other)."""
    img.quantize(colors=128, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(path, optimize=True)


def build_one(args):
    kind, look = args
    atlas, pos = pack(frames_for(kind, look))
    save_q(atlas, os.path.join(OUT, "%s%d.png" % (kind, look)))
    return kind, look, pos, atlas.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", default="")
    ap.add_argument("--look", type=int, default=-1)
    ap.add_argument("--strips", default="")
    ap.add_argument("--faces", default="")
    ap.add_argument("--fx", action="store_true")
    ap.add_argument("--quant", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if a.fx:
        make_fx()
        return
    if a.quant:
        for f in sorted(os.listdir(OUT)):
            if f.endswith(".png") and f != "fx.png":
                save_q(Image.open(os.path.join(OUT, f)).convert("RGBA"), os.path.join(OUT, f))
        return
    if a.faces:
        faces_sheet(a.faces)
        return
    if a.strips:
        strips(a.strips, a.set or "walker", a.look if a.look >= 0 else 0)
        return
    sets = {"walker": WALKER_LOOKS, "runner": RUNNER_LOOKS, "brute": BRUTE_LOOKS, "crawler": CRAWLER_LOOKS}
    jobs = [(k, l) for k, ls in sets.items() if not a.set or a.set == k for l in ls if a.look < 0 or a.look == l]
    ip = os.path.join(OUT, "index.json")
    idx = json.load(open(ip)) if os.path.exists(ip) else {}
    with mp.Pool(8) as pool:
        for kind, look, pos, size in pool.imap_unordered(build_one, jobs):
            idx.setdefault(kind, {})[str(look)] = pos
            print(kind, look, size, flush=True)
    json.dump(idx, open(ip, "w"), separators=(",", ":"))


def make_fx():
    """The damage decals and gibs: 8 x 2 cells of 48 px (wounds 0-3, spray left and right, a ruined hand, a bite, four gibs, two drips)."""
    C = 48
    sheet = Image.new("RGBA", (C * 8, C * 2), (0, 0, 0, 0))
    B, BD, BL = rw.BLOOD, rw.BLOOD_D, rw.BLOOD_L

    def cell(i):
        return Win(0, 0, C, C), (i % 8) * C, (i // 8) * C

    def put_cell(W, i):
        sheet.alpha_composite(W.img.resize((C, C), Image.LANCZOS), ((i % 8) * C, (i // 8) * C))
    for i in range(4):         # a bullet wound: a dark hole, a wet rim, a run
        rng = random.Random(i * 11 + 3)
        W = Win(0, 0, C, C)
        pts = [(24 + math.cos(a / 9 * 6.283) * (11 + rng.uniform(-3, 4)), 24 + math.sin(a / 9 * 6.283) * (10 + rng.uniform(-3, 4))) for a in range(9)]
        flat(W, rw.smooth_poly and poly_m(W, rw.smooth_poly(pts, 2)), BD)
        flat(W, ell_m(W, 24, 24, 7.5, 7), B)
        flat(W, ell_m(W, 24, 24.5, 4.2, 4), (22, 6, 8))
        flat(W, ell_m(W, 21.5, 21.5, 2, 1.6), BL)
        flat(W, line_m(W, [(24 + rng.uniform(-3, 3), 29), (24 + rng.uniform(-4, 4), 41)], 3.6), B)
        for q in range(3):
            flat(W, ell_m(W, 24 + rng.uniform(-18, 18), 24 + rng.uniform(-16, 16), 1.8, 1.8), BD)
        put_cell(W, i)
    for side in (0, 1):          # a spray over the shoulder it came from
        rng = random.Random(40 + side)
        W = Win(0, 0, C, C)
        sg = -1 if side == 0 else 1
        for q in range(9):
            a = math.radians(-60 + q * 15) + (math.pi if sg < 0 else 0)
            ln = rng.uniform(10, 22)
            x0, y0 = 24 - sg * 6, 26
            flat(W, line_m(W, [(x0, y0), (x0 + math.cos(a) * ln * 0.9, y0 + math.sin(a) * ln * 0.9)], rng.uniform(2.2, 4.6)), B if q % 2 else BD)
            flat(W, ell_m(W, x0 + math.cos(a) * (ln + 3), y0 + math.sin(a) * (ln + 3), 1.8, 1.8), BD)
        flat(W, ell_m(W, 24 - sg * 6, 26, 7, 6), BD)
        put_cell(W, 4 + side)
    W = Win(0, 0, C, C)          # a ruined hand: a red mass with bone and drips
    flat(W, ell_m(W, 24, 22, 14, 11), BD)
    flat(W, ell_m(W, 24, 22, 10, 8), B)
    flat(W, ell_m(W, 26, 21, 3.6, 3), rw.BONE)
    for dx in (-8, -1, 7):
        flat(W, line_m(W, [(24 + dx, 28), (24 + dx + 1, 40 + (dx % 3) * 2)], 4), B)
    put_cell(W, 6)
    W = Win(0, 0, C, C)          # a bite: a ring of teeth marks in red
    flat(W, ell_m(W, 24, 24, 17, 14), BD)
    flat(W, ell_m(W, 24, 24, 12, 9), B)
    for q in range(8):
        a = q / 8 * 6.283
        flat(W, ell_m(W, 24 + math.cos(a) * 15, 24 + math.sin(a) * 12, 2.4, 2.4), (210, 190, 160))
    put_cell(W, 7)
    skin = rw.SKINS[0]
    W = Win(0, 0, C, C)          # gib: a hand
    put(W, ell_m(W, 22, 26, 9, 8), skin, ow=3.4)
    for q in range(4):
        put(W, capsule_m(W, (28 + q * 2, 20 + q * 4), (40 + q, 16 + q * 6), 5.4, 4.2), skin, ow=2.6, shade=False)
    flat(W, ell_m(W, 14, 27, 5, 6), B)
    put_cell(W, 8)
    W = Win(0, 0, C, C)          # a chunk of meat
    put(W, poly_m(W, rw.smooth_poly([(10, 24), (18, 12), (32, 14), (40, 26), (30, 36), (16, 35)], 2)), (150, 40, 44), ow=3.6)
    flat(W, ell_m(W, 24, 24, 6, 5), (200, 90, 90))
    put_cell(W, 9)
    W = Win(0, 0, C, C)          # a bone
    put(W, capsule_m(W, (10, 30), (38, 18), 8, 8), rw.BONE, ow=3.2)
    put(W, ell_m(W, 9, 32, 6, 5), rw.BONE, ow=3.2, shade=False)
    put(W, ell_m(W, 39, 16, 6, 5), rw.BONE, ow=3.2, shade=False)
    flat(W, ell_m(W, 23, 24, 4, 3), B)
    put_cell(W, 10)
    W = Win(0, 0, C, C)          # a rag of torn cloth and flesh
    put(W, poly_m(W, [(8, 28), (20, 16), (30, 20), (40, 14), (38, 28), (26, 34), (12, 36)]), (170, 80, 76), ow=3.4)
    flat(W, line_m(W, [(14, 28), (36, 20)], 2), (110, 40, 44))
    put_cell(W, 11)
    for i in (0, 1):
        W = Win(0, 0, C, C)
        flat(W, ell_m(W, 20 + i * 8, 24, 5, 4), BD)
        flat(W, ell_m(W, 30 - i * 6, 28, 3.4, 3), B)
        put_cell(W, 12 + i)
    sheet.save(os.path.join(OUT, "fx.png"), optimize=True)


def strips(path, kind, look, scale=3):
    """Every pose of one look as rows: S, E, N (walk, idle, attack, hurt), then the E falls and rise."""
    rows = []
    cur = {}
    for key, im in frames_for(kind, look):
        cur[key] = im
    order = []
    for v in "SEN":
        order.append([k for k in cur if k.startswith(v + "/")])
    order.append([k for k in cur if k.startswith("E/death_f")] + [k for k in cur if k.startswith("E/rise")])
    order.append([k for k in cur if k.startswith("E/death_b")])
    order = [r for r in order if r]
    wrapped = []
    for r in order:
        for q in range(0, len(r), 12):
            wrapped.append(r[q:q + 12])
    order = wrapped
    box = (14, 30, 176, 150)
    bw, bh = box[2] - box[0], box[3] - box[1]
    cols = max(len(r) for r in order)
    sheet = Image.new("RGBA", (cols * bw * scale, len(order) * bh * scale), (74, 84, 66, 255))
    for j, r in enumerate(order):
        for i, k in enumerate(r):
            im = cur[k].crop(box).resize((bw * scale, bh * scale), Image.NEAREST)
            sheet.alpha_composite(im, (i * bw * scale, j * bh * scale))
    sheet.save(path)


def faces_sheet(path):
    base = rw.load_looks()
    cols = zh.N_FACES
    sheet = Image.new("RGBA", (cols * 128, 6 * 128), (74, 84, 66, 255))
    for si in range(6):
        for fv in range(cols):
            L = dict(base[[2, 1, 0, 4, 3, 8][si]])
            L["skin"] = rw.SKINS[si]
            L["eyes"] = ["pale", "dark", "red", "white", "dark", "pale"][si]
            hw = zh.head2(L, "S", 184, 152, fv, 0.6)
            sm = hw.img.resize((hw.w, hw.h), Image.LANCZOS).crop((12, 12, 140, 140))
            sheet.alpha_composite(sm, (fv * 128, si * 128))
    sheet.save(path)


if __name__ == "__main__":
    main()
