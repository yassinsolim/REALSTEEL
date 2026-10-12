"""Builds the robot: meshes, FBX, rig data, poses and preview renders. Run headless through scripts/art.ps1:

    blender --background --factory-startup --python art/build_robot.py -- --out art/build --luau src/shared \
        --previews poses --engine WORKBENCH

Outputs in --out (regenerable, not tracked): <Name>.fbx, <Name>.rig.json, preview PNGs. --luau gets RobotRigs.luau,
RobotClips.luau and RobotKits.luau (the add-on kits from art/kits.py). --previews kits renders the kits on the robot.
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


# Chassis as the game draws them. Keep the scales in step with Loadout.luau.
CHASSIS_LOOK = (("ANVIL", 1.0), ("BULWARK", 1.08), ("LANCE", 1.1), ("RAZOR", 0.94), ("MAUL", 1.06))
STEEL = (0.52, 0.56, 0.66)
GUNMETAL = (0.2, 0.21, 0.26)
BLUE = (0.18, 0.5, 1.0)
RED = (1.0, 0.33, 0.27)


def kit_previews(robot, out, sheets, poses):
    """Contact sheets of the kits: chassis, modules, crests and paint. --sheets picks some of them."""
    kits.build()
    wanted = sheets.split(",") if sheets else ["chassis", "modules", "crests", "looks"]
    steel = preview_kits.palette_materials(STEEL, BLUE)
    if "chassis" in wanted:
        entries = []
        for name, scale in CHASSIS_LOOK:
            entries.append((name, {"kits": preview_kits.kits_for(name), "scale": scale, "materials": steel}))
        for view in ("front", "three", "side"):
            preview_kits.sheet(robot, entries, os.path.join(out, "kits_chassis_%s.png" % view), view, 6.8, (2400, 900))
        for name, spec in entries:
            spec["pose"] = poses["JabStrike"]
        preview_kits.sheet(robot, entries, os.path.join(out, "kits_chassis_jab.png"), "side", 7.4, (2400, 900))
    if "modules" in wanted:
        entries = [("STOCK", {"kits": [], "materials": steel})]
        for slot, options in kits.MODULE_KITS.items():
            for option, kit_name in options.items():
                arms, core, legs = (option if slot == name else 1 for name in ("ARMS", "CORE", "LEGS"))
                entries.append((kit_name, {"kits": preview_kits.kits_for("ANVIL", arms, core, legs), "materials": steel}))
        for view in ("front", "three", "side"):
            preview_kits.sheet(robot, entries, os.path.join(out, "kits_modules_%s.png" % view), view, 6.2, (2800, 900))
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
        signals, ids, normal = wear.bake(robot)
        paths = wear.save(wear.compose(signals, ids, normal), robot.name, os.path.join(out, "textures"))
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


def main():
    options = parse()
    out = os.path.abspath(options.out)
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    robot = anvil.build()
    print("total %d parts, %d triangles" % (len(robot.parts), sum(part.triangles for part in robot.parts)))
    exporters.export_fbx(robot, out)
    exporters.export_json(robot, anvil.ROLES, out)
    poses = pose_library.finalize(robot)
    report(robot, poses)
    if options.luau:
        luau = os.path.abspath(options.luau)
        exporters.export_luau(robot, anvil.ROLES, os.path.join(luau, "RobotRigs.luau"))
        exporters.export_clips(poses, pose_library.CLIPS, os.path.join(luau, "RobotClips.luau"))
        kits.build()
        kits.export_luau(os.path.join(luau, "RobotKits.luau"))

    if options.previews == "none":
        return
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
