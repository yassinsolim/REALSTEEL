"""Preview renders for the procedural robots: a lit scene, role materials, and posed copies for contact sheets."""

import math

import bpy
from mathutils import Matrix, Vector

import robotlib

# metallic, roughness, emission strength
LOOK = {"Armor": (0.85, 0.42, 0.0), "Dark": (0.6, 0.5, 0.0), "Trim": (0.45, 0.35, 0.0), "Glow": (0.0, 0.3, 6.0)}


def role_materials(roles, team=None):
    materials = {}
    for role, style in roles.items():
        metallic, roughness, emission = LOOK.get(role, (0.5, 0.5, 0.0))
        color = tuple(team) if team is not None and style["tint"] else tuple(style["color"])
        material = bpy.data.materials.new(role)
        material.use_nodes = True
        material.diffuse_color = (*color, 1)
        bsdf = material.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission > 0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1)
            bsdf.inputs["Emission Strength"].default_value = emission
        materials[role] = material
    return materials


def _light(name, kind, energy, location, target, color=(1, 1, 1), size=None):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if size is not None and kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = robotlib.to_blender(location)
    direction = robotlib.to_blender(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


def setup_scene(engine):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE" if engine == "EEVEE" else "BLENDER_WORKBENCH"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    if engine == "EEVEE":
        scene.eevee.taa_render_samples = 24
    else:
        shading = scene.display.shading
        shading.light = "STUDIO"
        shading.color_type = "MATERIAL"
        shading.show_cavity = True
        shading.show_object_outline = True
        shading.show_specular_highlight = True
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.045, 0.05, 0.065, 1)
    background.inputs["Strength"].default_value = 1.0
    scene.world = world

    bpy.ops.mesh.primitive_plane_add(size=400)
    floor = bpy.context.active_object
    floor.location = (0, 0, -0.001)
    floor.name = "PreviewFloor"
    material = bpy.data.materials.new("floor")
    material.use_nodes = True
    material.diffuse_color = (0.07, 0.08, 0.1, 1)
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.07, 0.08, 0.1, 1)
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    floor.data.materials.append(material)

    _light("key", "SUN", 3.5, (20, 30, -15), (0, 3, 0))
    _light("fill", "SUN", 1.2, (-20, 10, 20), (0, 3, 0), color=(0.7, 0.8, 1.0))
    _light("rim", "SUN", 2.0, (0, 12, 30), (0, 3, 0), color=(1.0, 0.85, 0.7))


def hide_originals(robot):
    for part in robot.parts:
        part.obj.hide_render = True
        part.obj.hide_viewport = True


def pose_instances(robot, pose, offset, materials):
    """Copies of every part posed in Roblox axes and shifted by offset (also Roblox axes)."""
    world = robotlib.solve(robot, pose)
    shift = Matrix.Translation(Vector(offset))
    copies = []
    for part in robot.parts:
        if not part.obj.data.materials:
            part.obj.data.materials.append(materials[part.role])
        copy = part.obj.copy()
        copy.hide_render = False
        copy.hide_viewport = False
        bpy.context.scene.collection.objects.link(copy)
        copy.matrix_world = robotlib.BASIS @ shift @ robotlib.part_matrix(robot, world, part) @ robotlib.BASIS.inverted()
        copies.append(copy)
    return copies


def label(text, position, camera_rotation, size=0.55):
    curve = bpy.data.curves.new("label", "FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    obj = bpy.data.objects.new("label", curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = robotlib.to_blender(position)
    obj.rotation_euler = camera_rotation
    material = bpy.data.materials.new("label")
    material.diffuse_color = (1, 1, 1, 1)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
    bsdf.inputs["Emission Color"].default_value = (1, 1, 1, 1)
    bsdf.inputs["Emission Strength"].default_value = 1.0
    obj.data.materials.append(material)
    return obj


def camera(position, target, ortho_scale=None, lens=50):
    data = bpy.data.cameras.new("cam")
    if ortho_scale is not None:
        data.type = "ORTHO"
        data.ortho_scale = ortho_scale
    else:
        data.lens = lens
    obj = bpy.data.objects.new("cam", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = robotlib.to_blender(position)
    direction = robotlib.to_blender(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = obj
    return obj


def render(path, size):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def discard(objects):
    for obj in objects:
        data = obj.data
        bpy.data.objects.remove(obj)
        if data is not None and data.users == 0 and isinstance(data, bpy.types.Curve):
            bpy.data.curves.remove(data)


def sheet(robot, poses, path, materials, view="side", spacing=6.5, size=(2400, 700), names=True):
    """One row of posed robots, left to right in list order. poses is [(label, pose)]."""
    count = len(poses)
    created = []
    cam = None
    if view == "side":
        # Viewed from +x looking toward -x: screen right is -z, so a robot (facing -z) faces right.
        for index, (name, pose) in enumerate(poses):
            z = -(index - (count - 1) / 2) * spacing
            created += pose_instances(robot, pose, (0, 0, z), materials)
        width = spacing * count + 6
        cam = camera((60, 3.6, 0), (0, 3.6, 0), ortho_scale=width)
        for index, (name, pose) in enumerate(poses):
            z = -(index - (count - 1) / 2) * spacing
            if names:
                created.append(label(name, (0, 7.4, z), cam.rotation_euler))
    else:
        for index, (name, pose) in enumerate(poses):
            x = -(index - (count - 1) / 2) * spacing
            created += pose_instances(robot, pose, (x, 0, 0), materials)
        width = spacing * count + 6
        cam = camera((0, 3.6, -60), (0, 3.6, 0), ortho_scale=width)
        for index, (name, pose) in enumerate(poses):
            x = -(index - (count - 1) / 2) * spacing
            if names:
                created.append(label(name, (x, 7.4, 0), cam.rotation_euler))
    render(path, size)
    discard(created)
    bpy.data.objects.remove(cam)
