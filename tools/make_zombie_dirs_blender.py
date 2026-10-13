"""Prison experiment, round 8: the zombie art set. Headless Blender renders of a rigged chibi zombie (same camera, size, toon ramp and 160 px to the tile as tools/make_pawn_dirs_blender.py).

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/make_zombie_dirs_blender.py -- <outdir> <set>[,<set>...] [--px=320] [--only=pose,pose] [--quick]

A set is "<kind>_<look>" (walker_0 .. walker_7, runner_0 .. 3, brute_0 .. 3, crawler_0 .. 3; see LOOKS and KINDS below). Output: <outdir>/<set>/<pose>_f<frame>_d<dir>.png (colour) and
i<pose>_f<frame>_d<dir>.png (a flat colour for each body part, which the packer turns into the thin lines between parts). tools/pack_zombie_dirs.py packs them.
Units as in the pawn script: 1 Blender unit = 1 tile of screen, the figure stretched by 1/cos(elevation), forward is -y, heading i of 16 faces the screen angle i * 22.5 degrees
(0 east, 4 south, 8 west, 12 north: PawnNode._ori). The figure is a joint tree of empties (fall, body, spine, head, jaw, shoulders, elbows, hips): a pose is a dictionary of joint angles
(POSES below), so a new look or pose is data, not modelling. Heights come from the look's `s`, the hunch from `hunch`, the dragged foot from `drag` (+1 right, -1 left).
"""
import bpy, math, os, sys, random
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0]
WANT = argv[1].split(",") if len(argv) > 1 and not argv[1].startswith("--") else None
OPT = {a.split("=")[0]: a.split("=")[1] for a in argv if a.startswith("--") and "=" in a}
PX = float(OPT.get("--px", 320))
ELEV = math.radians(16.0)
ONLY_POSE = OPT["--only"].split(",") if "--only" in OPT else None
ONLY_DIR = [int(x) for x in OPT["--dir"].split(",")] if "--dir" in OPT else None
QUICK = "--quick" in argv           # one frame, a few headings: for looking at a model

# ---------------------------------------------------------------------------------------------------------------- the looks
# One shared rig, different clothes, skin, hair and damage. Every key is optional.
#  skin       skin tone (the whole figure is a pale, grey-green dead one)      top, under   the garment and what shows under it     pants, shoes
#  style      shirt | scrubs | jumpsuit | uniform | hoodie | cardigan | dress | vest      sleeves  "long" | "rolled" (forearms bare) | "torn" (one arm bare)
#  hair       bald short messy matted long ponytail thin     hairColor     hat  cap | hardhat | guard | beanie | hood     hatColor
#  tie        tie colour    blood 0..1 (stains and drips)     chest  open ribs      gash  a bite on the shoulder      cheek  a torn cheek     eyes  dead eye on this side (+1/-1)
#  s height scale   w torso width     hunch  forward lean of the spine     tilt  head roll     lop  shoulder drop on one side (+1/-1)     jaw  slack jaw 0..1     drag  dragged foot
LOOKS = {
    "walker": [
        {"name": "office", "skin": "#9aa38c", "style": "shirt", "top": "#c8c4b4", "under": "#c8c4b4", "pants": "#3a3f4c", "shoes": "#25201c", "sleeves": "rolled", "tie": "#6a2a34", "hair": "thin", "hairColor": "#4a3c30",
         "blood": 0.55, "chest": False, "gash": True, "s": 1.0, "w": 0.95, "hunch": 0.42, "tilt": 0.30, "lop": 1, "jaw": 0.8, "drag": 1, "eyes": 1},
        {"name": "labourer", "skin": "#a39a7a", "style": "vest", "top": "#6a6860", "under": "#6a6860", "outer": "#d8782a", "pants": "#3c4660", "shoes": "#3a3028", "sleeves": "torn", "hair": "short", "hairColor": "#3a2c22", "hat": "hardhat", "hatColor": "#d8b02a",
         "blood": 0.4, "cheek": True, "s": 1.06, "w": 1.12, "hunch": 0.32, "tilt": -0.22, "lop": -1, "jaw": 0.55, "drag": -1, "eyes": -1},
        {"name": "nurse", "skin": "#a8aca0", "style": "scrubs", "top": "#4aa0a0", "under": "#4aa0a0", "pants": "#3e8c8c", "shoes": "#d8d4cc", "sleeves": "long", "hair": "ponytail", "hairColor": "#2a2018",
         "blood": 0.85, "chest": True, "s": 0.97, "w": 0.9, "hunch": 0.38, "tilt": 0.18, "lop": -1, "jaw": 1.0, "drag": 1, "eyes": 1},
        {"name": "prisoner", "skin": "#8f9c88", "style": "jumpsuit", "top": "#d8661e", "under": "#d8661e", "pants": "#d8661e", "shoes": "#2c2824", "sleeves": "torn", "hair": "bald", "hairColor": "#2a2018",
         "blood": 0.6, "gash": True, "cheek": True, "s": 1.04, "w": 1.0, "hunch": 0.36, "tilt": -0.3, "lop": 1, "jaw": 0.7, "drag": -1, "eyes": -1},
        {"name": "guard", "skin": "#9ba48f", "style": "uniform", "top": "#2c3c5c", "under": "#2c3c5c", "pants": "#1e2838", "shoes": "#141414", "sleeves": "long", "hair": "short", "hairColor": "#2a2018", "hat": "guard", "hatColor": "#1c2638",
         "blood": 0.5, "chest": False, "gash": True, "s": 1.08, "w": 1.08, "hunch": 0.30, "tilt": 0.2, "lop": 1, "jaw": 0.6, "drag": 1, "eyes": 1},
        {"name": "kid", "skin": "#a8a894", "style": "hoodie", "top": "#b83a3a", "under": "#b83a3a", "pants": "#3a4a6c", "shoes": "#e0dcd0", "sleeves": "long", "hair": "messy", "hairColor": "#6a4a2a", "hat": "hood", "hatColor": "#b83a3a",
         "blood": 0.5, "s": 0.74, "w": 0.9, "hunch": 0.30, "tilt": 0.35, "lop": -1, "jaw": 0.9, "drag": -1, "eyes": -1},
        {"name": "elder", "skin": "#b0aa98", "style": "cardigan", "top": "#d0c8b0", "under": "#d0c8b0", "outer": "#8a6a4a", "pants": "#6a5c4a", "shoes": "#2a2420", "sleeves": "long", "hair": "thin", "hairColor": "#e0dcd0",
         "blood": 0.3, "cheek": True, "s": 0.92, "w": 0.9, "hunch": 0.62, "tilt": 0.4, "lop": 1, "jaw": 1.0, "drag": 1, "eyes": 1},
        {"name": "dress", "skin": "#8c9a96", "style": "dress", "top": "#7a8cb0", "under": "#7a8cb0", "pants": "#7a8cb0", "shoes": "#5a3a3a", "sleeves": "torn", "hair": "long", "hairColor": "#6a4a2a",
         "blood": 0.7, "gash": True, "s": 0.98, "w": 0.88, "hunch": 0.34, "tilt": -0.26, "lop": 1, "jaw": 0.85, "drag": -1, "eyes": -1},
    ],
    "runner": [
        {"name": "jogger", "skin": "#b0b49c", "style": "hoodie", "top": "#3a6aa0", "under": "#3a6aa0", "pants": "#2a2c34", "shoes": "#d8d0c0", "sleeves": "long", "hair": "short", "hairColor": "#2a2018", "blood": 0.6, "s": 0.95, "w": 0.8, "hunch": 0.4, "tilt": 0.2, "lop": 1, "jaw": 1.0, "eyes": 1},
        {"name": "clerk", "skin": "#a8a894", "style": "shirt", "top": "#d4d0c0", "under": "#d4d0c0", "pants": "#4a4a54", "shoes": "#2a2420", "sleeves": "rolled", "tie": "#3a4a8a", "hair": "messy", "hairColor": "#3a2c22", "blood": 0.7, "gash": True, "s": 0.97, "w": 0.8, "hunch": 0.4, "tilt": -0.2, "lop": -1, "jaw": 1.0, "eyes": -1},
        {"name": "inmate", "skin": "#98a490", "style": "jumpsuit", "top": "#d8661e", "under": "#d8661e", "pants": "#d8661e", "shoes": "#2c2824", "sleeves": "torn", "hair": "bald", "hairColor": "#2a2018", "blood": 0.65, "cheek": True, "s": 0.96, "w": 0.82, "hunch": 0.42, "tilt": 0.3, "lop": 1, "jaw": 1.0, "eyes": 1},
        {"name": "scrubs", "skin": "#a6aa9c", "style": "scrubs", "top": "#4aa0a0", "under": "#4aa0a0", "pants": "#3e8c8c", "shoes": "#d8d4cc", "sleeves": "long", "hair": "long", "hairColor": "#5a3a2a", "blood": 0.8, "chest": True, "s": 0.92, "w": 0.78, "hunch": 0.38, "tilt": -0.25, "lop": -1, "jaw": 1.0, "eyes": -1},
    ],
    "brute": [
        {"name": "bruiser", "skin": "#8c9684", "style": "vest", "top": "#5a5a58", "under": "#5a5a58", "outer": "#c8702a", "pants": "#3a3a40", "shoes": "#222018", "sleeves": "torn", "hair": "bald", "hairColor": "#2a2018", "blood": 0.7, "gash": True, "s": 1.0, "w": 1.0, "hunch": 0.5, "tilt": 0.25, "lop": 1, "jaw": 0.8, "eyes": 1, "brute": True},
        {"name": "warden", "skin": "#98a08c", "style": "uniform", "top": "#2c3c5c", "under": "#2c3c5c", "pants": "#1e2838", "shoes": "#141414", "sleeves": "long", "hair": "short", "hairColor": "#2a2018", "hat": "guard", "hatColor": "#1c2638", "blood": 0.55, "s": 1.0, "w": 1.0, "hunch": 0.45, "tilt": -0.2, "lop": -1, "jaw": 0.7, "eyes": -1, "brute": True},
        {"name": "orange", "skin": "#8a9684", "style": "jumpsuit", "top": "#d8661e", "under": "#d8661e", "pants": "#d8661e", "shoes": "#2c2824", "sleeves": "torn", "hair": "bald", "hairColor": "#2a2018", "blood": 0.8, "cheek": True, "gash": True, "s": 1.0, "w": 1.05, "hunch": 0.5, "tilt": 0.3, "lop": 1, "jaw": 0.9, "eyes": 1, "brute": True},
        {"name": "butcher", "skin": "#a0a088", "style": "cardigan", "top": "#c8c4b4", "under": "#c8c4b4", "outer": "#6a4036", "pants": "#4a4234", "shoes": "#2a2420", "sleeves": "long", "hair": "matted", "hairColor": "#3a2c22", "blood": 1.0, "chest": True, "s": 1.0, "w": 1.0, "hunch": 0.55, "tilt": -0.3, "lop": -1, "jaw": 1.0, "eyes": -1, "brute": True},
    ],
    "crawler": [
        {"name": "crawl_office", "skin": "#9aa38c", "style": "shirt", "top": "#c8c4b4", "under": "#c8c4b4", "pants": "#3a3f4c", "sleeves": "rolled", "tie": "#6a2a34", "hair": "thin", "hairColor": "#4a3c30", "blood": 0.8, "s": 1.0, "w": 0.95, "tilt": 0.2, "jaw": 1.0, "eyes": 1},
        {"name": "crawl_nurse", "skin": "#a8aca0", "style": "scrubs", "top": "#4aa0a0", "under": "#4aa0a0", "pants": "#3e8c8c", "sleeves": "long", "hair": "ponytail", "hairColor": "#2a2018", "blood": 0.9, "chest": True, "s": 0.97, "w": 0.9, "tilt": -0.2, "jaw": 1.0, "eyes": -1},
        {"name": "crawl_inmate", "skin": "#8f9c88", "style": "jumpsuit", "top": "#d8661e", "under": "#d8661e", "pants": "#d8661e", "sleeves": "torn", "hair": "bald", "hairColor": "#2a2018", "blood": 0.7, "gash": True, "s": 1.02, "w": 1.0, "tilt": 0.3, "jaw": 0.9, "eyes": 1},
        {"name": "crawl_kid", "skin": "#a8a894", "style": "hoodie", "top": "#b83a3a", "under": "#b83a3a", "pants": "#3a4a6c", "sleeves": "long", "hair": "messy", "hairColor": "#6a4a2a", "hat": "hood", "hatColor": "#b83a3a", "blood": 0.6, "s": 0.78, "w": 0.9, "tilt": -0.3, "jaw": 1.0, "eyes": -1},
    ],
}
# per kind: the figure's scale (what the game draws it at, so that the sprite is not scaled again), the render cell (tiles) and the frames of the walk
KINDS = {
    "walker": {"scale": 1.0, "cell": 2.4, "walk": 8},
    "runner": {"scale": 0.92, "cell": 2.4, "walk": 6},
    "brute": {"scale": 1.55, "cell": 3.2, "walk": 6},
    "crawler": {"scale": 1.0, "cell": 2.4, "walk": 6},
}
DIRS16 = 16
DIRS8 = 8


def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c]


def mix(a, b, t):
    ca = [int(a.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    return "#%02x%02x%02x" % tuple(int(x + (y - x) * t) for x, y in zip(ca, cb))


def shade(h, k):
    c = [int(h.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v * k))) for v in c)


bpy.ops.wm.read_factory_settings(use_empty=True)
sce = bpy.context.scene
COL = bpy.data.collections.new("zombie")
sce.collection.children.link(COL)
MATS = {}
RAMP = [(0.0, 0.80), (0.4, 0.92), (0.7, 1.0), (1.0, 1.07)]


def mat(h):
    if h in MATS:
        return MATS[h]
    m = bpy.data.materials.new(h)
    m.diffuse_color = (*lin(h), 1.0)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    mul.inputs[6].default_value = (*lin(h), 1.0)
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "LINEAR"
    el = ramp.color_ramp.elements
    el[0].position, el[0].color = RAMP[0][0], (RAMP[0][1],) * 3 + (1,)
    el[1].position, el[1].color = RAMP[-1][0], (RAMP[-1][1],) * 3 + (1,)
    for pos, v in RAMP[1:-1]:
        e = el.new(pos)
        e.color = (v, v, v, 1)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], sep.inputs[0])
    nt.links.new(sep.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], mul.inputs[7])
    nt.links.new(mul.outputs[2], em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs[0])
    MATS[h] = m
    return m


def id_mat(g):
    key = "id%d" % g
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    c = {1: (1, 0, 0), 2: (0, 1, 0), 3: (0, 0, 1), 4: (1, 1, 0), 5: (1, 0, 1), 6: (0, 1, 1), 7: (1, 1, 1)}[g]
    em.inputs[0].default_value = (*c, 1.0)
    nt.links.new(em.outputs[0], out.inputs[0])
    MATS[key] = m
    return m


def tmat(rot, t):
    return Matrix.Translation(t)


# ------------------------------------------------------------------------------------------------------------------- the rig
HEAD_Z, HR = 0.545, 0.268
HIP_Z = -0.12
SOLE_Z = -0.345
G_HEAD, G_TORSO, G_LEG, G_ARML, G_ARMR, G_JAW, G_LEGR = 1, 2, 3, 4, 5, 6, 7


class Z:
    def __init__(self, kind, look):
        self.kind = kind
        self.L = L = look
        self.rnd = random.Random(hash(look["name"]) & 0xffff)
        self.parts = []
        self.joint_rest = {}
        sc = KINDS[kind]["scale"] * float(L.get("s", 1.0))
        self.root = self.empty("root", None, (0, 0, 0))
        self.root.scale = (1.0, 1.0, 1.0 / math.cos(ELEV))
        self.rot = self.empty("rot", self.root, (0, 0, 0))
        self.fall = self.empty("fall", self.rot, (0, 0, 0))
        self.fall.scale = (sc, sc, sc)
        self.body = self.empty("body", self.fall, (0, 0, HIP_Z))
        self.spine = self.empty("spine", self.body, (0, 0, HIP_Z + 0.02))
        self.neck = self.empty("neck", self.spine, (0, 0, 0.26))
        self.jaw = self.empty("jaw", self.neck, (0, -0.1, HEAD_Z - 0.12))
        self.sh = {}
        self.el = {}
        self.hip = {}
        self.cr = kind == "crawler"
        self.brute = kind == "brute"
        W = float(L.get("w", 1.0)) * (1.38 if self.brute else 1.0)
        self.W = W
        lop = float(L.get("lop", 0))
        for sg in (1, -1):
            drop = -0.05 * lop * sg if lop else 0.0     # the lopsided shoulder: one drops
            sx = sg * (0.31 * W + (0.04 if self.brute else 0.0))
            self.sh[sg] = self.empty("sh%d" % sg, self.spine, (sx, -0.02, 0.17 + drop))
            ar = 0.2 * (1.25 if self.brute else 1.0)
            self.el[sg] = self.empty("el%d" % sg, self.sh[sg], (sx, -0.02, 0.17 + drop - ar))
            if not self.cr:
                self.hip[sg] = self.empty("hip%d" % sg, self.body, (sg * 0.105 * (1.3 if self.brute else 1.0), 0, HIP_Z))
        self.mskin = mat(L["skin"])
        self.mskin_d = mat(shade(L["skin"], 0.72))
        self.mtop = mat(L.get("outer") or L["top"])
        self.mund = mat(L["under"])
        self.mpant = mat(L["pants"])
        self.mshoe = mat(L.get("shoes", "#2a2420"))
        self.mhair = mat(L.get("hairColor", "#2a211c"))
        self.mblood = mat("#6e1713")
        self.mbloodd = mat("#4a0f0d")
        self.mflesh = mat("#8a2a28")
        self.mbone = mat("#d9d2bc")
        self.mink = mat("#1a1411")
        self.mwhite = mat("#e4e0d0")
        self.build()
        for o in self.parts:
            pass

    # -- scene helpers
    def empty(self, name, parent, loc):
        e = bpy.data.objects.new(name, None)
        COL.objects.link(e)
        e.rotation_mode = "XYZ"
        if parent is not None:
            e.parent = parent
            pr = self.joint_rest.get(parent.name, Vector((0, 0, 0)))
            e.location = Vector(loc) - pr
            self.joint_rest[name] = Vector(loc)
        else:
            self.joint_rest[name] = Vector((0, 0, 0))
        return e

    def fin(self, o, m, j, grp, smooth=True):
        for c in list(o.users_collection):
            c.objects.unlink(o)
        COL.objects.link(o)
        o.data.materials.append(m)
        for p in o.data.polygons:
            p.use_smooth = smooth
        o.parent = j
        o.matrix_parent_inverse = Matrix.Translation(-self.joint_rest[j.name])
        o["grp"] = grp
        self.parts.append(o)
        return o

    def sph(self, j, grp, loc, r, m, seg=18, rot=None):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(6, seg // 2), radius=1.0, location=loc)
        o = bpy.context.active_object
        o.scale = r if isinstance(r, (tuple, list)) else (r, r, r)
        if rot:
            o.rotation_euler = rot
        return self.fin(o, m, j, grp)

    def box(self, j, grp, loc, size, rad, m, seg=3, taper=1.0, rot=None):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        o = bpy.context.active_object
        o.scale = size
        bpy.ops.object.transform_apply(scale=True)
        if taper != 1.0:
            for v in o.data.vertices:
                v.co.x *= 1.0 - (1.0 - taper) * (0.5 - v.co.z / size[2])
        b = o.modifiers.new("b", "BEVEL")
        b.width = rad
        b.segments = seg
        b.limit_method = "NONE"
        bpy.ops.object.modifier_apply(modifier="b")
        if rot:
            o.rotation_euler = rot
        return self.fin(o, m, j, grp)

    def cyl(self, j, grp, loc, r, depth, m, verts=12, rot=None, r2=None):
        if r2 is None:
            bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
        else:
            bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc)
        o = bpy.context.active_object
        if rot:
            o.rotation_euler = rot
        return self.fin(o, m, j, grp)

    # -- the build
    def build(self):
        L, W = self.L, self.W
        brute = self.brute
        style = L["style"]
        tz = 0.05
        th = 0.42
        # torso
        self.box(self.spine, G_TORSO, (0, 0, tz), (0.66 * W, 0.40 * (1.1 if brute else 1.0), th), 0.12, self.mtop if style not in ("jumpsuit",) else self.mund, 4, taper=0.82)
        if brute:
            # big shoulders: a hump across the top
            self.sph(self.spine, G_TORSO, (0, 0.03, 0.2), (0.4 * W, 0.22, 0.13), self.mtop, 16)
        # the garment details
        if style == "shirt":
            self.box(self.spine, G_TORSO, (0, -0.02, 0.255), (0.28, 0.26, 0.07), 0.03, self.mund, 2)
            if L.get("tie"):
                self.box(self.spine, G_TORSO, (0.02, -0.205, 0.07), (0.055, 0.025, 0.28), 0.01, mat(L["tie"]), 2, rot=(0, 0.1, 0))
        elif style == "scrubs":
            self.sph(self.spine, G_TORSO, (0, -0.19, 0.2), (0.12, 0.05, 0.075), self.mskin, 12)
            self.box(self.spine, G_TORSO, (0.17, -0.205, 0.08), (0.07, 0.02, 0.09), 0.006, mat("#e8f0f0"), 1)
        elif style == "jumpsuit":
            self.box(self.spine, G_TORSO, (0, -0.205, 0.05), (0.03, 0.02, 0.4), 0.006, mat("#2a2018"), 1)
            self.box(self.spine, G_TORSO, (0.17, -0.207, 0.1), (0.1, 0.012, 0.07), 0.004, mat("#e8e0cc"), 1)
            self.box(self.spine, G_TORSO, (0, -0.02, 0.255), (0.3, 0.26, 0.06), 0.025, self.mund, 2)
        elif style == "uniform":
            self.box(self.spine, G_TORSO, (-0.16, -0.205, 0.11), (0.06, 0.016, 0.07), 0.005, mat("#c8a43a"), 1)
            self.box(self.spine, G_TORSO, (0, -0.0, -0.14), (0.62 * W, 0.4, 0.05), 0.012, mat("#16181c"), 2)
            self.box(self.spine, G_TORSO, (0, -0.205, -0.14), (0.07, 0.018, 0.05), 0.005, mat("#b8a050"), 1)
            for sg in (1, -1):
                self.box(self.spine, G_TORSO, (sg * 0.26 * W, 0.0, 0.245), (0.14, 0.12, 0.03), 0.01, mat("#c8a43a"), 1)
            self.box(self.spine, G_TORSO, (0, -0.02, 0.255), (0.28, 0.26, 0.07), 0.03, mat("#d8d4c4"), 2)
        elif style == "hoodie":
            self.box(self.spine, G_TORSO, (0, -0.2, -0.06), (0.4, 0.04, 0.14), 0.02, mat(shade(L["top"], 0.82)), 2)
            self.sph(self.spine, G_TORSO, (0, 0.17, 0.2), (0.24, 0.15, 0.12), mat(shade(L["top"], 0.9)), 14)
        elif style == "cardigan":
            self.box(self.spine, G_TORSO, (0, -0.19, 0.04), (0.2, 0.06, 0.4), 0.025, self.mund, 3)
            for i in range(3):
                self.sph(self.spine, G_TORSO, (-0.05, -0.222, 0.12 - i * 0.11), 0.018, mat("#2a2018"), 8)
            self.box(self.spine, G_TORSO, (0, -0.02, 0.255), (0.3, 0.26, 0.06), 0.025, self.mund, 2)
        elif style == "vest":
            self.box(self.spine, G_TORSO, (0, -0.0, 0.05), (0.675 * W, 0.405, 0.4), 0.115, mat(L["outer"]), 4, taper=0.82)
            self.box(self.spine, G_TORSO, (0, -0.0, 0.05), (0.19, 0.42, 0.405), 0.03, mat(L["top"]), 2)      # the gap between the two panels
            for zz in (-0.04, 0.12):
                self.box(self.spine, G_TORSO, (0, -0.0, zz), (0.67 * W, 0.415, 0.05), 0.012, mat("#d8dcc0"), 1, taper=0.9)
            self.box(self.spine, G_TORSO, (0, -0.02, 0.255), (0.28, 0.26, 0.07), 0.03, mat(L["top"]), 2)
        elif style == "dress":
            self.cyl(self.body, G_TORSO, (0, 0, HIP_Z - 0.08), 0.255, 0.22, self.mtop, 16, r2=0.37)
            self.box(self.spine, G_TORSO, (0, -0.0, -0.08), (0.5 * W, 0.34, 0.05), 0.012, mat(shade(L["top"], 0.7)), 2)
        # torn clothing: a dark ragged hem, and open tears showing skin / flesh
        self.rags()
        if L.get("chest"):
            # an open chest: flesh, ribs, a dark cavity
            self.sph(self.spine, G_TORSO, (0.02, -0.2, 0.08), (0.17, 0.03, 0.15), self.mbloodd, 14)
            self.sph(self.spine, G_TORSO, (0.02, -0.215, 0.08), (0.135, 0.02, 0.12), self.mflesh, 14)
            for i in range(3):
                self.box(self.spine, G_TORSO, (0.02, -0.232, 0.145 - i * 0.065), (0.2, 0.016, 0.022), 0.006, self.mbone, 1, rot=(0, 0.18 * (1 if i % 2 else -1), 0))
        if L.get("gash"):
            sg = 1 if L.get("lop", 1) < 0 else -1
            self.sph(self.spine, G_TORSO, (sg * 0.27 * W, -0.12, 0.2), (0.1, 0.07, 0.07), self.mflesh, 12)
            self.sph(self.spine, G_TORSO, (sg * 0.27 * W, -0.15, 0.2), (0.06, 0.04, 0.045), self.mbloodd, 10)
        # blood stains: dark blots on the torso and drips
        bl = float(L.get("blood", 0.0))
        rnd = random.Random(int(sum(map(ord, L["name"]))))
        for i in range(int(bl * 7) + 1):
            self.sph(self.spine, G_TORSO, (rnd.uniform(-0.22, 0.22) * W, -0.2, rnd.uniform(-0.1, 0.22)), (rnd.uniform(0.04, 0.12), 0.018, rnd.uniform(0.035, 0.12)), self.mblood if i % 3 else self.mbloodd, 10)
        # legs
        if not self.cr:
            for sg in (1, -1):
                j = self.hip[sg]
                g = G_LEG if sg > 0 else G_LEGR
                lw = 0.15 * (1.45 if brute else 1.0)
                self.box(j, g, (sg * 0.105 * (1.3 if brute else 1.0), 0, HIP_Z - 0.085), (lw, 0.15 * (1.3 if brute else 1.0), 0.17), 0.05, self.mpant, 3)
                self.sph(j, g, (sg * 0.105 * (1.3 if brute else 1.0), -0.03, SOLE_Z + 0.04), (0.085 * (1.4 if brute else 1.0), 0.115, 0.055), self.mshoe, 12)
                if (L.get("drag", 0) == sg or rnd.random() < 0.3) and bl > 0.4:
                    self.sph(j, g, (sg * 0.105 * (1.3 if brute else 1.0), -0.075, HIP_Z - 0.09), (0.045, 0.02, 0.05), self.mblood, 8)
        else:
            # no legs: a ragged stump under the torso, trailing a smear
            self.sph(self.body, G_TORSO, (0, 0.0, HIP_Z - 0.07), (0.26, 0.17, 0.09), self.mpant, 12)
            self.sph(self.body, G_TORSO, (0, 0.04, HIP_Z - 0.14), (0.2, 0.15, 0.05), self.mflesh, 12)
        self.build_arms()
        self.build_head()
        self.build_hat()

    def rags(self):
        L = self.L
        rnd = random.Random(7 + int(sum(map(ord, L["name"]))))
        col = L.get("outer") or L["top"]
        if L["style"] == "dress":
            col = L["top"]
        dark = mat(shade(col, 0.82))
        # tatters hanging below the hem: flat strips, different lengths
        n = 6 if L["style"] != "dress" else 9
        for i in range(n):
            x = (i - (n - 1) / 2.0) / (n - 1) * 0.5 * self.W
            ln = rnd.uniform(0.04, 0.12)
            if L["style"] == "dress":
                continue
            self.box(self.spine, G_TORSO, (x, -0.17 + rnd.uniform(-0.03, 0.03), -0.17 - ln * 0.4), (0.07, 0.03, ln), 0.008, dark if i % 2 else self.mtop, 1, rot=(rnd.uniform(-0.2, 0.2), 0, rnd.uniform(-0.15, 0.15)))
        # a torn patch of bare belly and a torn sleeve edge
        if L.get("sleeves") != "long" or L["style"] in ("shirt", "cardigan"):
            self.sph(self.spine, G_TORSO, (-0.15 * self.W, -0.2, -0.1), (0.09, 0.02, 0.06), self.mskin_d, 10)
            self.sph(self.spine, G_TORSO, (-0.15 * self.W, -0.207, -0.1), (0.06, 0.012, 0.04), self.mflesh, 8)

    def build_arms(self):
        L = self.L
        brute = self.brute
        k = 1.3 if brute else 1.0
        sl = L.get("sleeves", "long")
        rr = 0.058 * (1.55 if brute else 1.0)
        ar = 0.2 * (1.25 if brute else 1.0)
        sleeve_m = self.mtop if L["style"] not in ("jumpsuit",) else self.mund
        if L["style"] == "vest":
            sleeve_m = mat(L["top"])
        for sg in (1, -1):
            grp = G_ARML if sg > 0 else G_ARMR
            js, je = self.sh[sg], self.el[sg]
            sx = self.joint_rest[js.name].x
            sz = self.joint_rest[js.name].z
            self.sph(js, grp, (sx, -0.02, sz), rr * 1.35, sleeve_m, 12)                          # the shoulder cap
            self.cyl(js, grp, (sx, -0.02, sz - ar / 2), rr, ar + 0.02, sleeve_m, 12)             # upper arm
            torn = sl == "torn" and sg == (1 if L.get("lop", 1) > 0 else -1)
            bare = sl in ("rolled",) or torn
            fm = self.mskin if bare else sleeve_m
            ez = self.joint_rest[je.name].z
            self.cyl(je, grp, (sx, -0.02, ez - ar / 2), rr * (0.88 if bare else 0.95), ar + 0.01, fm, 12)  # forearm
            self.sph(je, grp, (sx, -0.02, ez), rr * 1.02, sleeve_m, 10)                           # the elbow
            hz = ez - ar - 0.03
            self.sph(je, grp, (sx, -0.025, hz), 0.07 * (1.45 if brute else 1.0), self.mskin_d, 12)   # the hand
            self.sph(je, grp, (sx, -0.05, hz - 0.03), (0.045 * (1.4 if brute else 1.0), 0.04, 0.05), self.mskin_d, 8)
            if bare and float(L.get("blood", 0)) > 0.3:
                self.sph(je, grp, (sx, -0.07, ez - 0.07), (0.05, 0.02, 0.07), self.mblood, 8)
                self.sph(je, grp, (sx, -0.03, hz), 0.05, self.mblood, 8)
            if torn:
                # a ragged cuff on the torn arm: a flap of sleeve and a wound
                self.sph(js, grp, (sx, -0.07, sz - ar * 0.7), (0.04, 0.03, 0.09), self.mflesh, 8)
                self.box(js, grp, (sx, 0.0, sz - ar * 0.9), (0.09, 0.07, 0.05), 0.01, sleeve_m, 1, rot=(0, 0, 0.5))

    def build_head(self):
        L = self.L
        j = self.neck
        hj = self.neck
        skin = self.mskin
        self.sph(hj, G_HEAD, (0, 0.0, HEAD_Z), (HR, HR * 0.95, HR * 0.97), skin, 28)
        for sg in (1, -1):
            self.sph(hj, G_HEAD, (sg * HR * 0.97, 0.01, HEAD_Z - 0.01), (0.035, 0.045, 0.065), skin, 10)
        ez = HEAD_Z + 0.025
        dead = int(L.get("eyes", 1))
        # sunken sockets and uneven eyes: one big and low, one small and high; one clouded
        for sg in (1, -1):
            big = (sg == dead)
            ex = sg * 0.105
            zz = ez - 0.03 if big else ez + 0.022
            sx, sz = (0.062, 0.07) if big else (0.046, 0.05)
            self.sph(hj, G_HEAD, (ex, -HR * 0.9 + 0.012, zz), (sx * 1.35, 0.03, sz * 1.3), mat(mix(L["skin"], "#2a1c30", 0.55)), 12)          # the socket
            self.sph(hj, G_HEAD, (ex, -HR * 0.9 - 0.004, zz), (sx, 0.026, sz), mat("#e0dcc4") if not big else mat("#cfd2b0"), 12)
            if not big:
                self.sph(hj, G_HEAD, (ex + sg * 0.004, -HR * 0.9 - 0.022, zz - 0.004), (0.022, 0.012, 0.026), mat("#241a14"), 8)
            else:
                self.sph(hj, G_HEAD, (ex - sg * 0.012, -HR * 0.9 - 0.022, zz + 0.012), (0.026, 0.012, 0.03), mat("#8aa0a0"), 8)     # a clouded pupil
        # a heavy brow
        for sg in (1, -1):
            self.box(hj, G_HEAD, (sg * 0.105, -HR * 0.9, ez + (0.075 if sg == dead else 0.1)), (0.1, 0.03, 0.025), 0.01, mat(shade(L["skin"], 0.85)), 2, rot=(0, sg * 0.25, 0))
        # nose
        self.sph(hj, G_HEAD, (0, -HR * 0.97, HEAD_Z - 0.045), (0.04, 0.036, 0.04), mat(shade(L["skin"], 0.93)), 10)
        # the mouth: a dark gape, upper teeth, a slack jaw hanging under it
        jo = float(L.get("jaw", 0.7))
        self.sph(hj, G_HEAD, (0, -HR * 0.88, HEAD_Z - 0.115), (0.082, 0.04, 0.045 + 0.03 * jo), mat("#2a0a0c"), 12)
        self.box(hj, G_HEAD, (0, -HR * 0.92 - 0.01, HEAD_Z - 0.088), (0.09, 0.016, 0.02), 0.005, self.mwhite, 1)
        jw = self.jaw
        jz = self.joint_rest[jw.name]
        self.sph(jw, G_JAW, (0, -0.21, HEAD_Z - 0.205), (0.135, 0.095, 0.07), skin, 14)
        self.box(jw, G_JAW, (0, -0.255, HEAD_Z - 0.19), (0.085, 0.014, 0.014), 0.004, self.mwhite, 1)
        if float(L.get("blood", 0)) > 0.4:
            self.sph(jw, G_JAW, (0, -0.26, HEAD_Z - 0.24), (0.07, 0.03, 0.09), self.mblood, 8)       # blood down the chin
        if L.get("cheek"):
            self.sph(hj, G_HEAD, (-0.16 * (1 if dead > 0 else -1) * -1, -HR * 0.8, HEAD_Z - 0.09), (0.07, 0.03, 0.06), self.mflesh, 10)
            self.sph(hj, G_HEAD, (-0.16 * (1 if dead > 0 else -1) * -1, -HR * 0.83, HEAD_Z - 0.09), (0.045, 0.02, 0.04), self.mbloodd, 8)
        # a few veins / bruises
        self.sph(hj, G_HEAD, (-0.1 * dead, -HR * 0.86, HEAD_Z + 0.13), (0.07, 0.02, 0.045), mat(mix(L["skin"], "#5a4a78", 0.45)), 8)

    def build_hat(self):
        L = self.L
        hj = self.neck
        hs = L.get("hair", "short")
        hat = L.get("hat")
        hair = self.mhair
        zH = HEAD_Z
        rnd = random.Random(int(sum(map(ord, L["name"]))) + 3)
        s = HR / 0.31
        if hat == "hardhat":
            hm = mat(L["hatColor"])
            self.sph(hj, G_HEAD, (0, 0.02, zH + 0.1 * s + 0.01), (0.285, 0.28, 0.2), hm, 24)
            self.box(hj, G_HEAD, (0, -0.2, zH + 0.1), (0.34, 0.12, 0.022), 0.01, hm, 2, rot=(0.15, 0, 0))
            self.box(hj, G_HEAD, (0, 0.0, zH + 0.28), (0.07, 0.3, 0.03), 0.01, shade_m(hm, 0.9), 2)
            return
        if hat == "guard":
            hm = mat(L["hatColor"])
            self.sph(hj, G_HEAD, (0, 0.02, zH + 0.11), (0.29, 0.285, 0.18), hm, 24)
            self.box(hj, G_HEAD, (0, -0.235, zH + 0.2), (0.38, 0.15, 0.02), 0.008, mat("#0c0c10"), 2, rot=(-0.25, 0, 0))
            self.box(hj, G_HEAD, (0, -0.27, zH + 0.25), (0.07, 0.02, 0.05), 0.006, mat("#c8a43a"), 1)
            return
        if hat == "hood":
            hm = mat(L["hatColor"])
            self.sph(hj, G_HEAD, (0, 0.1, zH + 0.02), (0.3, 0.24, 0.26), hm, 20)       # the hood is down: a heap behind and over the head
            self.sph(hj, G_HEAD, (0, 0.0, zH + 0.17), (0.28, 0.27, 0.1), hm, 20)
            return
        if hat == "beanie":
            self.sph(hj, G_HEAD, (0, 0.02, zH + 0.1), (0.29, 0.285, 0.2), mat(L["hatColor"]), 22)
            return
        if hs == "bald":
            return
        if hs in ("short", "messy", "matted"):
            self.sph(hj, G_HEAD, (0, 0.035, zH + 0.085), (HR * 1.06, HR * 1.04, 0.2), hair, 22)
            if hs in ("messy", "matted"):
                for i in range(8):
                    a = rnd.uniform(0, math.tau)
                    self.sph(hj, G_HEAD, (math.cos(a) * 0.23, 0.04 + math.sin(a) * 0.19, zH + rnd.uniform(0.0, 0.2)), rnd.uniform(0.06, 0.1), hair, 8)
        elif hs == "thin":
            # a balding head: a few long strands over a bare crown and a fringe
            self.sph(hj, G_HEAD, (0, 0.11, zH + 0.0), (0.24, 0.12, 0.13), hair, 14)
            for i in range(7):
                a = rnd.uniform(-1.2, 1.2)
                self.cyl(hj, G_HEAD, (math.sin(a) * 0.22, 0.12 + abs(math.sin(a)) * 0.03, zH - 0.04 - rnd.uniform(0, 0.08)), 0.014, rnd.uniform(0.18, 0.3), hair, 6, rot=(0, rnd.uniform(-0.2, 0.2), 0))
        elif hs == "ponytail":
            self.sph(hj, G_HEAD, (0, 0.035, zH + 0.085), (HR * 1.05, HR * 1.04, 0.2), hair, 22)
            self.sph(hj, G_HEAD, (0, 0.15, zH - 0.02), (0.2, 0.17, 0.2), hair, 12)
            self.cyl(hj, G_HEAD, (0.03, 0.29, zH - 0.14), 0.05, 0.28, hair, 8, rot=(0.2, 0, 0.2))
        elif hs == "long":
            self.sph(hj, G_HEAD, (0, 0.04, zH + 0.085), (HR * 1.07, HR * 1.05, 0.2), hair, 22)
            self.sph(hj, G_HEAD, (0, 0.16, zH - 0.1), (0.32, 0.15, 0.34), hair, 16)
            for sg in (1, -1):
                for i in range(3):
                    self.cyl(hj, G_HEAD, (sg * (0.25 + 0.015 * i), 0.0 + 0.04 * i, zH - 0.14 - 0.03 * i), 0.026, 0.3 + 0.06 * i, hair, 6, rot=(0, sg * 0.06, 0))


def shade_m(m, k):
    c = m.diffuse_color
    return m


# ---------------------------------------------------------------------------------------------------------------------- poses
def D(x):
    return math.radians(x)


def pose_dict():
    return {
        "dz": 0.0, "dy": 0.0, "bp": 0.0, "br": 0.0, "by": 0.0,     # body: shift up / forward, pitch, roll, yaw
        "sp": 0.0, "sr": 0.0, "sy": 0.0,                                 # spine pitch (forward = +), roll, yaw
        "hp": 0.0, "hr": 0.0, "hy": 0.0, "jaw": 0.0,                      # head
        "al": (0.0, 0.0, 0.0), "ar": (0.0, 0.0, 0.0),                     # arm (+x side, -x side): forward angle, out roll, yaw
        "el": 0.0, "er": 0.0,                                              # elbow bend (forward)
        "ll": (0.0, 0.0), "lr": (0.0, 0.0),                               # leg swing (forward = +), lift
        "fall": 0.0, "flift": 0.0,                                         # whole-figure fall about the feet: forward (+) / backward (-)
    }


def apply(z, P):
    L = z.L
    ox = {"fall": z.fall, "body": z.body, "spine": z.spine, "neck": z.neck, "jaw": z.jaw}
    z.fall.rotation_euler = (P["fall"], 0, 0)
    z.fall.location = Vector((0, 0, P["flift"])) + Vector((0, 0, SOLE_Z)) * 0.0
    z.body.rotation_euler = (P["bp"], P["br"], P["by"])
    z.body.location = Vector((0, -P["dy"], P["dz"]))
    z.spine.rotation_euler = (P["sp"], P["sr"], P["sy"])
    z.neck.rotation_euler = (P["hp"], P["hr"] + float(L.get("tilt", 0)) * 0.5, P["hy"])
    z.jaw.rotation_euler = (P["jaw"], 0, 0)
    for sg, key in ((1, "al"), (-1, "ar")):
        f, out, yaw = P[key]
        z.sh[sg].rotation_euler = (-f, -sg * out, sg * yaw)
        z.el[sg].rotation_euler = (-(P["el"] if sg > 0 else P["er"]), 0, 0)
    if not z.cr:
        for sg, key in ((1, "ll"), (-1, "lr")):
            z.hip[sg].rotation_euler = (-P[key][0], 0, 0)
    # hips are children of body at rest location relative to body: set explicit
    if not z.cr:
        for sg in (1, -1):
            rest = z.joint_rest["hip%d" % sg] - z.joint_rest["body"]
            lift = (P["ll"] if sg > 0 else P["lr"])[1]
            z.hip[sg].location = rest + Vector((0, 0, lift))


def noise(f, n=8):
    return [1.0, 0.82, 1.12, 0.9, 1.05, 1.18, 0.78, 0.98][f % 8]


def walk_pose(z, f, nf):
    """The walk: shambler (8 irregular frames), runner (6, pumping), brute (6, heavy), crawler (6)."""
    P = pose_dict()
    L = z.L
    kind = z.kind
    p = f / nf * math.tau
    sn, cs = math.sin(p), math.cos(p)
    hunch = float(L.get("hunch", 0.35))
    drag = int(L.get("drag", 1))
    if kind == "walker":
        n = noise(f)
        P["sp"] = hunch + 0.05 * math.sin(2 * p + 0.6) * n
        P["bp"] = 0.04
        P["br"] = 0.10 * sn * n
        P["dz"] = -0.018 * abs(sn) * n
        P["sr"] = -0.07 * sn
        P["sy"] = 0.1 * sn
        P["hp"] = -0.28 + 0.08 * math.sin(2 * p + 1.0)
        P["hr"] = 0.12 * math.sin(p + 1.2) * n
        P["jaw"] = 0.18 + 0.1 * math.sin(2 * p)
        for sg, key in ((1, "al"), (-1, "ar")):
            ph = p + (0.0 if sg > 0 else 2.2)
            P[key] = (D(78 + 8 * math.sin(ph) * n - (10 if sg == -drag else 0)), D(12 + 6 * math.sin(ph + 1)), D(10 + 6 * math.sin(ph)))
        P["el"] = D(20 + 10 * math.sin(p + 0.5))
        P["er"] = D(32 + 12 * math.sin(p + 2.0))
        for sg, key in ((1, "ll"), (-1, "lr")):
            q = p + (0.0 if sg > 0 else math.pi)
            dragging = sg == drag
            amp = 0.26 if dragging else 0.46
            sw = amp * math.sin(q) * (n if not dragging else 1.0) - (0.1 if dragging else 0.0)
            lift = (0.012 if dragging else 0.05) * max(0.0, math.cos(q))
            P[key] = (sw, lift)
    elif kind == "runner":
        P["sp"] = 0.62 + 0.05 * sn
        P["bp"] = 0.1
        P["dz"] = 0.03 * abs(sn) - 0.02
        P["br"] = 0.07 * sn
        P["sy"] = 0.28 * sn
        P["hp"] = -0.5
        P["hr"] = 0.08 * sn
        P["jaw"] = 0.5
        for sg, key in ((1, "al"), (-1, "ar")):
            q = p + (0.0 if sg > 0 else math.pi)
            P[key] = (D(40 + 55 * math.sin(q)) - D(30), D(8), D(0))
        P["el"] = D(75)
        P["er"] = D(75)
        for sg, key in ((1, "ll"), (-1, "lr")):
            q = p + (0.0 if sg > 0 else math.pi)
            P[key] = (0.85 * math.sin(q), 0.12 * max(0.0, math.cos(q)) + 0.04)
    elif kind == "brute":
        P["sp"] = hunch + 0.06 * abs(sn)
        P["bp"] = 0.0
        P["dz"] = -0.03 * abs(sn)
        P["br"] = 0.09 * sn
        P["sy"] = 0.12 * sn
        P["sr"] = -0.08 * sn
        P["hp"] = -0.25
        P["hr"] = 0.06 * sn
        P["jaw"] = 0.25
        for sg, key in ((1, "al"), (-1, "ar")):
            q = p + (0.0 if sg > 0 else math.pi)
            P[key] = (D(30 + 22 * math.sin(q)), D(22), D(6))
        P["el"] = D(26)
        P["er"] = D(26)
        for sg, key in ((1, "ll"), (-1, "lr")):
            q = p + (0.0 if sg > 0 else math.pi)
            P[key] = (0.34 * math.sin(q), 0.025 * max(0.0, math.cos(q)))
    else:   # crawler: the torso lies forward on the ground, the arms pull
        P["fall"] = D(80)
        P["flift"] = 0.2
        P["sp"] = -0.3
        P["hp"] = -1.0 + 0.1 * sn
        P["hr"] = 0.12 * sn
        P["jaw"] = 0.4
        P["sy"] = 0.1 * sn
        for sg, key in ((1, "al"), (-1, "ar")):
            q = p + (0.0 if sg > 0 else math.pi)
            P[key] = (D(115 + 55 * math.sin(q)), D(28), D(-8))
        P["el"] = D(30 - 25 * math.sin(p))
        P["er"] = D(30 + 25 * math.sin(p))
    return P


def idle_pose(z, f, nf):
    P = walk_pose(z, 0, 1)
    p = f / nf * math.tau
    s = math.sin(p)
    L = z.L
    hunch = float(L.get("hunch", 0.35))
    if z.kind == "runner":
        hunch = 0.3
    if z.kind == "crawler":
        P = walk_pose(z, 0, 6)
        P["hp"] += 0.05 * s
        P["sy"] = 0.06 * s
        return P
    P["sp"] = hunch * (0.9 if z.kind != "runner" else 1.0) + 0.04 * s
    P["br"] = 0.05 * s
    P["sr"] = -0.03 * s
    P["hr"] = 0.1 * math.sin(p + 1.0)
    P["hp"] = -0.2 + 0.08 * math.cos(p)
    P["jaw"] = 0.25 + 0.12 * math.sin(p + 2)
    P["al"] = (D(45 + 10 * s), D(14), D(8))
    P["ar"] = (D(34 - 10 * s), D(14), D(8))
    P["el"] = D(25)
    P["er"] = D(30)
    P["ll"] = (0.0, 0.0)
    P["lr"] = (0.0, 0.0)
    P["dz"] = 0.0
    P["sy"] = 0.0
    return P


def attack_pose(z, f, nf):
    """rear back with the arms up, the peak, slam forward, recover."""
    P = walk_pose(z, 0, 1) if z.kind != "crawler" else walk_pose(z, 0, 6)
    hunch = float(z.L.get("hunch", 0.35))
    P["ll"] = (0.0, 0.0)
    P["lr"] = (0.0, 0.0)
    P["sy"] = 0.0
    P["br"] = 0.0
    P["dz"] = 0.0
    seq = [  # spine pitch, arms forward angle (up past 90 = overhead), out, elbow, head pitch, jaw, body forward shift
        (-0.18, 150, 18, 45, 0.1, 0.9, -0.03),
        (-0.3, 175, 22, 40, 0.0, 1.1, -0.05),
        (0.62 + hunch * 0.3, 95, 8, 8, -0.5, 1.2, 0.1),
        (hunch + 0.1, 70, 10, 30, -0.35, 0.7, 0.04),
    ]
    sp, a, out, el, hp, jaw, dy = seq[f % 4]
    if z.kind == "crawler":
        P["sp"] = -0.3 - sp * 0.6
        P["hp"] = -1.0 + hp * 0.3
        P["al"] = (D(115 + (a - 100) * 0.5), D(28), D(-8))
        P["ar"] = (D(115 + (a - 100) * 0.5), D(28), D(-8))
        P["jaw"] = jaw
        P["dy"] = dy
        return P
    P["sp"] = sp
    P["bp"] = 0.0 if f != 1 else -0.12
    P["hp"] = hp
    P["jaw"] = jaw
    P["dy"] = dy
    P["al"] = (D(a), D(out), D(6))
    P["ar"] = (D(a - 8), D(out), D(6))
    P["el"] = D(el)
    P["er"] = D(el + 8)
    if z.kind == "brute":
        P["al"] = (D(a * 0.95), D(out + 10), D(6))
        P["ar"] = (D(a * 0.95), D(out + 10), D(6))
    return P


def hurt_pose(z, f, nf):
    P = walk_pose(z, 0, 1) if z.kind != "crawler" else walk_pose(z, 0, 6)
    P["ll"] = (0.0, 0.0)
    P["lr"] = (0.0, 0.0)
    P["sy"] = 0.0
    P["br"] = 0.0
    P["dz"] = 0.0
    if z.kind == "crawler":
        P["fall"] = D(70)
        P["hp"] = -1.3
        P["jaw"] = 1.0
        P["hr"] = 0.3 if f == 0 else -0.3
        return P
    k = (0.75, 1.0)[f % 2]
    P["sp"] = -0.28 * k
    P["bp"] = 0.1 * k
    P["hp"] = -0.7 * k
    P["hr"] = (0.3 if f == 0 else -0.25)
    P["jaw"] = 1.1
    P["dy"] = -0.06 * k
    P["al"] = (D(60 * k), D(55 * k), D(10))
    P["ar"] = (D(40 * k), D(70 * k), D(10))
    P["el"] = D(60)
    P["er"] = D(70)
    P["ll"] = (0.0, 0.0)
    P["lr"] = (-0.25 * k, 0.0)
    return P


def death_pose(z, f, nf, back):
    """The collapse: the knees buckle, the body topples about the feet, forward (head first) or backward (shot), and lies."""
    P = idle_pose(z, 0, 4) if z.kind != "crawler" else walk_pose(z, 0, 6)
    steps = [0.2, 0.9, 1.45, 1.57]
    a = steps[f % 4]
    sgn = -1.0 if back else 1.0
    P["fall"] = a * sgn
    P["flift"] = 0.2 * math.sin(a) * (1.0 if z.kind != "crawler" else 0.5)
    if z.kind == "crawler":
        P["fall"] = (1.4 + 0.17 * f / 3.0) * sgn if not back else -(1.0 + 0.5 * f / 3.0)
    P["bp"] = 0.15 * (1 - f / 3.0)
    P["dz"] = -0.06 * (1 if f == 0 else 0)
    if back:
        P["sp"] = -0.2
        P["hp"] = -0.5
        P["al"] = (D(100 - 40 * f / 3.0), D(40 + 20 * f / 3.0), D(10))
        P["ar"] = (D(80 - 30 * f / 3.0), D(50 + 20 * f / 3.0), D(10))
        P["el"] = D(30)
        P["er"] = D(30)
    else:
        P["sp"] = 0.1 + 0.2 * f / 3.0 if f < 3 else 0.1
        P["hp"] = -0.2
        P["al"] = (D(100 + 60 * min(f, 2) / 2.0), D(30 + 30 * f / 3.0), D(10))
        P["ar"] = (D(90 + 70 * min(f, 2) / 2.0), D(35 + 30 * f / 3.0), D(10))
        P["el"] = D(20)
        P["er"] = D(25)
    P["jaw"] = 0.9
    P["ll"] = (0.2 * f / 3.0, 0.0)
    P["lr"] = (-0.15 * f / 3.0, 0.0)
    P["hr"] = 0.2 if f > 1 else 0.0
    return P


def make_pose(z, pose, f, nf):
    if pose == "walk":
        return walk_pose(z, f, nf)
    if pose == "idle":
        return idle_pose(z, f, nf)
    if pose == "attack":
        return attack_pose(z, f, nf)
    if pose == "hurt":
        return hurt_pose(z, f, nf)
    if pose == "deathf":
        return death_pose(z, f, nf, False)
    if pose == "deathb":
        return death_pose(z, f, nf, True)
    raise ValueError(pose)


# the poses of a set: name -> (frames, headings)
def pose_table(kind):
    return {"walk": (KINDS[kind]["walk"], DIRS16), "idle": (4 if kind == "walker" else 2, DIRS8), "attack": (4, DIRS8), "hurt": (2, DIRS8), "deathf": (4, DIRS8), "deathb": (3, DIRS8)}


# ------------------------------------------------------------------------------------------------------------------- render
def setup_render(cell):
    r = sce.render
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            r.engine = eng
            break
        except TypeError:
            pass
    try:
        sce.eevee.taa_render_samples = 16
    except Exception:
        pass
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.0
    so = bpy.data.objects.new("sun", sun)
    COL.objects.link(so)
    so.rotation_euler = (math.radians(55), 0, math.radians(-35))
    r.resolution_x = r.resolution_y = int(cell * PX)
    r.resolution_percentage = 100
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    sce.view_settings.view_transform = "Standard"
    sce.view_settings.look = "None"
    sce.display_settings.display_device = "sRGB"
    r.use_freestyle = False
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    COL.objects.link(cam)
    cd.type = "ORTHO"
    cd.ortho_scale = cell
    cd.clip_start = 0.1
    cd.clip_end = 100
    cam.rotation_euler = (math.pi / 2 - ELEV, 0, 0)
    d = 30.0
    cam.location = (0, -d * math.cos(ELEV), d * math.sin(ELEV))
    sce.camera = cam


def id_pass(z, path):
    meshes = [o for o in z.parts if o.type == "MESH"]
    saved = [(o, o.data.materials[0]) for o in meshes]
    for o in meshes:
        o.data.materials[0] = id_mat(int(o["grp"]))
    f0, t0, fl = sce.render.filter_size, sce.eevee.taa_render_samples, sce.render.filepath
    sce.render.filter_size = 0.0
    sce.eevee.taa_render_samples = 1
    sce.render.filepath = path
    bpy.ops.render.render(write_still=True)
    sce.render.filter_size, sce.eevee.taa_render_samples, sce.render.filepath = f0, t0, fl
    for o, m in saved:
        o.data.materials[0] = m


def main():
    names = WANT
    if names is None:
        names = ["%s_%d" % (k, i) for k, v in LOOKS.items() for i in range(len(v))]
    for name in names:
        kind, idx = name.rsplit("_", 1)
        look = LOOKS[kind][int(idx)]
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        MATS.clear()
        setup_render(KINDS[kind]["cell"])
        z = Z(kind, look)
        od = os.path.join(OUT, name)
        os.makedirs(od, exist_ok=True)
        table = pose_table(kind)
        for pose, (nf, nd) in table.items():
            if ONLY_POSE and pose not in ONLY_POSE:
                continue
            frames = range(nf) if not QUICK else [0]
            for f in frames:
                P = make_pose(z, pose, f, nf)
                apply(z, P)
                for d in range(nd):
                    if QUICK and d % 4:
                        continue
                    if ONLY_DIR is not None and d not in ONLY_DIR:
                        continue
                    ori = d * math.tau / nd
                    z.rot.rotation_euler = (0, 0, math.pi / 2 - ori)
                    sce.render.filepath = os.path.join(od, "%s_f%d_d%02d.png" % (pose, f, d))
                    bpy.ops.render.render(write_still=True)
                    id_pass(z, os.path.join(od, "i%s_f%d_d%02d.png" % (pose, f, d)))
        print("DONE", name)


main()
