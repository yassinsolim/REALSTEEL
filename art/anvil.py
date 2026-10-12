"""ANVIL: the all-rounder, a classic boxer. Rounded headgear with cheek guards and a visor band, a chest with a ring
emblem, glove-like fists with cuffs, and a waistband like a fighter's trunks. Pistons behind its thighs and calves, cable
runs at the waist. The armor plates sit on a dark frame, so the gaps between them read as panel lines.

Built on the shared skeleton (skeleton.py) in Roblox axes and studs: standing, arms hanging, facing -z, feet on y = 0.
Each joint owns one mesh per material role (Armor, Dark, Steel, Trim, Glow); the game recolors Armor, Trim and Glow per
player.
"""

from greebles import cables, piston, rivets
from robotlib import Robot
from skeleton import SIDES, add_joints

ROLES = {
    # color is linear-ish sRGB 0-1; material is the Roblox Enum.Material used in game; tint parts take the team color.
    "Armor": {"color": (0.46, 0.5, 0.57), "material": "Metal", "tint": False},
    "Dark": {"color": (0.035, 0.04, 0.05), "material": "Metal", "tint": False},
    "Steel": {"color": (0.66, 0.68, 0.72), "material": "Metal", "tint": False},
    "Trim": {"color": (0.18, 0.5, 1.0), "material": "Metal", "tint": True},
    "Glow": {"color": (0.35, 0.85, 1.0), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Anvil", smooth=True)
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
    dark.box((0, 3.06, 0), (1.4, 0.48, 0.92), bevel=0.06)
    for sign in (1, -1):
        dark.cylinder((0.3 * sign, 3.0, 0), (0.95 * sign, 3.0, 0), 0.36, segments=12)
    # The waistband of a fighter's trunks, and the panels under it.
    robot.part("Pelvis", "Trim").box((0, 3.34, 0), (1.85, 0.22, 1.12), bevel=0.06, segments=3)
    armor = robot.part("Pelvis", "Armor")
    armor.taper((0, 2.9, -0.5), 0.6, (0.9, 0.14), (1.2, 0.16), bevel=0.05, segments=3)
    for sign in (1, -1):
        armor.box((1.0 * sign, 2.95, 0.0), (0.16, 0.66, 0.96), bevel=0.06, segments=3, rot=(0, 0, -6 * sign))
    armor.box((0, 2.98, 0.5), (1.1, 0.55, 0.14), bevel=0.05)
    robot.part("Pelvis", "Glow").box((0, 3.34, -0.57), (0.3, 0.08, 0.03), bevel=0.01, segments=1)


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.taper((0, 4.7, 0.02), 1.28, (1.4, 0.92), (2.25, 1.12), bevel=0.08)
    dark.cylinder((0, 3.42, 0), (0, 4.06, 0), 0.44, segments=12)
    dark.cylinder((0, 5.32, 0.03), (0, 5.52, 0.03), 0.32, segments=12)
    armor = robot.part("Chest", "Armor")
    for y in (3.62, 3.8, 3.98):
        armor.box((0, y, -0.02), (1.05, 0.12, 0.84), bevel=0.03)
    for sign in (1, -1):
        armor.box((0.55 * sign, 4.98, -0.56), (1.0, 0.74, 0.2), bevel=0.12, segments=3, rot=(-6, -12 * sign, 0))
        armor.box((1.08 * sign, 4.66, -0.02), (0.16, 0.95, 0.95), bevel=0.06, segments=3)
    armor.box((0, 5.3, 0.02), (2.5, 0.26, 1.15), bevel=0.08, segments=3)
    armor.box((0, 4.7, 0.6), (1.6, 1.0, 0.14), bevel=0.05)
    trim = robot.part("Chest", "Trim")
    trim.box((0, 4.7, 0.69), (0.12, 0.9, 0.06), bevel=0.02)
    # The ring emblem.
    steel = robot.part("Chest", "Steel")
    steel.cylinder((0, 4.3, -0.45), (0, 4.3, -0.52), 0.25, segments=16)
    trim.cylinder((0, 4.3, -0.5), (0, 4.3, -0.55), 0.19, segments=16)
    robot.part("Chest", "Glow").cylinder((0, 4.3, -0.55), (0, 4.3, -0.57), 0.1, segments=16)
    rivets(steel, (-1.0, 5.42, -0.55), (-0.4, 5.42, -0.55), 3, (0, 0, -1))
    rivets(steel, (0.4, 5.42, -0.55), (1.0, 5.42, -0.55), 3, (0, 0, -1))
    cables(steel, (0.3, 3.5, -0.32), (0.34, 4.1, -0.36), [(0, 0, 0), (-0.6, 0, 0)], radius=0.045)


def head(robot):
    robot.part("Head", "Dark").cylinder((0, 5.38, 0.05), (0, 5.66, 0.05), 0.24, segments=10)
    armor = robot.part("Head", "Armor")
    # Rounded headgear: cheek guards, a brow, a chin guard and a strap over the top.
    armor.box((0, 5.92, 0.06), (0.82, 0.72, 0.86), bevel=0.26, segments=3)
    armor.box((0, 6.08, -0.33), (0.7, 0.12, 0.2), bevel=0.04, rot=(-10, 0, 0))
    armor.box((0, 5.58, -0.32), (0.5, 0.16, 0.2), bevel=0.05)
    for sign in (1, -1):
        armor.box((0.4 * sign, 5.8, -0.18), (0.14, 0.46, 0.42), bevel=0.07, segments=3, rot=(0, -10 * sign, 0))
        robot.part("Head", "Steel").cylinder((0.42 * sign, 5.95, 0.12), (0.5 * sign, 5.95, 0.12), 0.12, segments=10)
    robot.part("Head", "Dark").box((0, 5.82, -0.34), (0.6, 0.38, 0.12), bevel=0.04)
    robot.part("Head", "Glow").box((0, 5.88, -0.41), (0.5, 0.08, 0.03), bevel=0.01, segments=1)
    robot.part("Head", "Trim").box((0, 6.28, 0.06), (0.18, 0.06, 0.78), bevel=0.02)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.4)
    dark.cylinder((1.5 * sign, 4.85, 0), (1.53 * sign, 4.12, 0), 0.28, segments=12)
    armor = robot.part(upper, "Armor")
    # A domed shoulder over a trimmed band, and a sleeve on the upper arm.
    armor.sphere((1.62 * sign, 5.22, 0), 0.5, scale=(1.0, 0.75, 1.0))
    robot.part(upper, "Trim").box((1.62 * sign, 4.9, 0), (0.86, 0.07, 0.86), bevel=0.02, rot=(0, 0, -8 * sign))
    armor.box((1.52 * sign, 4.5, 0), (0.6, 0.66, 0.66), bevel=0.14, segments=3)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.24 * sign, 3.95, 0), (1.86 * sign, 3.95, 0), 0.32, segments=12)
    armor = robot.part(fore, "Armor")
    armor.taper((1.6 * sign, 3.36, 0), 1.0, (0.96, 0.98), (0.78, 0.82), bevel=0.14, segments=3)
    rivets(robot.part(fore, "Steel"), (1.6 * sign, 3.7, -0.47), (1.6 * sign, 3.05, -0.52), 3, (0, 0, -1))

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.92, 0), (1.62 * sign, 2.78, 0), 0.42, segments=12)
    # A glove: a rounded fist with a cuff and a steel plate over the knuckles.
    robot.part(hand, "Trim").box((1.62 * sign, 2.82, 0), (1.0, 0.16, 1.04), bevel=0.06, segments=3)
    armor = robot.part(hand, "Armor")
    armor.box((1.64 * sign, 2.36, 0), (1.0, 0.84, 1.06), bevel=0.32, segments=3)
    armor.box((1.12 * sign, 2.44, -0.34), (0.26, 0.44, 0.32), bevel=0.1, segments=3)
    robot.part(hand, "Steel").box((1.66 * sign, 1.95, 0), (0.74, 0.1, 0.86), bevel=0.05)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.4)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.3, segments=10)
    armor = robot.part(thigh, "Armor")
    armor.taper((0.64 * sign, 2.32, -0.02), 1.2, (0.84, 0.88), (0.98, 1.0), bevel=0.1, segments=3)
    robot.part(thigh, "Trim").box((1.11 * sign, 2.4, 0.0), (0.03, 0.8, 0.12), bevel=0.01, segments=1)
    piston(dark, robot.part(thigh, "Steel"), (0.64 * sign, 2.85, 0.5), (0.64 * sign, 1.88, 0.54), 0.08)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.26 * sign, 1.62, 0), (1.02 * sign, 1.62, 0), 0.33, segments=12)
    armor = robot.part(shin, "Armor")
    armor.box((0.64 * sign, 1.66, -0.42), (0.66, 0.56, 0.26), bevel=0.12, segments=3, rot=(-10, 0, 0))
    armor.taper((0.64 * sign, 1.02, 0.0), 1.0, (0.84, 0.88), (0.76, 0.8), bevel=0.09, segments=3)
    robot.part(shin, "Trim").box((0.64 * sign, 1.02, -0.45), (0.1, 0.6, 0.03), bevel=0.01, segments=1)
    piston(dark, robot.part(shin, "Steel"), (0.64 * sign, 1.48, 0.46), (0.64 * sign, 0.74, 0.48), 0.075)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.3)
    dark.box((0.66 * sign, 0.1, -0.16), (1.0, 0.2, 1.56), bevel=0.06)
    armor = robot.part(foot, "Armor")
    armor.box((0.66 * sign, 0.4, -0.22), (0.9, 0.44, 1.3), bevel=0.14, segments=3)
    armor.box((0.65 * sign, 0.66, 0.0), (0.84, 0.4, 0.84), bevel=0.1, segments=3)
    robot.part(foot, "Trim").box((0.66 * sign, 0.35, -0.84), (0.8, 0.24, 0.2), bevel=0.06)
