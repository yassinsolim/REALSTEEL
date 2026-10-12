"""LANCE: the long-reach poker. A lean racer: a sharp V-shaped torso around a reactor in the solar plexus, a narrow wedge
head with a single lens and a swept fin, slim limbs with exposed cable tendons, fins on the forearms and a spear tip on
every fist. The armor plates sit on a dark frame, so the gaps between them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z.
"""

from greebles import cables, piston
from robotlib import Robot
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.06, 0.17, 0.5), "material": "Metal", "tint": False},
    "Dark": {"color": (0.03, 0.035, 0.045), "material": "Metal", "tint": False},
    "Steel": {"color": (0.66, 0.68, 0.72), "material": "Metal", "tint": False},
    "Trim": {"color": (1.0, 0.45, 0.08), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.5, 0.2), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Lance", smooth=True)
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
    dark.box((0, 3.06, 0), (1.2, 0.46, 0.84), bevel=0.06)
    dark.box((0, 3.34, 0), (1.35, 0.16, 0.9), bevel=0.04)
    for sign in (1, -1):
        dark.cylinder((0.28 * sign, 3.0, 0), (0.92 * sign, 3.0, 0), 0.32, segments=12)
    armor = robot.part("Pelvis", "Armor")
    armor.taper((0, 2.9, -0.44), 0.55, (0.36, 0.12), (0.7, 0.14), bevel=0.04, rot=(8, 0, 0))
    for sign in (1, -1):
        # Hip blades flaring out at the top.
        armor.box((0.98 * sign, 3.02, 0.05), (0.1, 0.6, 0.8), bevel=0.04, rot=(0, 0, -12 * sign))
    armor.box((0, 3.0, 0.45), (0.8, 0.4, 0.12), bevel=0.04)
    robot.part("Pelvis", "Trim").box((0, 3.34, -0.47), (0.5, 0.2, 0.06), bevel=0.02)


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.cylinder((0, 3.42, 0), (0, 4.1, 0), 0.34, segments=12)
    dark.taper((0, 4.72, 0.02), 1.25, (1.05, 0.8), (2.0, 1.0), bevel=0.07)
    dark.cylinder((0, 5.3, 0.05), (0, 5.5, 0.05), 0.28, segments=10)
    armor = robot.part("Chest", "Armor")
    for y in (3.62, 3.8, 3.98):
        armor.box((0, y, -0.05), (0.84, 0.11, 0.66), bevel=0.03)
    for sign in (1, -1):
        armor.box((0.5 * sign, 4.98, -0.5), (0.86, 0.62, 0.12), bevel=0.05, rot=(-8, -16 * sign, 6 * sign))
        armor.box((0.83 * sign, 4.72, 0.0), (0.1, 1.0, 0.75), bevel=0.04, rot=(0, 0, -21 * sign))
        armor.box((0.62 * sign, 5.33, 0.0), (0.82, 0.14, 0.86), bevel=0.04, rot=(0, 0, -8 * sign))
    armor.box((0, 4.75, 0.55), (1.3, 0.95, 0.12), bevel=0.04, rot=(6, 0, 0))
    # The reactor in the solar plexus.
    steel = robot.part("Chest", "Steel")
    steel.cylinder((0, 4.45, -0.4), (0, 4.45, -0.47), 0.34, segments=16)
    dark.cylinder((0, 4.45, -0.46), (0, 4.45, -0.51), 0.27, segments=16)
    robot.part("Chest", "Glow").cylinder((0, 4.45, -0.51), (0, 4.45, -0.53), 0.18, segments=16)
    trim = robot.part("Chest", "Trim")
    for sign in (1, -1):
        # Fins swept back from the shoulders, and cables down the spine.
        trim.box((0.3 * sign, 5.42, 0.62), (0.1, 0.9, 0.42), bevel=0.03, rot=(28, 0, 8 * sign))
        cables(steel, (0.12 * sign, 3.5, 0.3), (0.16 * sign, 4.25, 0.36), [(0, 0, 0), (0.08 * sign, 0, 0.02)])


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.36, 0.05), (0, 5.66, 0.05), 0.2, segments=10)
    armor = robot.part("Head", "Armor")
    armor.taper((0, 5.92, 0.08), 0.66, (0.6, 0.86), (0.46, 0.78), bevel=0.09)
    armor.box((0, 6.02, -0.3), (0.56, 0.2, 0.3), bevel=0.05, rot=(-20, 0, 0))
    for sign in (1, -1):
        armor.box((0.3 * sign, 5.76, -0.24), (0.08, 0.34, 0.44), bevel=0.03, rot=(0, -12 * sign, 0))
    dark.box((0, 5.84, -0.36), (0.46, 0.4, 0.12), bevel=0.04)
    # A single lens.
    robot.part("Head", "Steel").cylinder((0, 5.88, -0.41), (0, 5.88, -0.46), 0.17, segments=16)
    dark.cylinder((0, 5.88, -0.45), (0, 5.88, -0.48), 0.13, segments=16)
    robot.part("Head", "Glow").cylinder((0, 5.88, -0.48), (0, 5.88, -0.5), 0.09, segments=16)
    robot.part("Head", "Trim").box((0, 6.38, 0.16), (0.1, 0.36, 1.15), bevel=0.03, rot=(-12, 0, 0))


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.34)
    dark.cylinder((1.5 * sign, 4.85, 0), (1.53 * sign, 4.1, 0), 0.2, segments=10)
    armor = robot.part(upper, "Armor")
    armor.box((1.6 * sign, 5.26, 0.0), (0.74, 0.4, 0.86), bevel=0.14, segments=3, rot=(0, 0, -12 * sign))
    armor.box((1.52 * sign, 4.5, -0.22), (0.36, 0.64, 0.1), bevel=0.04)
    robot.part(upper, "Trim").box((1.74 * sign, 5.52, 0.26), (0.1, 0.5, 0.82), bevel=0.03, rot=(30, 0, -14 * sign))
    steel = robot.part(upper, "Steel")
    cables(steel, (1.4 * sign, 4.88, 0.2), (1.44 * sign, 4.1, 0.22), [(0, 0, 0), (0.18 * sign, 0, 0)], radius=0.05)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.3 * sign, 3.95, 0), (1.8 * sign, 3.95, 0), 0.26, segments=12)
    armor = robot.part(fore, "Armor")
    armor.taper((1.6 * sign, 3.36, 0), 1.06, (0.66, 0.66), (0.56, 0.6), bevel=0.12, segments=3)
    # A blade down the outside of the forearm that juts past the elbow.
    robot.part(fore, "Trim").taper((1.94 * sign, 3.55, 0.05), 1.3, (0.1, 0.22), (0.1, 0.62), bevel=0.03)
    steel = robot.part(fore, "Steel")
    cables(steel, (1.3 * sign, 3.85, 0.22), (1.32 * sign, 2.95, 0.24), [(0, 0, 0), (0, 0, -0.12)], radius=0.05)
    robot.part(fore, "Glow").box((1.6 * sign, 3.4, -0.33), (0.07, 0.7, 0.03), bevel=0.01, segments=1)

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.9, 0), (1.62 * sign, 2.77, 0), 0.31, segments=12)
    armor = robot.part(hand, "Armor")
    armor.box((1.63 * sign, 2.42, 0), (0.62, 0.56, 0.7), bevel=0.14, segments=3)
    armor.box((1.36 * sign, 2.47, -0.22), (0.16, 0.3, 0.22), bevel=0.06)
    # A spear tip over the knuckles, on the striking face (downward at rest).
    robot.part(hand, "Steel").taper((1.64 * sign, 1.99, 0), 0.3, (0.2, 0.3), (0.58, 0.66), bevel=0.04)
    robot.part(hand, "Trim").box((1.63 * sign, 2.72, 0), (0.66, 0.08, 0.74), bevel=0.02)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.34)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.22, segments=10)
    armor = robot.part(thigh, "Armor")
    armor.taper((0.64 * sign, 2.36, -0.16), 1.05, (0.48, 0.32), (0.66, 0.38), bevel=0.06)
    armor.box((0.9 * sign, 2.45, 0.02), (0.08, 0.75, 0.56), bevel=0.03, rot=(0, 0, 6 * sign))
    robot.part(thigh, "Trim").box((0.64 * sign, 2.36, -0.34), (0.08, 0.7, 0.03), bevel=0.01, segments=1)
    steel = robot.part(thigh, "Steel")
    cables(steel, (0.52 * sign, 2.85, 0.2), (0.54 * sign, 1.88, 0.22), [(0, 0, 0), (0.22 * sign, 0, 0)], radius=0.05)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.36 * sign, 1.62, 0), (0.92 * sign, 1.62, 0), 0.27, segments=12)
    dark.cylinder((0.64 * sign, 1.5, 0.0), (0.64 * sign, 0.62, 0.0), 0.2, segments=10)
    armor = robot.part(shin, "Armor")
    armor.box((0.64 * sign, 1.7, -0.3), (0.44, 0.38, 0.2), bevel=0.08, rot=(-14, 0, 0))
    # A blade down the shin and a calf swept back, for a runner's leg.
    armor.taper((0.64 * sign, 1.04, -0.2), 0.95, (0.36, 0.22), (0.56, 0.3), bevel=0.05)
    armor.box((0.64 * sign, 1.18, 0.28), (0.42, 0.62, 0.22), bevel=0.06, rot=(18, 0, 0))
    robot.part(shin, "Trim").box((0.64 * sign, 1.04, -0.33), (0.07, 0.6, 0.03), bevel=0.01, segments=1)
    piston(dark, robot.part(shin, "Steel"), (0.64 * sign, 1.42, 0.42), (0.64 * sign, 0.68, 0.3), 0.07)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.25)
    dark.box((0.66 * sign, 0.09, -0.22), (0.62, 0.18, 1.42), bevel=0.05)
    armor = robot.part(foot, "Armor")
    armor.taper((0.66 * sign, 0.33, -0.3), 0.3, (0.6, 1.2), (0.46, 1.0), bevel=0.06)
    armor.box((0.65 * sign, 0.56, 0.02), (0.5, 0.3, 0.6), bevel=0.06)
    armor.box((0.66 * sign, 0.32, 0.55), (0.28, 0.26, 0.32), bevel=0.05, rot=(-22, 0, 0))
    robot.part(foot, "Trim").taper((0.66 * sign, 0.24, -0.98), 0.2, (0.42, 0.18), (0.3, 0.12), bevel=0.03)
