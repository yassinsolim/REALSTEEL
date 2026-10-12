"""Preview renders of the add-on kits on ANVIL: chassis, modules, crests and paint. Like preview.py it is only for looking
at the art; what the game draws comes from the generated RobotKits.luau."""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import kits
import preview
import robotlib

# metallic, roughness, emission strength for each finish the game offers (Looks.luau has the Roblox side of these).
FINISHES = {
    "BRUSHED": (0.85, 0.42),
    "MATTE": (0.1, 0.8),
    "CHROME": (1.0, 0.12),
    "GLOSS": (0.3, 0.2),
}

_unit_meshes = {}


def _unit_mesh(shape):
    """A unit box, cylinder (axis along Blender Z, which is Roblox Y) or ball, made once and shared."""
    if shape in _unit_meshes:
        return _unit_meshes[shape]
    bm = bmesh.new()
    if shape == "box":
        bmesh.ops.create_cube(bm, size=1.0)
    elif shape == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=0.5, radius2=0.5, depth=1.0)
    else:
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.5)
    mesh = bpy.data.meshes.new("unit_" + shape)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = shape != "box"
    _unit_meshes[shape] = mesh
    return mesh


def palette_materials(armor, accent, finish="BRUSHED", frame=None):
    """Role materials for a paint job: armor color, accent (trim and glow) color, and a finish."""
    metallic, roughness = FINISHES[finish]
    glow = tuple(min(1.0, channel * 0.65 + 0.35) for channel in accent)
    dark = frame if frame is not None else (0.055, 0.06, 0.075)
    styles = {
        "Armor": (armor, metallic, roughness, 0.0),
        "Dark": (dark, 0.6, 0.5, 0.0),
        "Trim": (accent, 0.45, 0.35, 0.0),
        "Glow": (glow, 0.0, 0.3, 6.0),
    }
    materials = {}
    for role, (color, metal, rough, emission) in styles.items():
        material = bpy.data.materials.new("%s_%s" % (role, finish))
        material.use_nodes = True
        material.diffuse_color = (*color, 1)
        bsdf = material.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        if emission > 0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1)
            bsdf.inputs["Emission Strength"].default_value = emission
        materials[role] = material
    return materials


def _assign(obj, material):
    if not obj.material_slots:
        obj.data.materials.append(material)
    obj.material_slots[0].link = "OBJECT"
    obj.material_slots[0].material = material


def instance(robot, pose, offset, materials, active_kits, scale=1.0):
    """The robot posed with the given kits, shifted by offset (Roblox axes) and drawn `scale` times as big."""
    world = robotlib.solve(robot, pose)
    shift = Matrix.Translation(Vector(offset))
    grow = Matrix.Scale(scale, 4)
    basis, unbasis = robotlib.BASIS, robotlib.BASIS.inverted()
    pivots = robot.joint_map()
    made = []

    for part in robot.parts:
        if not part.obj.data.materials:
            part.obj.data.materials.append(materials[part.role])
        copy = part.obj.copy()
        copy.hide_render = False
        copy.hide_viewport = False
        bpy.context.scene.collection.objects.link(copy)
        copy.matrix_world = basis @ shift @ grow @ robotlib.part_matrix(robot, world, part) @ unbasis
        _assign(copy, materials[part.role])
        made.append(copy)

    for name in active_kits:
        for piece in kits.KITS[name]:
            joint = pivots[piece["joint"]]
            center = Vector(piece["center"])
            size = piece["size"]
            local = Matrix.Translation(center - joint.pivot) @ robotlib.rotation_matrix(piece["rot"])
            # Unit meshes are in Blender axes: Roblox x, z, y become Blender x, y, z.
            stretch = Matrix.Diagonal((size[0], size[2], size[1], 1))
            obj = bpy.data.objects.new("%s_%s" % (name, piece["role"]), _unit_mesh(piece["shape"]))
            bpy.context.scene.collection.objects.link(obj)
            obj.matrix_world = basis @ shift @ grow @ world[piece["joint"]] @ local @ unbasis @ stretch
            _assign(obj, materials[piece["role"]])
            made.append(obj)
    return made


def kits_for(chassis_name, arms=1, core=1, legs=1, crest=None):
    active = []
    if chassis_name in kits.CHASSIS_KITS:
        active.append(kits.CHASSIS_KITS[chassis_name])
    for slot, option in (("ARMS", arms), ("CORE", core), ("LEGS", legs)):
        if option in kits.MODULE_KITS[slot]:
            active.append(kits.MODULE_KITS[slot][option])
    if crest:
        active.append(crest)
    return active


def sheet(robot, entries, path, view="front", spacing=6.5, size=(2400, 900), center_y=3.6, ortho=None):
    """One row of robots. entries is [(label, {"kits": [...], "scale": 1.0, "materials": {...}, "pose": {...}})]."""
    count = len(entries)
    created = []
    rest = {"pos": (0, 0, 0), "rot": {}}
    # The camera stands at (sin a, 0, -cos a) times its distance and looks at the robots; a = 0 is the front, 90 degrees
    # the side from +x. Screen right is the view direction crossed with up, and the robots stand in a row along it.
    azimuth = {"front": 0.0, "three": 40.0, "side": 90.0}[view]
    angle = math.radians(azimuth)
    right = (-math.cos(angle), 0, -math.sin(angle))
    toward_camera = (math.sin(angle), 0, -math.cos(angle))

    def place(slot, height=0.0):
        return (right[0] * slot, height, right[2] * slot)

    for index, (name, spec) in enumerate(entries):
        slot = (index - (count - 1) / 2) * spacing
        created += instance(
            robot, spec.get("pose", rest), place(slot), spec["materials"], spec.get("kits", []), spec.get("scale", 1.0)
        )
    width = ortho if ortho is not None else spacing * count + 6
    elevation = 4.0 if view == "three" else 0.0
    cam = preview.camera(
        (toward_camera[0] * 60, center_y + elevation, toward_camera[2] * 60), (0, center_y, 0), ortho_scale=width
    )
    for index, (name, spec) in enumerate(entries):
        slot = (index - (count - 1) / 2) * spacing
        created.append(preview.label(name, place(slot, center_y + 4.1), cam.rotation_euler))
    preview.render(path, size)
    preview.discard(created)
    bpy.data.objects.remove(cam)
