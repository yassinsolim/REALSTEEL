"""Concept renders of whole robot frames: lineups of several robots side by side, each in its own paint, and a lit hero
shot of one robot. Used to review new frames before they go into the game.
"""

import math

import bpy
from mathutils import Vector

import preview
import preview_kits
import robotlib

# metallic, roughness, emission strength per material role
STYLE = {
    "Armor": (0.45, 0.38, 0.0),
    "Dark": (0.55, 0.55, 0.0),
    "Steel": (1.0, 0.18, 0.0),
    "Trim": (0.6, 0.3, 0.0),
    "Glow": (0.0, 0.3, 2.5),
}


def materials(roles, prefix):
    """Role materials from a frame's ROLES (its stock paint)."""
    made = {}
    for role, style in roles.items():
        color = tuple(style["color"])
        metallic, roughness, emission = STYLE.get(role, (0.5, 0.5, 0.0))
        material = bpy.data.materials.new("%s_%s" % (prefix, role))
        material.use_nodes = True
        material.diffuse_color = (*color, 1)
        bsdf = material.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission > 0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1)
            bsdf.inputs["Emission Strength"].default_value = emission
        made[role] = material
    return made


def setup(engine):
    """The preview scene, with a softer tone curve so glowing parts keep their color."""
    preview.setup_scene(engine)
    bpy.context.scene.view_settings.view_transform = "AgX"


def lineup(entries, path, view="three", spacing=6.4, size=(3000, 1050), center_y=3.5):
    """One row of robots. entries is [(label, robot, materials, pose, scale)]; view is front, three or side."""
    count = len(entries)
    created = []
    azimuth = {"front": 0.0, "three": 35.0, "side": 90.0}[view]
    angle = math.radians(azimuth)
    right = (-math.cos(angle), 0, -math.sin(angle))
    toward_camera = (math.sin(angle), 0, -math.cos(angle))
    for index, (label, robot, mats, pose, scale) in enumerate(entries):
        slot = (index - (count - 1) / 2) * spacing
        offset = (right[0] * slot, 0, right[2] * slot)
        created += preview_kits.instance(robot, pose, offset, mats, [], scale)
    width = spacing * count + 4
    elevation = 3.0 if view == "three" else 0.0
    cam = preview.camera(
        (toward_camera[0] * 60, center_y + elevation, toward_camera[2] * 60), (0, center_y, 0), ortho_scale=width
    )
    for index, (label, *_rest) in enumerate(entries):
        slot = (index - (count - 1) / 2) * spacing
        created.append(preview.label(label, (right[0] * slot, center_y + 4.3, right[2] * slot), cam.rotation_euler))
    preview.render(path, size)
    preview.discard(created)
    bpy.data.objects.remove(cam)


def hero(robot, mats, pose, path, accent, scale=1.0, size=(1400, 1600)):
    """One robot from a low three-quarter angle, with a rim light in its accent color."""
    created = preview_kits.instance(robot, pose, (0, 0, 0), mats, [], scale)
    height = 6.5 * scale
    cam = preview.camera((9.5, 2.2, -15.5), (0, height * 0.5, 0), lens=55)
    rim = preview._light("hero_rim", "AREA", 900, (-6, 9, 8), (0, height * 0.6, 0), color=accent, size=6)
    kick = preview._light("hero_kick", "AREA", 500, (8, 2, 6), (0, height * 0.5, 0), color=(0.75, 0.85, 1.0), size=4)
    preview.render(path, size)
    preview.discard(created)
    for obj in (cam, rim, kick):
        bpy.data.objects.remove(obj)


def lowest(robot, pose):
    """The lowest point of a posed robot, to check it stands on the floor."""
    everything = tuple(joint.name for joint in robot.joints)
    return min(point.y for point in robotlib.world_vertices(robot, pose, everything))


def bounds(robot):
    """The rest pose's extent in x, y and z, for a quick silhouette comparison."""
    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    everything = tuple(joint.name for joint in robot.joints)
    for point in robotlib.world_vertices(robot, {"pos": (0, 0, 0), "rot": {}}, everything):
        for axis in range(3):
            low[axis] = min(low[axis], point[axis])
            high[axis] = max(high[axis], point[axis])
    return low, high
