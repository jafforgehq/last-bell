"""ROUND 11: the faces of the dead. head2() draws one head of the RimWorld-style set with a face variant (13 of them), a mouth that opens by a fraction, and eye holes and a mouth a pixel or two
bigger than Round 10 so the face reads at 1x. Used by tools/make_zombie_anim.py (the layered parts: head, body, arms, legs, are posed there and packed into atlases)."""
import math
import random

from PIL import ImageChops

import make_rimworld_zombies as rw
from make_rimworld_zombies import (BLOOD, BLOOD_D, BLOOD_L, BONE, OL, SOCKET, TEETH, Win, capsule_m, ell_m, flat, line_m, mulc, poly_m, put, smooth_poly)

FACE_NAMES = ["grim", "hanging jaw", "no jaw", "two-tone eyes", "empty socket", "glazed", "skull patch", "bandaged", "scream", "cheek hole", "stitched", "sunken", "peeled"]
N_FACES = len(FACE_NAMES)
BANDAGE = (222, 214, 190)


def eyes_of(L, fv):
    """(left eye, right eye) kinds for the S view, by the face variant."""
    k = L["eyes"]
    if fv == 3:
        return "pale", "red"
    if fv == 4:
        return "red", "missing"
    if fv == 5:
        return "glazed", "glazed"
    if fv == 8:
        return "wide", "wide"
    if fv == 11:
        return "dark", "dark"
    return k, k


def eye(W, kind, x, y, side, big=1.0):
    """A sunken eye hole (bigger than Round 10) and what is in it."""
    rx, ry = 13.0 * big, 11.0 * big
    put(W, ell_m(W, x, y, rx, ry), SOCKET, outline=True, shade=False, ow=3.4)
    flat(W, ell_m(W, x, y + 8, 13, 3.6), (74, 66, 92), 100)
    if kind == "missing":
        flat(W, ell_m(W, x, y + 1, rx - 3, ry - 3), (14, 6, 8))
        flat(W, ell_m(W, x - 1, y + 3, 5, 4), BLOOD_D)
        flat(W, line_m(W, [(x + 2, y + 9), (x + 3, y + 26)], 4), BLOOD)
        flat(W, ell_m(W, x + 3, y + 28, 3.4, 4.6), BLOOD)
        return
    ball = {"pale": (232, 228, 196), "dark": (214, 210, 186), "red": (214, 214, 196), "white": (240, 240, 232), "glazed": (232, 238, 234), "wide": (240, 238, 226)}[kind]
    er = 7.4 if kind != "wide" else 8.8
    flat(W, ell_m(W, x, y, er, er * 0.92), ball)
    if kind == "red":
        flat(W, ell_m(W, x, y, er, er * 0.92), (206, 40, 36))
        flat(W, ell_m(W, x - 1.5, y - 1.5, 2.8, 2.5), (255, 168, 138))
    elif kind in ("white", "glazed"):
        flat(W, ell_m(W, x, y, er, er * 0.92), (226, 234, 230))
        flat(W, ell_m(W, x - 2, y - 2, 2.4, 2), (255, 255, 255))
        flat(W, line_m(W, [(x - 5, y + 2), (x + 3, y - 4)], 1.2), (180, 190, 196), 160)
    elif kind == "wide":
        flat(W, ell_m(W, x - side * 0.5, y + 0.5, 3.2, 3.6), (22, 14, 14))
        flat(W, line_m(W, [(x - 6, y - 2), (x - 3, y + 3)], 1.0), (190, 60, 56), 200)
        flat(W, line_m(W, [(x + 6, y - 1), (x + 3, y + 4)], 1.0), (190, 60, 56), 200)
    else:
        flat(W, ell_m(W, x - side * 0.7, y + 0.8, 3.0, 3.4), (22, 16, 16))
    flat(W, line_m(W, [(x - 11, y - 8.5), (x + 11, y - 9)], 2.2), (24, 16, 18), 200)


def mouth2(W, x, y, rx, ry, jaw_hang=False, grin=False):
    """An open mouth: top lip fixed, the lower jaw down by `ry`; teeth above, a tongue and the dark throat. y is the CENTRE."""
    put(W, ell_m(W, x, y, rx, ry), (40, 8, 12), shade=False, ow=3.4)
    cl = ell_m(W, x, y, rx - 0.5, ry - 0.5)
    flat(W, ell_m(W, x, y + ry * 0.35, rx * 0.62, ry * 0.5), (132, 36, 42), clip=cl)
    if ry > 9:
        flat(W, ell_m(W, x, y + ry * 0.62, rx * 0.44, ry * 0.26), (176, 66, 70), clip=cl)
    n = 6 if rx > 13 else 4
    th = 5.0 + min(5.0, ry * 0.35)
    for k in range(n):
        tx = x - rx * 0.8 + (2 * rx * 0.8) * k / (n - 1)
        h = th if k % 2 == 0 else th * 0.72
        if grin and k % 3 == 2:
            continue
        flat(W, poly_m(W, [(tx - 2, y - ry), (tx + 2, y - ry), (tx + 0.9, y - ry + h), (tx - 0.9, y - ry + h)]), TEETH, clip=cl)
    if ry > 6.5:
        for k in range(4):
            tx = x - rx * 0.55 + rx * 0.37 * k
            if jaw_hang and k == 2:
                continue
            flat(W, poly_m(W, [(tx - 1.8, y + ry), (tx + 1.8, y + ry), (tx + 0.7, y + ry - 4.4), (tx - 0.7, y + ry - 4.4)]), TEETH, clip=cl)
    flat(W, line_m(W, [(x - rx + 1, y - 1), (x - rx + 4, y + 3)], 2.0), BLOOD, 230)


def head2(L, view, hx, hy, fv, open_=0.55, R=38, twitch=0.0):
    """One head layer (a Win): S the face, E the profile, N the back. fv: the face variant (0 to 12); open_: how wide the mouth is, 0 shut to 1 as wide as it goes."""
    W = Win(hx - 76, hy - 74, 152, 170)
    rng = random.Random(L["i"] * 31 + ord(view) + fv * 7)
    skin = L["skin"]
    sk_d = mulc(skin, 0.72)
    if fv in (1, 2, 8):
        open_ = max(open_, 0.9 if fv != 2 else 0.5)
    ry = 5.0 + 12.5 * open_
    if view == "N":
        rw.hair_back(W, L, hx, hy, R, rng)
        back_marks(W, L, fv, hx, hy, R, rng)
        return W
    clipm = ell_m(W, hx, hy, R - 1, R)
    s = view == "S"
    mx = hx + (3 if L["tilt"] > 0 else -3) if s else hx + 28
    my = hy + 15 + ry   # the top lip stays, the jaw goes down
    if fv == 1:     # the jaw hangs: a long chin
        put(W, ell_m(W, hx if s else hx + 10, hy + 36, 22 if s else 18, 17), skin)
    put(W, ell_m(W, hx, hy, R, R * 1.03), skin)
    if not s:
        put(W, ell_m(W, hx - 9, hy + 3, 7, 8), mulc(skin, 0.94), ow=4.5)
    if s:
        for sx in (-1, 1):
            flat(W, ell_m(W, hx + sx * 28, hy + 12, 9, 15), sk_d, 170 if fv != 11 else 255, clip=clipm)
        flat(W, ell_m(W, hx, hy - 31, 22, 8), mulc(skin, 0.86), 130, clip=clipm)
        kl, kr = eyes_of(L, fv)
        eye(W, kl, hx - 15, hy - 3, 1)
        eye(W, kr, hx + 15, hy - 3, -1)
        up = -3 if fv == 8 else 0
        for sx in (-1, 1):
            flat(W, line_m(W, [(hx + sx * 26, hy - 15 + (2 if sx > 0 else 0) + up), (hx + sx * 7, hy - 15 + up * 2)], 3.8), OL)
        # nose: a dark split, a hole when sunken
        if fv == 11:
            flat(W, poly_m(W, [(hx, hy + 4), (hx - 5, hy + 13), (hx + 5, hy + 13)]), (20, 10, 12))
        else:
            flat(W, poly_m(W, [(hx - 3, hy + 4), (hx + 3, hy + 4), (hx + 1.2, hy + 12), (hx - 1.2, hy + 12)]), sk_d)
        rx = 16.5 if fv != 8 else 19
        if fv == 11:
            mouth2(W, mx, hy + 24, 17, 7, grin=True)
        elif fv == 2:
            pass
        else:
            mouth2(W, mx, my, rx, ry, jaw_hang=fv == 1)
    else:
        flat(W, ell_m(W, hx + 22, hy + 10, 9, 14), sk_d, 170, clip=clipm)
        kind = eyes_of(L, fv)[1 if fv in (4, 3) else 0]
        eye(W, kind, hx + 18, hy - 3, 1)
        flat(W, line_m(W, [(hx + 29, hy - 14), (hx + 9, hy - 15)], 3.8), OL)
        flat(W, poly_m(W, [(hx + R - 4, hy + 3), (hx + R + 3, hy + 10), (hx + R - 5, hy + 12)]), sk_d)
        if fv == 11:
            mouth2(W, hx + 28, hy + 24, 12, 7, grin=True)
        elif fv != 2:
            mouth2(W, hx + 27, my, 13.5 if fv != 8 else 15, ry, jaw_hang=fv == 1)
    # the scar of each face
    face_marks(W, L, fv, view, hx, hy, R, clipm, rng, mx, my, ry)
    if L["bruise"] and fv not in (6, 7):
        flat(W, ell_m(W, hx - 18, hy + 6, 12, 9), (96, 90, 132), 120, clip=clipm)
    # blood from the mouth
    if fv != 2:
        bx = mx
        flat(W, line_m(W, [(bx + 5, my + ry - 1), (bx + 6, my + ry + 12)], 6), BLOOD)
        flat(W, ell_m(W, bx + 6, my + ry + 15, 3.6, 5), BLOOD)
        flat(W, line_m(W, [(bx - 7, my + ry - 1), (bx - 7, my + ry + 6)], 3.4), BLOOD)
    rw.hair_front(W, L, view, hx, hy, R, rng)
    top_marks(W, L, fv, view, hx, hy, R, clipm, rng)
    return W


def face_marks(W, L, fv, view, hx, hy, R, clipm, rng, mx, my, ry):
    s = view == "S"
    skin = L["skin"]
    if fv == 2:     # no lower jaw: torn flesh, bone stumps, a long tongue
        lower = ImageChops.invert(ell_m(W, hx, hy - 6, R + 12, R - 2)) if False else None
        cut = poly_m(W, [(hx - 60, hy + 20), (hx + 60, hy + 20), (hx + 60, hy + 90), (hx - 60, hy + 90)])
        W.img.paste((0, 0, 0, 0), mask=cut)
        pts = [(hx - 34, hy + 19)]
        for k in range(1, 10):
            pts.append((hx - 34 + k * 7.6, hy + 19 + (rng.uniform(3, 11) if k % 2 else rng.uniform(-1, 3))))
        pts.append((hx + 34, hy + 19))
        put(W, poly_m(W, pts + [(hx + 22, hy + 14), (hx - 22, hy + 14)]), BLOOD, ow=4)
        mxx = hx if s else hx + 14
        for k in range(7):
            tx = mxx - 22 + k * 7.4
            flat(W, poly_m(W, [(tx - 2.4, hy + 19), (tx + 2.4, hy + 19), (tx + 0.8, hy + 29), (tx - 0.8, hy + 29)]), TEETH)
        put(W, capsule_m(W, (mxx + 3, hy + 22), (mxx + 5, hy + 52), 11, 8), (170, 62, 66), ow=3.4, shade=False)
        flat(W, line_m(W, [(mxx + 3, hy + 24), (mxx + 4, hy + 48)], 1.6), (210, 110, 110))
        for sx in (-1, 1):
            put(W, capsule_m(W, (hx + sx * 30, hy + 19), (hx + sx * 33, hy + 30), 6, 4), BONE, ow=2.6, shade=False)
        flat(W, line_m(W, [(mxx + 8, hy + 46), (mxx + 8, hy + 66)], 3), BLOOD)
    elif fv == 9:   # a hole in the cheek with the teeth behind it
        cxx, cyy = (hx + 24, hy + 13) if s else (hx + 8, hy + 14)
        pts = smooth_poly([(cxx - 10, cyy), (cxx - 5, cyy - 8), (cxx + 5, cyy - 7), (cxx + 11, cyy), (cxx + 5, cyy + 8), (cxx - 6, cyy + 7)], 1)
        put(W, poly_m(W, pts), BLOOD, ow=3.6, shade=False)
        flat(W, ell_m(W, cxx, cyy, 6, 4.4), (30, 8, 12))
        for k in range(3):
            flat(W, poly_m(W, [(cxx - 5 + k * 4, cyy - 3), (cxx - 2.6 + k * 4, cyy - 3), (cxx - 3.4 + k * 4, cyy + 2)]), TEETH)
    elif fv == 10:  # a long scar with stitches
        if s:
            a, b = (hx + 30, hy - 20), (hx - 8, hy + 20)
        else:
            a, b = (hx + 28, hy - 22), (hx + 6, hy + 14)
        flat(W, line_m(W, [a, b], 3.2), BLOOD_D, clip=clipm)
        for k in range(1, 6):
            t = k / 6.0
            px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            flat(W, line_m(W, [(px - 5, py - 3.4), (px + 5, py + 3.4)], 1.7), (30, 24, 24), clip=clipm)
    elif fv == 12:  # peeled: red muscle over the cheek and jaw line
        cxx = hx - 20 if s else hx + 16
        pts = smooth_poly([(cxx - 12, hy - 8), (cxx + 8, hy - 12), (cxx + 12, hy + 12), (cxx + 2, hy + 30), (cxx - 12, hy + 24)], 1)
        put(W, poly_m(W, pts), (150, 44, 46), ow=3.2, shade=False, clip=clipm)
        for k in range(3):
            flat(W, line_m(W, [(cxx - 8 + k * 6, hy - 6), (cxx - 6 + k * 5, hy + 24)], 1.6), (104, 24, 30), clip=clipm)
        flat(W, ell_m(W, cxx - 2, hy + 4, 4.4, 5), (210, 120, 110), clip=clipm)


def top_marks(W, L, fv, view, hx, hy, R, clipm, rng):
    """What sits on top of the hair: a bare skull patch, a bandage."""
    s = view == "S"
    if fv == 6:
        cxx = hx + (12 if s else 10)
        pts = smooth_poly([(cxx - 16, hy - 34), (cxx + 4, hy - 42), (cxx + 20, hy - 30), (cxx + 14, hy - 14), (cxx - 6, hy - 16)], 1)
        put(W, poly_m(W, pts), BLOOD_D, ow=3.4, shade=False, clip=ell_m(W, hx, hy, R + 1, R + 2))
        inner = smooth_poly([(cxx - 11, hy - 31), (cxx + 3, hy - 37), (cxx + 15, hy - 28), (cxx + 10, hy - 18), (cxx - 5, hy - 20)], 1)
        flat(W, poly_m(W, inner), BONE, clip=ell_m(W, hx, hy, R + 1, R + 2))
        flat(W, line_m(W, [(cxx - 6, hy - 30), (cxx + 2, hy - 24), (cxx + 10, hy - 28)], 1.6), mulc(BONE, 0.6))
        flat(W, line_m(W, [(cxx + 2, hy - 24), (cxx + 3, hy - 19)], 1.6), mulc(BONE, 0.6))
        flat(W, line_m(W, [(cxx + 14, hy - 16), (cxx + 17, hy - 4)], 3.4), BLOOD)
    elif fv == 7:
        ang = -0.22
        c, sn = math.cos(ang), math.sin(ang)
        def rp(x, y):
            return (hx + x * c - y * sn, hy - 10 + x * sn + y * c)
        band = poly_m(W, [rp(-R - 3, -9), rp(R + 3, -9), rp(R + 3, 9), rp(-R - 3, 9)])
        put(W, ImageChops.multiply(band, ell_m(W, hx, hy, R + 2, R + 3)), BANDAGE, ow=3.4)
        for k in range(-3, 4):
            flat(W, line_m(W, [rp(k * 11, -9), rp(k * 11 + 6, 9)], 1.4), mulc(BANDAGE, 0.8), 200, clip=ell_m(W, hx, hy, R, R))
        flat(W, ell_m(W, rp(10, 0)[0], rp(10, 0)[1], 8, 7), BLOOD, 230, clip=ell_m(W, hx, hy, R, R))
        flat(W, ell_m(W, rp(10, 0)[0], rp(10, 0)[1], 4, 3.4), BLOOD_D, 255)
        if view != "E":
            put(W, capsule_m(W, rp(-R, 4), (rp(-R, 4)[0] - 8, rp(-R, 4)[1] + 26), 9, 6), BANDAGE, ow=3, shade=False)


def back_marks(W, L, fv, hx, hy, R, rng):
    if fv == 6:
        pts = smooth_poly([(hx - 12, hy - 28), (hx + 8, hy - 34), (hx + 18, hy - 20), (hx + 4, hy - 8), (hx - 10, hy - 14)], 1)
        put(W, poly_m(W, pts), BLOOD_D, ow=3.2, shade=False)
        flat(W, poly_m(W, smooth_poly([(hx - 7, hy - 25), (hx + 6, hy - 30), (hx + 13, hy - 20), (hx + 2, hy - 12), (hx - 6, hy - 16)], 1)), BONE)
        flat(W, line_m(W, [(hx - 4, hy - 22), (hx + 5, hy - 18)], 1.6), mulc(BONE, 0.6))
    elif fv == 7:
        band = poly_m(W, [(hx - R - 3, hy - 20), (hx + R + 3, hy - 14), (hx + R + 3, hy + 2), (hx - R - 3, hy - 4)])
        put(W, ImageChops.multiply(band, ell_m(W, hx, hy, R + 2, R + 3)), BANDAGE, ow=3.4)
        put(W, capsule_m(W, (hx + 4, hy - 8), (hx - 8, hy + 20), 9, 6), BANDAGE, ow=3, shade=False)
        flat(W, ell_m(W, hx + 16, hy - 8, 6, 5), BLOOD, 230)
    elif fv == 10:
        flat(W, line_m(W, [(hx - 14, hy - 24), (hx + 14, hy + 4)], 3.0), BLOOD_D)
        for k in range(1, 6):
            t = k / 6.0
            px, py = hx - 14 + 28 * t, hy - 24 + 28 * t
            flat(W, line_m(W, [(px - 4, py + 3), (px + 4, py - 3)], 1.6), (30, 24, 24))
    elif fv == 12:
        flat(W, ell_m(W, hx + 10, hy - 6, 11, 9), (150, 44, 46))
        flat(W, ell_m(W, hx + 10, hy - 6, 5, 4), (210, 120, 110))
