"""Builds the robots: every frame's meshes, worn-metal textures, FBX and rig data, the poses and preview renders. Run
headless through scripts/art.ps1:

    blender --background --factory-startup --python art/build_robot.py -- --out art/build --luau src/shared \
        --previews poses --engine WORKBENCH

Outputs in --out (regenerable, not tracked): <Name>.fbx, <Name>.rig.json, textures/<Name>_*.png (see wear.py), preview
PNGs. --luau gets RobotRigs.luau (every frame), RobotClips.luau and RobotKits.luau (the crests from art/kits.py).
--frames BULWARK,LANCE limits the textures and FBX to those frames. --previews kits renders the crests and paint jobs,
frames the frames, worn the frames wearing their textures; a preview run exports nothing.
"""

import argparse
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import anvil  # noqa: E402
import bulwark  # noqa: E402
import exporters  # noqa: E402
import kits  # noqa: E402
import lance  # noqa: E402
import maul  # noqa: E402
import poses as pose_library  # noqa: E402
import preview  # noqa: E402
import preview_frames  # noqa: E402
import preview_kits  # noqa: E402
import razor  # noqa: E402
import robotlib  # noqa: E402
import wear  # noqa: E402

TEAM_BLUE = (0.12, 0.42, 1.0)

# The five free frames: label, module, the chassis' scale in game (keep in step with Loadout.luau).
FRAMES = (("ANVIL", anvil, 1.0), ("BULWARK", bulwark, 1.08), ("LANCE", lance, 1.1), ("RAZOR", razor, 0.94), ("MAUL", maul, 1.06))

SHEETS = {
    "attacks": ("side", ["Stance", "Guard", "JabChamber", "JabStrike", "StraightChamber", "StraightStrike"]),
    "kicks": ("side", ["Stance", "SnapChamber", "SnapStrike", "PowerChamber", "PowerStrike", "PowerHold"]),
    "reactions": ("side", ["HitLightPeak", "HitHeavyPeak", "BlockRecoil", "KoBuckle", "KoFall", "KoDown"]),
    "movement": ("side", ["DashCoil", "DashF", "DashB", "WalkF0", "WalkF1", "WalkB1"]),
    "front": ("front", ["Stance", "Guard", "JabStrike", "StraightStrike", "DashL", "DashR"]),
    "emotes": ("front", ["IntroA", "IntroB", "VictoryA", "VictoryB", "Slump", "Stance"]),
}

# What each strike's limb must reach to look like it connects at the longest range the hit detection allows:
# reach + hitRadius + BodyRadius from FightConfig, less the half depth of the defender's body. Keep in step with
# FightConfig; RobotSpec is the check that fails when they drift apart.
REACH_CHECKS = (
    ("JabStrike", "HandL", 4.15),
    ("JabHold", "HandL", 4.15),
    ("StraightStrike", "HandR", 4.95),
    ("SnapStrike", "FootL", 3.65),
    ("SnapHold", "FootL", 3.65),
    ("PowerStrike", "FootR", 3.95),
    ("PowerHold", "FootR", 3.95),
)


def parse():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="art/build")
    parser.add_argument("--luau", default="")
    parser.add_argument("--previews", default="none", choices=["none", "rest", "poses", "all", "kits", "frames", "worn"])
    parser.add_argument("--sheets", default="")
    parser.add_argument("--frames", default="", help="comma-separated frame labels to export (default: all)")
    parser.add_argument("--engine", default="WORKBENCH", choices=["WORKBENCH", "EEVEE"])
    return parser.parse_args(arguments)


def report(robot, poses):
    for name, hand, needed in REACH_CHECKS:
        reach = robotlib.front_extent(robot, poses[name], hand)
        print("reach %-15s %s front %.2f studs (hit range needs about %.2f)" % (name, hand, reach, needed))
    everything = tuple(joint.name for joint in robot.joints)
    for name in ("Stance", "Guard", "WalkF1", "KoDown"):
        low = min(point.y for point in robotlib.world_vertices(robot, poses[name], everything))
        print("lowest point %-8s y = %.3f" % (name, low))


STEEL = (0.52, 0.56, 0.66)
GUNMETAL = (0.2, 0.21, 0.26)
BLUE = (0.18, 0.5, 1.0)
RED = (1.0, 0.33, 0.27)


def kit_previews(robot, out, sheets, poses):
    """Contact sheets of the crests and of paint jobs on ANVIL. --sheets picks some of them. (The chassis are frames of
    their own now; --previews frames renders them.)"""
    kits.build()
    wanted = sheets.split(",") if sheets else ["crests", "looks"]
    steel = preview_kits.palette_materials(STEEL, BLUE)
    if "crests" in wanted:
        entries = [(name, {"kits": [name], "materials": steel}) for name in kits.CRESTS]
        preview_kits.sheet(
            robot, entries, os.path.join(out, "kits_crests.png"), "front", 3.4, (1800, 700), center_y=6.0, ortho=15
        )
    if "looks" in wanted:
        cyan = (0.25, 0.85, 1.0)
        gold = (1.0, 0.75, 0.2)
        violet = (0.65, 0.35, 1.0)
        lime = (0.55, 1.0, 0.3)
        looks = (
            ("STEEL BLUE", preview_kits.palette_materials(STEEL, BLUE, "BRUSHED")),
            ("GUN RED", preview_kits.palette_materials(GUNMETAL, RED, "MATTE")),
            ("CHROME", preview_kits.palette_materials((0.8, 0.82, 0.86), cyan, "CHROME")),
            ("GOLD", preview_kits.palette_materials((0.62, 0.5, 0.2), gold, "GLOSS", (0.08, 0.07, 0.05))),
            ("VIOLET", preview_kits.palette_materials((0.24, 0.18, 0.34), violet, "MATTE")),
            ("TOXIC", preview_kits.palette_materials((0.14, 0.2, 0.12), lime, "BRUSHED")),
        )
        entries = [(name, {"kits": [], "materials": materials}) for name, materials in looks]
        preview_kits.sheet(robot, entries, os.path.join(out, "kits_looks.png"), "front", 6.2, (2800, 900))


def worn_previews(anvil_robot, out, engine):
    """Bakes the worn-metal textures of every frame into out/textures, then renders each frame with them: a hero shot
    each and a lineup in the fighting stance."""
    import time

    frames = []
    for label, module, scale in FRAMES:
        robot = anvil_robot if module is anvil else module.build()
        started = time.time()
        wear.unwrap(robot)
        paths = wear.save(wear.compose(wear.bake(robot)), robot.name, os.path.join(out, "textures"))
        print("worn %-8s baked in %.1f s" % (label, time.time() - started))
        frames.append((label, robot, module.ROLES, scale, paths))
    preview_frames.setup(engine)
    for _label, robot, _roles, _scale, _paths in frames:
        preview.hide_originals(robot)
    fighting = []
    for label, robot, roles, scale, paths in frames:
        tints = {role: tuple(roles[role]["color"]) for role in ("Armor", "Trim")}
        mats = wear.material(label, paths, "BRUSHED", tints, tuple(roles["Glow"]["color"]))
        stance = pose_library.finalize(robot)["Stance"]
        accent = tuple(roles["Trim"]["color"])
        preview_frames.hero(robot, mats, stance, os.path.join(out, "worn_%s.png" % label.lower()), accent, scale)
        fighting.append((label, robot, mats, stance, scale))
    preview_frames.lineup(fighting, os.path.join(out, "worn_stance.png"), "three")


def frame_previews(anvil_robot, out):
    """Concept renders of the frames: the five chassis in lineups at rest, in the fighting stance and mid-punch, and a
    hero shot of each."""
    frames = []
    for label, module, scale in FRAMES:
        robot = anvil_robot if module is anvil else module.build()
        preview.hide_originals(robot)
        frames.append((label, robot, module.ROLES, scale))
    rest = {"pos": (0, 0, 0), "rot": {}}
    standing = []
    fighting = []
    striking = []
    for label, robot, roles, scale in frames:
        mats = preview_frames.materials(roles, label)
        poses = pose_library.finalize(robot)
        low, high = preview_frames.bounds(robot)
        print(
            "frame %-8s %3d parts, %5d triangles, %.2f wide, %.2f tall, %.2f deep; lowest in Stance y = %.3f"
            % (
                label,
                len(robot.parts),
                sum(part.triangles for part in robot.parts),
                high.x - low.x,
                high.y - low.y,
                high.z - low.z,
                preview_frames.lowest(robot, poses["Stance"]),
            )
        )
        for name, hand, needed in REACH_CHECKS:
            reach = robotlib.front_extent(robot, poses[name], hand)
            if reach < needed:
                print("  reach %-15s %s %.2f studs, short of %.2f" % (name, hand, reach, needed))
        standing.append((label, robot, mats, rest, scale))
        fighting.append((label, robot, mats, poses["Stance"], scale))
        striking.append((label, robot, mats, poses["StraightStrike"], scale))
    preview_frames.lineup(standing, os.path.join(out, "frames_front.png"), "front")
    preview_frames.lineup(standing, os.path.join(out, "frames_three.png"), "three")
    preview_frames.lineup(fighting, os.path.join(out, "frames_stance.png"), "three")
    preview_frames.lineup(striking, os.path.join(out, "frames_strike.png"), "side")
    for label, robot, roles, scale in frames:
        mats = preview_frames.materials(roles, label + "hero")
        stance = pose_library.finalize(robot)["Stance"]
        accent = tuple(roles["Trim"]["color"])
        preview_frames.hero(robot, mats, stance, os.path.join(out, "hero_%s.png" % label.lower()), accent, scale)


def discard_robot(robot):
    """Removes a built frame's objects and meshes, so the next frame can use the same part names."""
    for part in robot.parts:
        mesh = part.obj.data
        bpy.data.objects.remove(part.obj)
        bpy.data.meshes.remove(mesh)


def export_frames(out, luau, only=None):
    """Every frame in turn: worn textures baked onto its UV atlas, then its FBX and rig JSON with the same UVs. One frame
    is in the scene at a time, so every frame's parts keep their plain names (Chest_Armor, not Chest_Armor.001). `only`
    (a set of frame labels) limits the textures and FBX to those frames; every frame still goes into the rig module.
    Returns the rigs for the Luau module as [(robot, roles)] and ANVIL's poses for the clips."""
    rigs = []
    poses = None
    for label, module, _scale in FRAMES:
        robot = module.build()
        print("frame %-8s %3d parts, %5d triangles" % (label, len(robot.parts), sum(part.triangles for part in robot.parts)))
        robot_poses = pose_library.finalize(robot)
        for name, hand, needed in REACH_CHECKS:
            reach = robotlib.front_extent(robot, robot_poses[name], hand)
            if reach < needed:
                print("  reach %-15s %s %.2f studs, short of %.2f" % (name, hand, reach, needed))
        if module is anvil:
            poses = robot_poses
            report(robot, poses)
        if only is None or label in only:
            wear.unwrap(robot)
            wear.save(wear.compose(wear.bake(robot)), robot.name, os.path.join(out, "textures"))
            exporters.export_fbx(robot, out)
            exporters.export_json(robot, module.ROLES, out)
            print("  exported %s.fbx and its textures" % robot.name)
        rigs.append((robot, module.ROLES))
        discard_robot(robot)
    if luau:
        exporters.export_luau(rigs, os.path.join(luau, "RobotRigs.luau"))
    return poses


def main():
    options = parse()
    out = os.path.abspath(options.out)
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    if options.previews == "none":
        luau = os.path.abspath(options.luau) if options.luau else ""
        only = set(options.frames.upper().split(",")) if options.frames else None
        poses = export_frames(out, luau, only)
        if luau:
            exporters.export_clips(poses, pose_library.CLIPS, os.path.join(luau, "RobotClips.luau"))
            kits.build()
            kits.export_luau(os.path.join(luau, "RobotKits.luau"))
        return

    robot = anvil.build()
    poses = pose_library.finalize(robot)
    if options.previews == "worn":
        worn_previews(robot, out, options.engine)
        return
    preview.hide_originals(robot)
    if options.previews == "frames":
        preview_frames.setup(options.engine)
        frame_previews(robot, out)
        return
    preview.setup_scene(options.engine)
    materials = preview.role_materials(anvil.ROLES, TEAM_BLUE)
    if options.previews == "kits":
        kit_previews(robot, out, options.sheets, poses)
        return
    if options.previews in ("rest", "all"):
        rest = {"pos": (0, 0, 0), "rot": {}}
        preview.sheet(robot, [("rest", rest)], os.path.join(out, "rest_front.png"), materials, "front", 9, (700, 900), False)
    if options.previews in ("poses", "all"):
        wanted = options.sheets.split(",") if options.sheets else list(SHEETS)
        for key in wanted:
            view, names = SHEETS[key]
            entries = [(name, poses[name]) for name in names]
            preview.sheet(robot, entries, os.path.join(out, "poses_%s.png" % key), materials, view)


main()
