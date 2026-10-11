"""Prison experiment: four tree variants modelled procedurally in Blender (headless) and rendered as sprites that drop into assets/trees (314 x 359, transparent).
Flat matte colours from the existing tree palette, a dark ink outline (Freestyle, 34 26 19), orthographic camera seen from the south at a three-quarter top-down angle, then a soft
ground shadow ellipse and a one-step flat shade are composited with PIL (the shadow is not a render pass).

    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/make_prison_trees_blender.py

Writes assets/trees/tree_21.png (dead tree), tree_22 (pine), tree_23 (scrub bush), tree_24 (broadleaf) and docs/experiments/prison/blender/prison_trees.blend.
"""
import bpy, math, os, random, sys
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs/experiments/prison/blender")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sce = bpy.context.scene
col = bpy.data.collections.new("prison")
sce.collection.children.link(col)


def rgb(h):
    return tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4))    # sRGB hex to the linear value Blender stores


def mat(name, h):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb(h), 1)
    return m


def add(o, m):
    for c in o.users_collection:
        c.objects.unlink(o)
    col.objects.link(o)
    o.data.materials.append(m)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.shade_flat()
    o.select_set(False)
    return o


def blob(loc, r, m, sq=1.0, seed=0, detail=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=loc)
    o = bpy.context.active_object
    o.scale.z = sq
    rnd = random.Random(seed)
    for v in o.data.vertices:
        v.co *= 1.0 + rnd.uniform(-0.14, 0.14)
    return add(o, m)


def cone(loc, r1, r2, h, m, rot=(0, 0, 0), verts=9):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=h, location=loc, rotation=rot)
    return add(bpy.context.active_object, m)


def limb(a, b, r1, r2, m):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = cone((a + b) / 2, r1, r2, d.length, m, verts=7)
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Z', 'Y')
    return o


trunk = mat("trunk", "5a4030"); trunk_d = mat("trunk_d", "5e5248"); bark = mat("bark", "6a5e52")
g_dark = mat("g_dark", "3f6b38"); g_mid = mat("g_mid", "4d7a3c"); g_lit = mat("g_lit", "7aa24f")
p_dark = mat("p_dark", "2e5a3a"); p_mid = mat("p_mid", "3a6e46"); p_lit = mat("p_lit", "4a8454")
s_dark = mat("s_dark", "46703a"); s_lit = mat("s_lit", "7aa24f")

variants = {}
# 21: bare dead tree, forking limbs
o = [limb((0, 0, 0), (0, 0, 2.4), 0.42, 0.22, trunk_d)]
rnd = random.Random(21)
def branch(p, ang, ln, r, depth):
    if depth == 0:
        return
    q = (p[0] + math.cos(ang) * ln * 0.55, p[1] + rnd.uniform(-0.15, 0.15), p[2] + ln * 0.85)
    o.append(limb(p, q, r, r * 0.65, bark))
    for k, da in enumerate((-0.55, 0.5)):
        branch(q, ang + da + rnd.uniform(-0.2, 0.2), ln * 0.7, r * 0.65, depth - 1)
branch((0, 0, 2.2), math.pi - 0.5, 1.7, 0.22, 5)
branch((0, 0, 2.2), 0.5, 1.7, 0.22, 5)
branch((0, 0, 1.6), math.pi - 1.1, 1.3, 0.16, 4)
branch((0, 0, 1.4), 1.0, 1.2, 0.16, 4)
branch((0, 0, 2.6), math.pi / 2, 1.2, 0.14, 4)
variants["tree_21"] = o
# 22: pine: stacked cones
o = [cone((0, 0, 0.9), 0.24, 0.16, 1.8, trunk)]
for i, (z, r, h) in enumerate([(1.5, 1.7, 1.7), (2.5, 1.4, 1.6), (3.4, 1.05, 1.5), (4.3, 0.7, 1.4), (5.1, 0.4, 1.0)]):
    o.append(cone((0, 0, z + h / 2), r, 0.04, h, [p_dark, p_mid][i % 2], verts=10))
variants["tree_22"] = o
# 23: scrub bush
o = []
for i, (x, y, z, r, m) in enumerate([(-0.9, 0, 0.55, 0.85, s_dark), (0.8, 0.1, 0.5, 0.9, s_dark), (0, -0.4, 0.85, 0.8, s_lit), (0.1, 0.45, 0.45, 0.7, s_dark), (-0.3, 0, 1.0, 0.55, s_lit), (0.55, -0.2, 0.95, 0.5, s_lit)]):
    o.append(blob((x, y, z), r, m, 0.8, 23 + i))
variants["tree_23"] = o
# 24: broadleaf with a clumpy low-poly crown
o = [cone((0, 0, 1.2), 0.3, 0.2, 2.4, trunk)]
for i, (x, y, z, r, m) in enumerate([(0, 0, 3.6, 1.6, g_mid), (-1.0, 0.1, 3.9, 1.1, g_dark), (1.0, 0, 3.8, 1.15, g_dark), (-0.4, -0.7, 4.6, 0.95, g_lit), (0.5, 0.2, 4.7, 1.0, g_lit), (0, 0.5, 3.3, 1.2, g_dark), (0.9, -0.6, 3.5, 0.8, g_mid)]):
    o.append(blob((x, y, z), r, m, 0.92, 240 + i))
variants["tree_24"] = o

# render set-up: workbench, flat, freestyle ink outline
sce.render.engine = 'BLENDER_WORKBENCH'
sce.view_settings.view_transform = 'Standard'; sce.view_settings.look = 'None'; sce.display_settings.display_device = 'sRGB'
sce.render.resolution_x, sce.render.resolution_y = 314 * 3, 359 * 3
sce.render.resolution_percentage = 100
sce.render.film_transparent = True
sh = sce.display.shading
sh.light = 'FLAT'; sh.color_type = 'MATERIAL'
sce.render.image_settings.file_format = 'PNG'; sce.render.image_settings.color_mode = 'RGBA'
sce.render.use_freestyle = True
vl = sce.view_layers[0]
vl.use_freestyle = True
fs = vl.freestyle_settings
ls = fs.linesets.new("ink")
ls.select_silhouette = True; ls.select_border = True; ls.select_crease = True; ls.select_edge_mark = False
ls.linestyle.color = tuple((v / 255) ** 2.2 for v in (34, 26, 19))
ls.linestyle.thickness = 14.0
cd = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cd); col.objects.link(cam)
cd.type = 'ORTHO'; cd.ortho_scale = 7.4
tilt = math.radians(68)
cam.rotation_euler = (tilt, 0, 0)
dist = 20.0
cam.location = (0, -dist * math.sin(tilt), 0.0 + dist * math.cos(tilt) + 3.0)
sce.camera = cam
sun = bpy.data.lights.new("sun", 'SUN'); so = bpy.data.objects.new("sun", sun); col.objects.link(so)

for name, objs in variants.items():
    for n2, ob2 in variants.items():
        for x in ob2:
            x.hide_render = (n2 != name)
    sce.render.filepath = os.path.join(OUT, name + "_raw.png")
    bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "prison_trees.blend"))
print("RENDERED", list(variants))
