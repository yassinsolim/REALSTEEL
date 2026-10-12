"""Worn-metal textures for the robot frames.

Every textured part of a frame shares one UV atlas. Cycles bakes raw signals into it: how sharp each convex edge is, how
deep each seam is, two noise layers and the height above the floor, joint by joint so a hanging arm never stains the
torso. A beveled-edge normal map is baked too. numpy then turns the signals into the maps the game puts on the parts with
SurfaceAppearance:

  <Frame>_color.png   albedo in sRGB, alpha the paint (AlphaMode TintMask: each player's paint tints only where alpha is
                      1, so worn edges show bare steel whatever the paint)
  <Frame>_normal.png  tangent-space normals (OpenGL, +Y)
  <Frame>_metal_<FINISH>.png, <Frame>_rough_<FINISH>.png   for each finish in Looks.Finishes

Glow parts stay Neon and get no textures.
"""

import math
import os

import bpy
import numpy as np

# The roles that get textures, and the number each is baked as. Armor and Trim are painted; Dark and Steel are not.
ROLE_ID = {"Armor": 1, "Trim": 2, "Dark": 3, "Steel": 4}
PAINTED = (1, 2)
BAKE_SIZE = 2048
SIZE = 1024

# Paint metalness and roughness for each finish; keep the names in step with Looks.Finishes.
FINISHES = {"BRUSHED": (0.7, 0.36), "MATTE": (0.04, 0.78), "CHROME": (0.95, 0.07), "GLOSS": (0.1, 0.16)}

# Albedo of each surface in sRGB (paint is near white, so the player's paint tints it to its own color).
PAINT = 0.93
BARE_STEEL = 0.7
STEEL = 0.74
DARK = (0.11, 0.115, 0.13)


def textured(robot):
    return [part for part in robot.parts if part.role in ROLE_ID]


def unwrap(robot):
    """One UV atlas over every textured part, islands packed at an even texel density."""
    parts = textured(robot)
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    for part in parts:
        if not part.obj.data.uv_layers:
            part.obj.data.uv_layers.new(name="UVMap")
        part.obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0].obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.0, correct_aspect=True)
    bpy.ops.uv.pack_islands(rotate=True, scale=True, margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


def _cycles():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    preferences = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            preferences.compute_device_type = kind
        except TypeError:
            continue
        preferences.get_devices()
        devices = [device for device in preferences.devices if device.type == kind]
        if devices:
            for device in preferences.devices:
                device.use = device.type == kind
            scene.cycles.device = "GPU"
            break
    scene.cycles.samples = 24
    scene.render.bake.margin = 16
    scene.render.bake.margin_type = "EXTEND"


def _image(name, size, color_space="Non-Color"):
    image = bpy.data.images.new(name, size, size, alpha=True, float_buffer=True)
    image.colorspace_settings.name = color_space
    image.generated_color = (0, 0, 0, 0)
    return image


def _node(tree, kind, location, **settings):
    node = tree.nodes.new(kind)
    node.location = location
    for key, value in settings.items():
        setattr(node, key, value)
    return node


def _emit_material(name, image, build):
    """A material that emits whatever `build(tree)` returns, with the bake target image active."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = _node(tree, "ShaderNodeOutputMaterial", (900, 0))
    emission = _node(tree, "ShaderNodeEmission", (700, 0))
    tree.links.new(build(tree), emission.inputs["Color"])
    tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    target = _node(tree, "ShaderNodeTexImage", (700, 300), image=image)
    tree.nodes.active = target
    return material


def _edges(tree):
    """R: how far the surface turns within a bevel's reach (one minus the dot product of a rounded and the flat normal),
    high along every edge and nought on flat faces, whatever other geometry is near."""
    bevel = _node(tree, "ShaderNodeBevel", (0, 200), samples=12)
    bevel.inputs["Radius"].default_value = 0.05
    geometry = _node(tree, "ShaderNodeNewGeometry", (0, 0))
    dot = _node(tree, "ShaderNodeVectorMath", (200, 100), operation="DOT_PRODUCT")
    tree.links.new(bevel.outputs["Normal"], dot.inputs[0])
    tree.links.new(geometry.outputs["True Normal"], dot.inputs[1])
    turn = _node(tree, "ShaderNodeMath", (400, 100), operation="SUBTRACT")
    turn.inputs[0].default_value = 1.0
    tree.links.new(dot.outputs["Value"], turn.inputs[1])
    combine = _node(tree, "ShaderNodeCombineColor", (600, 0))
    tree.links.new(turn.outputs[0], combine.inputs["Red"])
    return combine.outputs["Color"]


def _signals(tree):
    """G: seams (occlusion from outside). B: coarse noise."""
    outside = _node(tree, "ShaderNodeAmbientOcclusion", (0, 0), samples=16)
    outside.inputs["Distance"].default_value = 0.35
    seam = _node(tree, "ShaderNodeMath", (200, 0), operation="SUBTRACT")
    seam.inputs[0].default_value = 1.0
    tree.links.new(outside.outputs["AO"], seam.inputs[1])
    coords = _node(tree, "ShaderNodeTexCoord", (-400, -200))
    noise = _node(tree, "ShaderNodeTexNoise", (0, -200))
    noise.inputs["Scale"].default_value = 3.5
    noise.inputs["Detail"].default_value = 9.0
    noise.inputs["Roughness"].default_value = 0.62
    tree.links.new(coords.outputs["Object"], noise.inputs["Vector"])
    combine = _node(tree, "ShaderNodeCombineColor", (450, 0))
    tree.links.new(seam.outputs[0], combine.inputs["Green"])
    tree.links.new(noise.outputs["Fac"], combine.inputs["Blue"])
    return combine.outputs["Color"]


def _details(tree):
    """R: scratches, thin wavy streaks broken into short runs. G: large grime blotches."""
    coords = _node(tree, "ShaderNodeTexCoord", (-600, 0))
    stretch = _node(tree, "ShaderNodeMapping", (-400, 0))
    stretch.inputs["Scale"].default_value = (1.0, 1.0, 1.0)
    stretch.inputs["Rotation"].default_value = (0.6, 0.3, 0.9)
    tree.links.new(coords.outputs["Object"], stretch.inputs["Vector"])
    wave = _node(tree, "ShaderNodeTexWave", (-150, 200), wave_type="BANDS", bands_direction="DIAGONAL")
    wave.inputs["Scale"].default_value = 9.0
    wave.inputs["Distortion"].default_value = 14.0
    wave.inputs["Detail"].default_value = 3.0
    tree.links.new(stretch.outputs["Vector"], wave.inputs["Vector"])
    lines = _node(tree, "ShaderNodeMapRange", (100, 200))
    lines.inputs["From Min"].default_value = 0.94
    lines.inputs["From Max"].default_value = 0.985
    tree.links.new(wave.outputs["Fac"], lines.inputs["Value"])
    runs = _node(tree, "ShaderNodeTexNoise", (-150, -50))
    runs.inputs["Scale"].default_value = 6.0
    runs.inputs["Detail"].default_value = 3.0
    tree.links.new(coords.outputs["Object"], runs.inputs["Vector"])
    gate = _node(tree, "ShaderNodeMapRange", (100, -50))
    gate.inputs["From Min"].default_value = 0.52
    gate.inputs["From Max"].default_value = 0.66
    tree.links.new(runs.outputs["Fac"], gate.inputs["Value"])
    scratches = _node(tree, "ShaderNodeMath", (300, 100), operation="MULTIPLY")
    tree.links.new(lines.outputs["Result"], scratches.inputs[0])
    tree.links.new(gate.outputs["Result"], scratches.inputs[1])
    blotch = _node(tree, "ShaderNodeTexNoise", (-150, -300))
    blotch.inputs["Scale"].default_value = 1.6
    blotch.inputs["Detail"].default_value = 6.0
    blotch.inputs["Roughness"].default_value = 0.7
    tree.links.new(coords.outputs["Object"], blotch.inputs["Vector"])
    combine = _node(tree, "ShaderNodeCombineColor", (500, 0))
    tree.links.new(scratches.outputs[0], combine.inputs["Red"])
    tree.links.new(blotch.outputs["Fac"], combine.inputs["Green"])
    return combine.outputs["Color"]


def _ids(tree):
    """R: the part's role number / 4. G: height above the floor / 8 studs (rest pose). B: fine noise for chips."""
    role = _node(tree, "ShaderNodeAttribute", (0, 200), attribute_type="GEOMETRY", attribute_name="wear_role")
    quarter = _node(tree, "ShaderNodeMath", (200, 200), operation="DIVIDE")
    tree.links.new(role.outputs["Fac"], quarter.inputs[0])
    quarter.inputs[1].default_value = 4.0
    geometry = _node(tree, "ShaderNodeNewGeometry", (-200, 0))
    split = _node(tree, "ShaderNodeSeparateXYZ", (0, 0))
    tree.links.new(geometry.outputs["Position"], split.inputs["Vector"])
    height = _node(tree, "ShaderNodeMath", (200, 0), operation="DIVIDE")
    tree.links.new(split.outputs["Z"], height.inputs[0])
    height.inputs[1].default_value = 8.0
    coords = _node(tree, "ShaderNodeTexCoord", (-400, -200))
    fine = _node(tree, "ShaderNodeTexNoise", (0, -200))
    fine.inputs["Scale"].default_value = 26.0
    fine.inputs["Detail"].default_value = 4.0
    fine.inputs["Roughness"].default_value = 0.5
    tree.links.new(coords.outputs["Object"], fine.inputs["Vector"])
    combine = _node(tree, "ShaderNodeCombineColor", (450, 0))
    tree.links.new(quarter.outputs[0], combine.inputs["Red"])
    tree.links.new(height.outputs[0], combine.inputs["Green"])
    tree.links.new(fine.outputs["Fac"], combine.inputs["Blue"])
    return combine.outputs["Color"]


def _normal_material(image):
    material = bpy.data.materials.new("WearNormal")
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = _node(tree, "ShaderNodeOutputMaterial", (600, 0))
    bsdf = _node(tree, "ShaderNodeBsdfPrincipled", (300, 0))
    bevel = _node(tree, "ShaderNodeBevel", (0, -200), samples=12)
    bevel.inputs["Radius"].default_value = 0.035
    tree.links.new(bevel.outputs["Normal"], bsdf.inputs["Normal"])
    tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    target = _node(tree, "ShaderNodeTexImage", (300, 300), image=image)
    tree.nodes.active = target
    return material


def _assign(parts, material):
    for part in parts:
        part.obj.data.materials.clear()
        part.obj.data.materials.append(material)


def _select(parts):
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    for part in parts:
        part.obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0].obj


def _pixels(image):
    width, height = image.size
    data = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(data)
    return data.reshape(height, width, 4)





def _joined(parts, shift):
    """One object made of copies of the parts, each moved `shift(part)` studs along x and with its role on every face, so
    a whole frame bakes in one Cycles session instead of one per part. Copies keep the parts' UVs and normals."""
    copies = []
    for part in parts:
        obj = part.obj.copy()
        obj.data = part.obj.data.copy()
        obj.hide_render = False
        bpy.context.scene.collection.objects.link(obj)
        obj.location.x += shift(part)
        role = obj.data.attributes.new("wear_role", "FLOAT", "FACE")
        role.data.foreach_set("value", [float(ROLE_ID[part.role])] * len(obj.data.polygons))
        copies.append(obj)
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    for obj in copies:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.data.materials.clear()
    return joined


def _discard(obj):
    mesh = obj.data
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)


def bake(robot):
    """Bakes the raw signals and the normal map at BAKE_SIZE. Returns (signals, ids, normal) as float arrays."""
    _cycles()
    parts = textured(robot)
    scratch = _image(robot.name + "_scratch", BAKE_SIZE)
    for part in robot.parts:
        part.obj.hide_render = True

    def bake_into(obj, material, kind="EMIT"):
        obj.data.materials.clear()
        obj.data.materials.append(material)
        for other in bpy.context.view_layer.objects:
            other.select_set(other == obj)
        bpy.context.view_layer.objects.active = obj
        if kind == "NORMAL":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_clear=True, target="IMAGE_TEXTURES")
        else:
            bpy.ops.object.bake(type="EMIT", use_clear=True, target="IMAGE_TEXTURES")
        return _pixels(scratch).copy()

    # The bevel normals and the edges with every part on its own, so neither rounds into a neighbouring part.
    index = {id(part): number for number, part in enumerate(parts)}
    alone = _joined(parts, lambda part: index[id(part)] * 40.0)
    normal = bake_into(alone, _normal_material(scratch), "NORMAL")
    edges = bake_into(alone, _emit_material("WearEdges", scratch, _edges))
    _discard(alone)

    # Seams with the joints spread far apart, so each joint's occlusion is its own and a hanging arm never stains the
    # torso. Height comes from the vertical, which the spread leaves alone.
    spread = {joint.name: number * 60.0 for number, joint in enumerate(robot.joints)}
    apart = _joined(parts, lambda part: spread[part.joint])
    signals = bake_into(apart, _emit_material("WearSignals", scratch, _signals))
    ids = bake_into(apart, _emit_material("WearIds", scratch, _ids))
    details = bake_into(apart, _emit_material("WearDetails", scratch, _details))
    _discard(apart)
    signals[..., 0] = edges[..., 0]
    # Scratches and blotches ride along in the spare alpha channels.
    signals[..., 3] = details[..., 0]
    ids[..., 3] = details[..., 1]

    for part in robot.parts:
        part.obj.hide_render = False
    return signals, ids, normal


def _smooth(low, high, value):
    t = np.clip((value - low) / (high - low), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _half(array):
    """Halves the resolution by averaging each 2x2 block, which antialiases the bake."""
    height, width = array.shape[:2]
    return array.reshape(height // 2, 2, width // 2, 2, *array.shape[2:]).mean(axis=(1, 3))


def compose(signals, ids, normal):
    """The game's maps from the baked signals: {name: (array HxWx4 at SIZE, color space)}."""
    edge_raw, seam_raw, noise, scratch = signals[..., 0], signals[..., 1], signals[..., 2], signals[..., 3]
    role = np.rint(ids[..., 0] * 4).astype(np.int32)
    height = ids[..., 1] * 8.0
    fine = ids[..., 2]
    blotch = ids[..., 3]

    edge = _smooth(0.012, 0.08, edge_raw)
    seam = _smooth(0.08, 0.7, seam_raw)
    # Paint wears off the edges, broken up by noise, chips off here and there, and is scratched through in places.
    breakup = _smooth(0.36, 0.6, noise + 0.12 * (fine - 0.5))
    chips = _smooth(0.74, 0.8, fine) * _smooth(0.45, 0.7, noise)
    wear = np.clip(edge * (0.45 + 0.9 * breakup) * (1.0 - 0.7 * seam) + 0.75 * chips + 0.85 * scratch, 0.0, 1.0)
    # Dirt rises from the floor, strongest at the feet and gone by the knees; grime gathers in the seams and in blotches.
    dirt = np.clip(1.0 - height / 1.8, 0.0, 1.0) ** 1.6 * (0.55 + 0.45 * noise)
    stains = _smooth(0.55, 0.75, blotch) * 0.35
    grime = np.clip(0.6 * seam + 0.45 * dirt + stains, 0.0, 1.0)

    painted = np.isin(role, PAINTED)
    is_dark = role == 3
    is_steel = role == 4

    paint = PAINT * (1.0 - 0.55 * grime)
    bare = BARE_STEEL * (1.0 - 0.4 * grime) * (0.88 + 0.24 * fine)
    gray = np.where(painted, paint * (1.0 - wear) + bare * wear, 0.0)
    gray = np.where(is_steel, STEEL * (1.0 - 0.45 * grime) * (0.9 + 0.2 * fine), gray)
    color = np.repeat(gray[..., None], 3, axis=2)
    for channel in range(3):
        lift = DARK[channel] + 0.09 * edge * breakup
        color[..., channel] = np.where(is_dark, lift * (1.0 - 0.45 * grime), color[..., channel])
    alpha = np.where(painted, 1.0 - wear, 0.0)

    maps = {"color": (np.dstack([color, alpha]), "sRGB"), "normal": (normal, "Non-Color")}
    for finish, (paint_metal, paint_rough) in FINISHES.items():
        metal = np.where(painted, paint_metal * (1.0 - wear) + 1.0 * wear, 0.0)
        metal = np.where(is_dark, 0.5, metal)
        metal = np.where(is_steel, 0.95, metal)
        rough = np.where(painted, paint_rough * (1.0 - wear) + 0.3 * wear, 0.0)
        rough = rough + np.where(painted, 0.28 * grime, 0.0)
        rough = np.where(is_dark, 0.58 + 0.25 * grime, rough)
        rough = np.where(is_steel, 0.26 + 0.25 * grime + 0.12 * fine, rough)
        rough = np.clip(rough, 0.03, 1.0)
        ones = np.ones_like(metal)
        maps["metal_" + finish] = (np.dstack([metal, metal, metal, ones]), "Non-Color")
        maps["rough_" + finish] = (np.dstack([rough, rough, rough, ones]), "Non-Color")
    return {name: (_half(array), space) for name, (array, space) in maps.items()}


def save(maps, name, folder):
    """Writes every map as <name>_<map>.png in folder. Returns {map: path}."""
    os.makedirs(folder, exist_ok=True)
    paths = {}
    for key, (array, space) in maps.items():
        height, width = array.shape[:2]
        image = bpy.data.images.new("%s_%s" % (name, key), width, height, alpha=True)
        image.colorspace_settings.name = space
        image.pixels.foreach_set(np.clip(array, 0.0, 1.0).astype(np.float32).ravel())
        path = os.path.join(folder, "%s_%s.png" % (name, key))
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        paths[key] = path
    return paths


def material(name, paths, finish, tint_of_role, glow_color):
    """Preview materials that look the way the game will draw the maps: {role: material}."""
    made = {}
    for role in ROLE_ID:
        tint = tint_of_role.get(role, (1.0, 1.0, 1.0))
        mat = bpy.data.materials.new("%s_%s_worn" % (name, role))
        mat.use_nodes = True
        tree = mat.node_tree
        bsdf = tree.nodes["Principled BSDF"]
        color = _node(tree, "ShaderNodeTexImage", (-900, 300), image=bpy.data.images.load(paths["color"], check_existing=True))
        # TintMask: color times a mix of white and the tint, by the map's alpha.
        mix = _node(tree, "ShaderNodeMix", (-500, 300), data_type="RGBA", blend_type="MIX")
        mix.inputs[6].default_value = (1, 1, 1, 1)
        mix.inputs[7].default_value = (*tint, 1)
        tree.links.new(color.outputs["Alpha"], mix.inputs[0])
        multiply = _node(tree, "ShaderNodeMix", (-250, 300), data_type="RGBA", blend_type="MULTIPLY")
        multiply.inputs[0].default_value = 1.0
        tree.links.new(color.outputs["Color"], multiply.inputs[6])
        tree.links.new(mix.outputs[2], multiply.inputs[7])
        tree.links.new(multiply.outputs[2], bsdf.inputs["Base Color"])
        for key, socket in (("metal_" + finish, "Metallic"), ("rough_" + finish, "Roughness")):
            texture = _node(tree, "ShaderNodeTexImage", (-900, 0), image=bpy.data.images.load(paths[key], check_existing=True))
            texture.image.colorspace_settings.name = "Non-Color"
            tree.links.new(texture.outputs["Color"], bsdf.inputs[socket])
        normal = _node(tree, "ShaderNodeTexImage", (-900, -300), image=bpy.data.images.load(paths["normal"], check_existing=True))
        normal.image.colorspace_settings.name = "Non-Color"
        normal_map = _node(tree, "ShaderNodeNormalMap", (-500, -300), space="TANGENT")
        tree.links.new(normal.outputs["Color"], normal_map.inputs["Color"])
        tree.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
        made[role] = mat
    glow = bpy.data.materials.new(name + "_Glow")
    glow.use_nodes = True
    bsdf = glow.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*glow_color, 1)
    bsdf.inputs["Emission Color"].default_value = (*glow_color, 1)
    bsdf.inputs["Emission Strength"].default_value = 2.5
    made["Glow"] = glow
    return made
