"""Prison experiment, round 7: 16-direction character renders for the key looks (Ruth, the guards, two walkers).

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/make_pawn_dirs_blender.py -- <outdir> [look,look,...] [--dirs=16] [--frames=6] [--px=320]

Headless Blender only. Builds a chibi figure (big head, short body, stubby legs: the proportions of the baked bust in assets/pawns plus the live legs of
scripts/render/pawn_art.gd) from the look dictionaries of assets/data/map.json (`people` and `zombieLooks`, plus the overrides of JOBS below), and renders it with
an orthographic camera seen from the south at the game's low three-quarter angle, Workbench shading and a dark ink outline (Freestyle), to
<outdir>/<look>/f<frame>_d<dir>.png (transparent, `px` pixels per tile, cell CELL tiles square, the figure's origin at the cell's middle).

What is NOT drawn: the arms and the gun of a person (the game draws the hands and the exact-angle weapon live, as it always did) and the ground shadow (drawn live).
A walker's arms ARE drawn (they reach and swing with the walk).
Units: 1 Blender unit = 1 tile of screen. Heights are in screen tiles (the figure is stretched by 1/cos(elevation) so that a tile of height is a tile on screen).
Heading i of N faces the screen angle i * 360 / N, 0 = east, 4 (of 16) = south (toward the camera), the game's `_ori` (y down).
Frame f of F is the stride phase f * 2 pi / F: frame 0 and F/2 are the neutral pose (legs together), so frame 0 is also the standing figure.
"""
import bpy, bmesh, math, os, sys, json, random
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0]
WANT = [a for a in argv[1:] if not a.startswith("--") and a][:1]
WANT = WANT[0].split(",") if WANT else None
OPT = {a.split("=")[0]: a.split("=")[1] for a in argv if a.startswith("--") and "=" in a}
DIRS = int(OPT.get("--dirs", 16))
FRAMES = int(OPT.get("--frames", 6))
PX = float(OPT.get("--px", 320))          # render pixels per tile (the game's art is 160: the packer halves it for the antialiasing)
CELL = float(OPT.get("--cell", 2.4))      # tiles across the render
ELEV = math.radians(float(OPT.get("--elev", 16)))
SHADE = OPT.get("--shade", "studio")
INK = (26, 20, 15)
INK_PX = float(OPT.get("--ink", 9.0))
ONLY_DIR = [int(x) for x in OPT["--only"].split(",")] if "--only" in OPT else None

MAP = json.load(open(os.path.join(ROOT, "assets/data/map.json")))
PEOPLE = {p["id"]: p["look"] for p in MAP["people"]}
ZL = MAP["zombieLooks"]

# What is rendered: name -> (look dict, is_zombie). A look of the crew is the baked person's look with the crew's overrides (scripts/prison/prison_crew.gd ROSTER).
JOBS = {
    "ruth": (PEOPLE["ruth"], False),
    "walt": (PEOPLE["walt"], False),
    "dez": (PEOPLE["dez"], False),
    "sol": ({**PEOPLE["hector"], "top": "#4a4a50", "pants": "#2c3038", "skin": "#c69877"}, False),
    "rae": ({**PEOPLE["ana"], "top": "#3a4a3a", "outer": "#555a50", "pants": "#2c2c34", "skin": "#a6734e"}, False),
    "z0": (ZL[0], True),
    "z1": (ZL[1], True),
}


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
COL = bpy.data.collections.new("pawn")
sce.collection.children.link(COL)
MATS = {}


TOON = OPT.get("--engine", "eevee") == "eevee"
# the light: from the upper left front of the figure, in the camera's frame (a top-lit cartoon: the top bright, the underside a step darker)
RAMP = [(0.0, 0.80), (0.4, 0.92), (0.7, 1.0), (1.0, 1.07)]


def mat(h, name=None):
    if h in MATS:
        return MATS[h]
    m = bpy.data.materials.new(name or h)
    m.diffuse_color = (*lin(h), 1.0)
    if TOON:
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


def finish(o, m, smooth=True):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    COL.objects.link(o)
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = smooth
    return o


def sphere(loc, r, m, seg=24, smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = r if isinstance(r, (tuple, list, Vector)) else (r, r, r)
    return finish(o, m, smooth)


def rbox(loc, size, rad, m, seg=4, taper=1.0):
    """A rounded box: a cube with its edges bevelled (applied); `taper` is the width of its bottom against its top."""
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
    return finish(o, m)


def cyl(loc, r, depth, m, verts=16, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    return finish(bpy.context.active_object, m)


def torus(loc, major, minor, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=20, minor_segments=8, location=loc, rotation=rot)
    return finish(bpy.context.active_object, m)


# ---------------------------------------------------------------- the figure --
# Screen-tile numbers taken from the baked bust and pawn_art.gd: the head's top at -0.88 (0.88 up), the chin at about -0.22, the shoulders at about -0.2, the hem at 0.13 (down),
# the feet at 0.3 to 0.35. The figure's origin is that of the sprite (the point the rules put the person at).
HEAD_Z, HEAD_R = 0.545, 0.268
HIP_Z = -0.12
SOLE_Z = -0.345


class Fig:
    def __init__(self, look, zombie):
        L = look
        self.zombie = zombie
        self.root = bpy.data.objects.new("root", None)      # scales z (the camera's foreshortening)
        COL.objects.link(self.root)
        self.root.scale = (1.0, 1.0, 1.0 / math.cos(ELEV))
        self.root.location = (0, 0, 0.0)
        self.rot = bpy.data.objects.new("rot", None)        # turns about z
        COL.objects.link(self.rot)
        self.rot.parent = self.root
        self.parts = []
        skin = L["skin"]
        self.m_skin = mat(skin)
        under = L.get("top", "#888888")
        outer = L.get("outer")
        self.m_top = mat(outer or under)
        self.m_under = mat(under)
        self.m_pants = mat(L.get("pants", "#333333"))
        self.m_shoe = mat(L.get("shoes", "#2a2420"))
        self.m_hair = mat(L.get("hairColor", "#2a211c"))
        self.m_ink = mat("#1a1411")
        self.m_white = mat("#f2eee6")
        self.look = L
        self.grp = 2
        self.legs = []
        self.arms = []
        self.grp = 2
        self.build_body()
        self.grp = 1
        self.build_head()
        self.build_hair()
        self.grp = 2
        self.build_gear()
        for o in self.parts:
            if o.parent is None:
                o.parent = self.rot

    def add(self, o):
        o["grp"] = self.grp
        self.parts.append(o)
        return o

    def build_body(self):
        L = self.look
        z = self.zombie
        # torso: a rounded block, wider at the shoulders; the cardigan/jacket over the top; the shirt in a strip down the middle
        top = self.add(rbox((0, 0.0, 0.05), (0.70, 0.40, 0.42), 0.12, self.m_top, 5, taper=0.84))
        if L.get("outer"):
            self.add(rbox((0, -0.19, 0.02), (0.20, 0.06, 0.40), 0.025, self.m_under, 3))
        elif L.get("topStyle") == "scrubs" or L.get("topStyle") == "hoodie":
            pass
        # collar
        self.add(rbox((0, -0.02, 0.255), (0.30, 0.26, 0.07), 0.03, self.m_under if L.get("outer") else self.m_top, 3))
        # the hem at the bottom of the torso hides the hips
        # legs: two short rounded blocks hanging from the hem with a shoe each
        for sg in (1, -1):
            self.grp = 3
            leg = self.add(rbox((sg * 0.105, 0, HIP_Z - 0.085), (0.14, 0.15, 0.17), 0.05, self.m_pants, 3))
            shoe = self.add(sphere((sg * 0.105, -0.03, SOLE_Z + 0.04), (0.085, 0.115, 0.055), self.m_shoe, 14))
            self.grp = 2
            self.legs.append((sg, leg, shoe))
        if z:
            # reaching arms: sleeves out in front, hands bare, swinging with the stride
            self.grp = 4
            for sg in (1, -1):
                sl = self.add(cyl((0, 0, 0), 0.062, 0.34, self.m_top, 12, rot=(math.pi / 2, 0, 0)))
                hd = self.add(sphere((0, 0, 0), 0.07, self.m_skin, 12))
                self.arms.append((sg, sl, hd))
            self.grp = 2
        # the bandolier of Ruth: a strap from the left shoulder to the right hip with shells
        if L.get("bandolier"):
            band = bpy.data.objects.new("band", None)    # an empty carrying the strap and its shells, tilted from the left shoulder to the right hip
            COL.objects.link(band)
            band.location = (0, -0.205, 0.03)
            band.rotation_euler = (0, -0.42, 0)
            self.parts.append(band)
            st = self.add(rbox((0, 0, 0), (0.07, 0.03, 0.62), 0.012, mat("#5a3a24"), 2))
            st.parent = band
            for i in range(6):
                t = (i - 2.5) / 2.5 * 0.9
                sh = self.add(rbox((0, -0.02, t * 0.27), (0.04, 0.025, 0.06), 0.008, mat("#c0462d" if i % 2 else "#d4a63a"), 1))
                sh.parent = band
        if L.get("belt"):
            self.add(rbox((0, -0.0, -0.18), (0.66, 0.42, 0.04), 0.012, mat("#5a3a22"), 2))
        if L.get("armband"):
            pass

    def build_head(self):
        L = self.look
        hs = 1.0
        head = self.add(sphere((0, 0.0, HEAD_Z), (HEAD_R, HEAD_R * 0.95, HEAD_R * 0.97), self.m_skin, 32))
        self.head = head
        # ears
        for sg in (1, -1):
            self.add(sphere((sg * HEAD_R * 0.97, 0.01, HEAD_Z - 0.01), (0.035, 0.045, 0.065), self.m_skin, 12))
        zomb = self.zombie
        eye_c = "#1b1512"
        ez = HEAD_Z + 0.015
        for sg in (1, -1):
            if zomb:
                self.add(sphere((sg * 0.105, -HEAD_R * 0.9, ez), (0.05, 0.03, 0.058), self.m_white, 14))
                self.add(sphere((sg * 0.105, -HEAD_R * 0.9 - 0.02, ez), (0.033, 0.016, 0.037), mat("#2a2018"), 10))
                self.add(sphere((sg * 0.105, -HEAD_R * 0.9 - 0.003, ez + 0.002), (0.07, 0.03, 0.075), mat(shade(L["skin"], 0.55)), 12)).scale.y = 0.02
            else:
                self.add(sphere((sg * 0.093, -HEAD_R * 0.91, ez), (0.03, 0.02, 0.042), mat(eye_c), 12))
                self.add(sphere((sg * 0.093 - sg * 0.009, -HEAD_R * 0.915 - 0.012, ez + 0.02), (0.01, 0.008, 0.012), self.m_white, 8))
                br = L.get("browColor", L.get("hairColor", "#2a211c"))
                b = self.add(rbox((sg * 0.093, -HEAD_R * 0.9, ez + 0.08), (0.085, 0.02, 0.02), 0.008, mat(br), 2))
                b.rotation_euler = (0, sg * 0.1, 0)
        # nose and mouth
        self.add(sphere((0, -HEAD_R * 0.97, HEAD_Z - 0.04), (0.04, 0.035, 0.035), mat(shade(L["skin"], 0.93)), 10))
        if zomb:
            self.add(sphere((0, -HEAD_R * 0.9, HEAD_Z - 0.135), (0.075, 0.03, 0.05), mat("#3a0f10"), 12))
            self.add(rbox((0, -HEAD_R * 0.91 - 0.01, HEAD_Z - 0.105), (0.08, 0.014, 0.018), 0.005, self.m_white, 1))
        else:
            self.add(rbox((0, -HEAD_R * 0.94, HEAD_Z - 0.12), (0.075, 0.016, 0.016), 0.006, mat(shade(L["skin"], 0.55)), 2))
            for sg in (1, -1):
                self.add(sphere((sg * 0.15, -HEAD_R * 0.78, HEAD_Z - 0.06), (0.05, 0.012, 0.035), mat(mix(L["skin"], "#e0705f", 0.28)), 10))
        if L.get("glasses"):
            for sg in (1, -1):
                self.add(torus((sg * 0.093, -HEAD_R * 0.93, ez), 0.062, 0.0075, mat("#2a2018"), rot=(math.pi / 2, 0, 0)))
            self.add(rbox((0, -HEAD_R * 0.94, ez + 0.01), (0.05, 0.012, 0.012), 0.004, mat("#2a2018"), 1))
        if L.get("wound"):
            self.add(sphere((0.15, -HEAD_R * 0.8, HEAD_Z + 0.1), (0.07, 0.03, 0.06), mat("#6e1d1a"), 10))
        n1 = len(self.parts)
        if L.get("beard") or L.get("mustache"):
            bc = mat(L.get("beardColor", "#2a211c"))
            if L.get("beard") == "full":
                self.add(sphere((0, -0.06, HEAD_Z - 0.17), (0.255, 0.22, 0.14), bc, 20))
                self.add(sphere((0, -0.27, HEAD_Z - 0.115), (0.075, 0.04, 0.025), bc, 10))
            elif L.get("beard") == "stubble":
                self.add(sphere((0, -0.2, HEAD_Z - 0.16), (0.2, 0.1, 0.085), mat(shade(L["skin"], 0.7)), 14))
            else:
                self.add(rbox((0, -HEAD_R * 0.98, HEAD_Z - 0.085), (0.15, 0.03, 0.03), 0.01, bc, 2))
        self.shrink(n1)

    def build_hair(self):
        n0 = len(self.parts)
        self._hair(0.31)
        self.shrink(n0)

    def _hair(self, HR):
        L = self.look
        hs = L.get("hair", "short")
        hair = self.m_hair
        zH = HEAD_Z
        rnd = random.Random(int(L.get("seed", 1)))
        hat = L.get("hat")
        if hat == "cap":
            hm = mat(L["hatColor"])
            self.add(sphere((0, 0.02, zH + 0.1), (HR * 1.06, HR * 1.05, 0.215), hm, 28))
            br = self.add(rbox((0, -0.33, zH + 0.135), (0.44, 0.2, 0.025), 0.012, hm, 3))
            br.rotation_euler = (0.12, 0, 0)
            if hs not in ("bald",):
                self.add(sphere((0, 0.14, zH - 0.02), (0.27, 0.14, 0.13), hair, 14))   # hair under the back of the cap
            return
        if hat == "beanie":
            hm = mat(L["hatColor"])
            self.add(sphere((0, 0.02, zH + 0.1), (HR * 1.06, HR * 1.05, 0.22), hm, 28))
            self.add(rbox((0, 0.0, zH + 0.12), (0.66, 0.62, 0.07), 0.03, mat(shade(L["hatColor"], 0.88)), 3))
            return
        if hs in ("short", "matted", "messy", "balding"):
            sc = (HR * 1.05, HR * 1.04, 0.22)
            top = zH + 0.1
            if hs == "balding":
                sc = (HR * 1.03, HR * 1.01, 0.12)
            o = self.add(sphere((0, 0.04, top), sc, hair, 24))
            if hs in ("matted", "messy"):
                for i in range(7):
                    a = rnd.uniform(0, math.tau)
                    self.add(sphere((math.cos(a) * 0.24, 0.05 + math.sin(a) * 0.2, zH + rnd.uniform(0.0, 0.2)), rnd.uniform(0.07, 0.11), hair, 10))
                if hs == "matted":
                    self.add(sphere((0, 0.17, zH - 0.04), (0.3, 0.15, 0.2), hair, 14))
        elif hs == "curly":
            self.add(sphere((0, 0.05, zH + 0.1), (0.3, 0.29, 0.2), hair, 20))
            self.puffs(rnd, 40, 0.305, 0.075, 0.12, hair)
        elif hs == "twists":
            self.add(sphere((0, 0.05, zH + 0.1), (0.3, 0.29, 0.2), hair, 22))
            self.puffs(rnd, 34, 0.31, 0.05, 0.08, hair)
        elif hs == "ponytail":
            self.add(sphere((0, 0.04, zH + 0.1), (HR * 1.05, HR * 1.04, 0.22), hair, 24))
            self.add(sphere((0, 0.15, zH - 0.02), (0.2, 0.17, 0.22), hair, 14))
            self.add(sphere((0.0, 0.3, zH - 0.12), (0.075, 0.075, 0.2), hair, 10))
            self.add(sphere((0.0, 0.3, zH + 0.0), (0.05, 0.05, 0.05), mat("#c0302a"), 8))
        elif hs == "long":
            self.add(sphere((0, 0.05, zH + 0.1), (HR * 1.07, HR * 1.06, 0.22), hair, 24))
            self.add(sphere((0, 0.17, zH - 0.12), (0.34, 0.16, 0.36), hair, 18))
            for sg in (1, -1):
                self.add(sphere((sg * 0.29, 0.03, zH - 0.1), (0.05, 0.1, 0.2), hair, 10))

    def shrink(self, n0, k=HEAD_R / 0.31):
        """Hair, hats and beards are written for a head of radius 0.31: scale them to this one, about the head's middle."""
        for o in self.parts[n0:]:
            o.location = Vector((o.location.x * k, o.location.y * k, HEAD_Z + (o.location.z - HEAD_Z) * k))
            o.scale = o.scale * k

    def puffs(self, rnd, n, R, r0, r1, m):
        """Small spheres over the top and back of the head (never the face): the curls of a head of hair."""
        k = 0
        while k < n:
            d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.1, 1))).normalized()
            if d.y < -0.15 and d.z < 0.62:
                continue
            if d.y < -0.5:
                continue
            light = mat(mix(self.look.get("hairColor", "#2a211c"), "#ffffff", 0.18)) if (self.look.get("hair") == "curly" and k % 3 == 0) else m
            self.add(sphere((d.x * R * 1.02, 0.05 + d.y * R * 0.98, HEAD_Z + 0.03 + d.z * R * 0.9), rnd.uniform(r0, r1), light, 10))
            k += 1

    def build_gear(self):
        L = self.look
        if L.get("backpack"):
            self.add(rbox((0, 0.25, 0.03), (0.4, 0.15, 0.36), 0.06, mat(L["backpack"]), 3))
        if L.get("tie"):
            self.add(rbox((0, -0.205, 0.02), (0.05, 0.02, 0.26), 0.01, mat(L["tie"]), 2))
        if L.get("pattern") == "plaid":
            pc = mat(L.get("patternColor", "#2e1c1a"))
            for i in range(3):
                self.add(rbox((0, -0.202 + 0.0, 0.06 - i * 0.11), (0.62, 0.012, 0.03), 0.004, pc, 1))
            for i in range(3):
                self.add(rbox((-0.2 + i * 0.2, -0.202, 0.0), (0.03, 0.012, 0.4), 0.004, pc, 1))
        if self.zombie and float(L.get("blood", 0)) > 0.3:
            self.add(sphere((0.12, -0.2, 0.0), (0.12, 0.02, 0.14), mat("#6e1d1a"), 10))
            self.add(sphere((-0.05, -0.235, HEAD_Z - 0.2), (0.03, 0.02, 0.1), mat("#6e1d1a"), 8))

    # -- the pose: ph is the stride phase (radians)
    def pose(self, ph, heading):
        """heading: the screen angle the figure faces (radians, 0 east, pi/2 south: toward the camera). Legs swing along it; arms reach along it."""
        A = 0.085
        for i, (sg, leg, shoe) in enumerate(self.legs):
            p = ph + (0.0 if sg > 0 else math.pi)
            f = A * math.sin(p) * (0.8 if self.zombie else 1.0)
            lift = 0.05 * max(0.0, math.cos(p)) * (0.6 if self.zombie else 1.0)
            # legs are in the figure's frame (it faces -y): forward is -y
            leg.location = Vector((sg * 0.105, -f, HIP_Z - 0.085 + lift))
            shoe.location = Vector((sg * 0.105, -0.03 - f, SOLE_Z + 0.04 + lift))
        for sg, sl, hd in self.arms:
            sw = 0.05 * math.sin(ph + (0 if sg > 0 else math.pi))
            base = Vector((sg * 0.33, -0.24 - sw, 0.07))
            sl.location = base
            hd.location = base + Vector((0, -0.19, -0.01))
        if self.zombie:
            self.head.rotation_euler = (0.12, float(self.look.get("tilt", 0)) * 0.6, 0)


def setup_render():
    r = sce.render
    if TOON:
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
        # a light from the upper left, a little toward the camera (the screen's -x, up, toward -y)
        so.rotation_euler = (math.radians(55), 0, math.radians(-35))
    else:
        r.engine = "BLENDER_WORKBENCH"
    r.resolution_x = r.resolution_y = int(CELL * PX)
    r.resolution_percentage = 100
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    sce.view_settings.view_transform = "Standard"
    sce.view_settings.look = "None"
    sce.display_settings.display_device = "sRGB"
    sh = sce.display.shading
    sh.color_type = "MATERIAL"
    if SHADE == "flat":
        sh.light = "FLAT"
    else:
        sh.light = "STUDIO"
        sh.use_world_space_lighting = True
        try:
            sh.studio_light = "rim.sl" if False else sh.studio_light
        except Exception:
            pass
    sh.show_cavity = False
    sh.show_object_outline = False
    sce.display.render_aa = "8"
    r.use_freestyle = False    # the outline is made by the packer from the silhouette (tools/pack_pawn_dirs.py): crisp and the same width everywhere
    cd = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cd)
    COL.objects.link(cam)
    cd.type = "ORTHO"
    cd.ortho_scale = CELL
    cd.clip_start = 0.1
    cd.clip_end = 100
    cam.rotation_euler = (math.pi / 2 - ELEV, 0, 0)
    d = 30.0
    cam.location = (0, -d * math.cos(ELEV), d * math.sin(ELEV))
    sce.camera = cam


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
    c = {1: (1, 0, 0), 2: (0, 1, 0), 3: (0, 0, 1), 4: (1, 1, 0), 5: (1, 0, 1)}[g]
    em.inputs[0].default_value = (*c, 1.0)
    nt.links.new(em.outputs[0], out.inputs[0])
    MATS[key] = m
    return m


def id_pass(fig, path):
    """The same view with one flat colour for each part of the body (1 head, 2 torso, 3 legs, 4 arms), unfiltered: the packer draws the thin lines where two parts meet."""
    meshes = [o for o in fig.parts if o.type == "MESH"]
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


setup_render()
names = WANT or list(JOBS)
for name in names:
    look, zomb = JOBS[name]
    for o in list(COL.objects):
        if o.type != "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)
    MATS.clear()
    fig = Fig(look, zomb)
    od = os.path.join(OUT, name)
    os.makedirs(od, exist_ok=True)
    for f in range(FRAMES):
        for d in range(DIRS):
            if ONLY_DIR is not None and d not in ONLY_DIR:
                continue
            ori = d * math.tau / DIRS
            fig.pose(f * math.tau / FRAMES, ori)
            fig.rot.rotation_euler = (0, 0, math.pi / 2 - ori)
            sce.render.filepath = os.path.join(od, "f%d_d%02d.png" % (f, d))
            bpy.ops.render.render(write_still=True)
            id_pass(fig, os.path.join(od, "i%d_d%02d.png" % (f, d)))
    print("DONE", name)
