"""RAZOR: the rushdown. A light, sharp prize-fighter: angled plates over a cinched waist, a wedge helmet with a V of eye
slits, swept blade-like shoulder plates, razor edges along slim forearms, stinger fins on the back, quick compact fists and
light feet with heel spurs. The armor plates sit on a dark frame, so the gaps between them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z.
"""

from greebles import cables, piston, vents
from robotlib import Robot
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.86, 0.86, 0.84), "material": "Metal", "tint": False},
    "Dark": {"color": (0.03, 0.03, 0.035), "material": "Metal", "tint": False},
    "Steel": {"color": (0.62, 0.64, 0.68), "material": "Metal", "tint": False},
    "Trim": {"color": (0.85, 0.07, 0.12), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.2, 0.22), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Razor", smooth=True)
    add_joints(robot)
    pelvis(robot)
    chest(robot)
    head(robot)
    for side, sign in SIDES:
        arm(robot, side, sign)
        leg(robot, side, sign)
    robot.finish()
    return robot


def pelvis(robot):
    dark = robot.part("Pelvis", "Dark")
    dark.box((0, 3.06, 0), (1.15, 0.44, 0.8), bevel=0.06)
    dark.box((0, 3.33, 0), (1.25, 0.16, 0.86), bevel=0.04)
    for sign in (1, -1):
        dark.cylinder((0.28 * sign, 3.0, 0), (0.9 * sign, 3.0, 0), 0.31, segments=12)
    armor = robot.part("Pelvis", "Armor")
    armor.taper((0, 2.9, -0.42), 0.5, (0.32, 0.12), (0.66, 0.14), bevel=0.04, segments=3)
    for sign in (1, -1):
        armor.box((0.86 * sign, 2.98, -0.05), (0.12, 0.6, 0.78), bevel=0.05, segments=3, rot=(0, 18 * sign, -10 * sign))
    armor.box((0, 3.0, 0.42), (0.78, 0.38, 0.12), bevel=0.04)
    robot.part("Pelvis", "Trim").box((0, 3.33, -0.45), (0.9, 0.12, 0.05), bevel=0.02)


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.cylinder((0, 3.42, 0), (0, 4.12, 0), 0.3, segments=12)
    dark.taper((0, 4.74, 0.02), 1.2, (1.0, 0.78), (1.9, 0.98), bevel=0.07)
    dark.cylinder((0, 5.3, 0.05), (0, 5.5, 0.05), 0.26, segments=10)
    armor = robot.part("Chest", "Armor")
    trim = robot.part("Chest", "Trim")
    for index, y in enumerate((3.66, 3.86)):
        armor.box((0, y, -0.06), (0.66 + 0.1 * index, 0.13, 0.6), bevel=0.03)
    for sign in (1, -1):
        # Sharp, angled pectorals; flank plates following the V; collar blades; stinger fins on the back.
        armor.taper((0.46 * sign, 4.95, -0.44), 0.72, (0.58, 0.12), (0.92, 0.14), bevel=0.05, segments=3,
                    rot=(-10, -18 * sign, 0))
        armor.box((0.8 * sign, 4.62, 0.0), (0.1, 0.9, 0.7), bevel=0.04, rot=(0, 0, -20 * sign))
        armor.box((0.5 * sign, 5.4, -0.05), (0.5, 0.16, 0.7), bevel=0.04, rot=(0, 0, -14 * sign))
        trim.box((0.22 * sign, 5.2, 0.62), (0.1, 0.75, 0.3), bevel=0.03, rot=(34, 0, 10 * sign))
        # A V on the chest, under the pectorals.
        trim.box((0.21 * sign, 4.36, -0.42), (0.5, 0.08, 0.05), bevel=0.02, rot=(0, 0, 34 * sign))
        vents(dark, (0.62 * sign, 4.15, -0.3), (0.3, 0.3, 0.05), 3)
    armor.box((0, 4.72, 0.52), (1.2, 0.9, 0.12), bevel=0.04, rot=(6, 0, 0))
    robot.part("Chest", "Glow").box((0, 4.2, -0.44), (0.16, 0.08, 0.04), bevel=0.01, segments=1)
    cables(robot.part("Chest", "Steel"), (0, 3.5, 0.3), (0, 4.25, 0.36), [(0.1, 0, 0), (-0.1, 0, 0)], radius=0.045)


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.36, 0.05), (0, 5.62, 0.05), 0.19, segments=10)
    armor = robot.part("Head", "Armor")
    # A wedge helmet with a beak over the face.
    armor.taper((0, 5.9, 0.08), 0.6, (0.58, 0.82), (0.5, 0.72), bevel=0.08, segments=3)
    armor.box((0, 6.0, -0.32), (0.3, 0.2, 0.34), bevel=0.06, rot=(-25, 0, 0))
    dark.box((0, 5.8, -0.33), (0.5, 0.3, 0.12), bevel=0.03)
    glow = robot.part("Head", "Glow")
    trim = robot.part("Head", "Trim")
    for sign in (1, -1):
        # A V of eye slits, and blades swept back off the temples.
        glow.box((0.12 * sign, 5.83, -0.4), (0.2, 0.05, 0.03), bevel=0.01, segments=1, rot=(0, 0, 20 * sign))
        trim.box((0.3 * sign, 6.02, 0.25), (0.07, 0.12, 0.62), bevel=0.02, rot=(-25, 0, -15 * sign))
        armor.box((0.27 * sign, 5.68, -0.22), (0.07, 0.24, 0.36), bevel=0.02, rot=(0, -14 * sign, 0))


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.32)
    dark.cylinder((1.5 * sign, 4.85, 0), (1.53 * sign, 4.12, 0), 0.21, segments=10)
    armor = robot.part(upper, "Armor")
    # A shoulder plate swept back like a blade.
    armor.box((1.58 * sign, 5.24, 0.05), (0.7, 0.34, 0.8), bevel=0.1, segments=3, rot=(12, 0, -14 * sign))
    armor.box((1.53 * sign, 4.5, -0.2), (0.34, 0.6, 0.1), bevel=0.04)
    robot.part(upper, "Trim").box((1.74 * sign, 5.32, 0.32), (0.08, 0.2, 0.9), bevel=0.02, rot=(16, 0, -20 * sign))
    cables(robot.part(upper, "Steel"), (1.42 * sign, 4.88, 0.18), (1.45 * sign, 4.12, 0.2), [(0, 0, 0)], radius=0.05)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.32 * sign, 3.95, 0), (1.78 * sign, 3.95, 0), 0.25, segments=12)
    armor = robot.part(fore, "Armor")
    armor.taper((1.6 * sign, 3.38, 0), 1.02, (0.6, 0.62), (0.52, 0.56), bevel=0.1, segments=3)
    # A razor edge down the outside, widest at the wrist.
    robot.part(fore, "Trim").taper((1.92 * sign, 3.38, 0), 1.1, (0.07, 0.5), (0.07, 0.18), bevel=0.02)
    robot.part(fore, "Glow").box((1.6 * sign, 3.42, -0.3), (0.06, 0.66, 0.03), bevel=0.01, segments=1)

    hand = "Hand" + side
    dark = robot.part(hand, "Dark")
    dark.cylinder((1.62 * sign, 2.9, 0), (1.62 * sign, 2.77, 0), 0.3, segments=12)
    armor = robot.part(hand, "Armor")
    armor.box((1.63 * sign, 2.38, 0), (0.64, 0.66, 0.72), bevel=0.14, segments=3)
    armor.box((1.35 * sign, 2.44, -0.22), (0.16, 0.3, 0.22), bevel=0.06)
    robot.part(hand, "Steel").box((1.64 * sign, 1.99, 0), (0.52, 0.1, 0.64), bevel=0.04)
    # Wrist wraps.
    for y in (2.72, 2.8):
        dark.box((1.62 * sign, y, 0), (0.66, 0.05, 0.74), bevel=0.02)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.32)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.2, segments=10)
    armor = robot.part(thigh, "Armor")
    armor.taper((0.64 * sign, 2.38, -0.14), 1.0, (0.46, 0.3), (0.62, 0.36), bevel=0.06, segments=3)
    armor.box((0.88 * sign, 2.45, 0.02), (0.08, 0.72, 0.54), bevel=0.03, rot=(0, 0, 6 * sign))
    robot.part(thigh, "Trim").box((0.64 * sign, 2.38, -0.31), (0.08, 0.66, 0.03), bevel=0.01, segments=1)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.38 * sign, 1.62, 0), (0.9 * sign, 1.62, 0), 0.25, segments=12)
    dark.cylinder((0.64 * sign, 1.5, 0.0), (0.64 * sign, 0.62, 0.0), 0.19, segments=10)
    armor = robot.part(shin, "Armor")
    # A knee spike pointing forward, a shin blade and a calf plate.
    armor.taper((0.64 * sign, 1.68, -0.36), 0.4, (0.36, 0.26), (0.12, 0.1), bevel=0.03, rot=(-90, 0, 0))
    armor.taper((0.64 * sign, 1.04, -0.18), 0.92, (0.34, 0.2), (0.52, 0.28), bevel=0.05, segments=3)
    armor.box((0.64 * sign, 1.16, 0.26), (0.38, 0.58, 0.2), bevel=0.06, rot=(14, 0, 0))
    robot.part(shin, "Trim").box((0.64 * sign, 1.04, -0.3), (0.07, 0.56, 0.03), bevel=0.01, segments=1)
    piston(dark, robot.part(shin, "Steel"), (0.64 * sign, 1.42, 0.4), (0.64 * sign, 0.7, 0.3), 0.065)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.24)
    dark.box((0.66 * sign, 0.09, -0.2), (0.58, 0.18, 1.34), bevel=0.05)
    armor = robot.part(foot, "Armor")
    armor.taper((0.66 * sign, 0.32, -0.28), 0.28, (0.56, 1.12), (0.44, 0.94), bevel=0.06, segments=3)
    armor.box((0.65 * sign, 0.54, 0.02), (0.46, 0.28, 0.56), bevel=0.06)
    robot.part(foot, "Trim").box((0.66 * sign, 0.3, -0.86), (0.4, 0.16, 0.12), bevel=0.04)
    # A spur off the heel.
    robot.part(foot, "Steel").taper((0.66 * sign, 0.3, 0.62), 0.3, (0.2, 0.16), (0.04, 0.04), bevel=0.01,
                                    rot=(90, 0, 0))
