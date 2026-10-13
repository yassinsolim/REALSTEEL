"""HAYMAKER: a premium body for ANVIL, the all-rounder. A retro prizefighter in smooth, rounded armor: a rounded helmet in a
padded headguard, round glowing eyes over a grilled mouth, a barrel chest with a big dial at its heart over a bellows
waist, trunks with a buckled waistband in the accent color, ball shoulders ringed in trim, huge padded gloves with laced
cuffs, and high-top boots. The shells sit on a dark frame, so the gaps between them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z. It
keeps ANVIL's size and reach, so it plays and reads exactly like the free ANVIL.
"""

from greebles import piston, rivets
from robotlib import Robot
from shells import BALL, BIG, DOME, FINE, MID, PLATE, RIM, SHELL
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.84, 0.79, 0.67), "material": "Metal", "tint": False},
    "Dark": {"color": (0.03, 0.03, 0.035), "material": "Metal", "tint": False},
    "Steel": {"color": (0.66, 0.68, 0.72), "material": "Metal", "tint": False},
    "Trim": {"color": (0.82, 0.1, 0.08), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.78, 0.36), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Haymaker", smooth=True)
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
    robot.part("Pelvis", "Dark").pod((0, 3.02, 0.02), (1.4, 0.6, 0.96), SHELL, MID)
    # Trunks that flare a little toward the legs, under a broad waistband with a buckle.
    armor = robot.part("Pelvis", "Armor")
    armor.pod((0, 2.96, 0.0), (1.66, 0.54, 1.1), SHELL, BIG, taper_x=(1.0, 1.08), taper_z=(1.0, 1.04))
    trim = robot.part("Pelvis", "Trim")
    trim.pod((0, 3.3, 0.02), (1.86, 0.3, 1.18), PLATE, BIG)
    robot.part("Pelvis", "Steel").pod((0, 3.3, -0.6), (0.44, 0.3, 0.08), PLATE, FINE)
    robot.part("Pelvis", "Glow").pod((0, 3.3, -0.64), (0.22, 0.09, 0.03), PLATE, FINE)


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.pod((0, 4.66, 0.04), (1.9, 1.6, 1.14), SHELL, MID, taper_x=(1.1, 0.8))
    # A bellows waist.
    for index, y in enumerate((3.5, 3.68, 3.86, 4.04)):
        dark.pod((0, y, 0.02), (0.92 + 0.04 * index, 0.13, 0.82), SHELL, MID)
    armor = robot.part("Chest", "Armor")
    trim = robot.part("Chest", "Trim")
    steel = robot.part("Chest", "Steel")
    glow = robot.part("Chest", "Glow")
    # A barrel chest under a broad yoke, and a collar.
    armor.pod((0, 4.76, 0.06), (2.1, 1.3, 1.24), DOME, BIG, taper_x=(1.04, 0.86))
    armor.pod((0, 5.36, 0.1), (2.3, 0.38, 1.14), PLATE, BIG)
    armor.pod((0, 5.56, 0.18), (1.0, 0.22, 0.72), SHELL, MID)
    trim.pod((0, 5.53, 0.1), (2.26, 0.05, 1.1), PLATE, RIM)
    # The dial at its heart: a steel bezel, a ring in the accent color and a glowing face.
    steel.pod((0, 4.68, -0.6), (0.66, 0.66, 0.14), DOME, MID)
    trim.pod((0, 4.68, -0.64), (0.54, 0.54, 0.06), DOME, MID)
    glow.pod((0, 4.68, -0.68), (0.34, 0.34, 0.04), DOME, MID)
    for sign in (1, -1):
        rivets(steel, (0.62 * sign, 5.16, -0.6), (0.92 * sign, 5.12, -0.5), 3, (0.3 * sign, 0, -1))
    # A rounded pack on the back with two vents.
    armor.pod((0, 4.8, 0.72), (1.36, 1.1, 0.4), PLATE, MID, taper_x=(1.0, 0.86))
    for sign in (1, -1):
        dark.pod((0.32 * sign, 4.8, 0.92), (0.2, 0.62, 0.06), PLATE, FINE)


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.36, 0.05), (0, 5.62, 0.05), 0.24, segments=12)
    armor = robot.part("Head", "Armor")
    trim = robot.part("Head", "Trim")
    # A rounded helmet in a padded headguard: a band, cheek pads and a strap over the top.
    armor.pod((0, 5.98, 0.08), (0.84, 0.8, 0.86), SHELL, BIG)
    trim.pod((0, 6.08, 0.1), (0.9, 0.16, 0.92), PLATE, RIM)
    trim.pod((0, 6.37, 0.08), (0.16, 0.1, 0.7), SHELL, FINE)
    for sign in (1, -1):
        trim.pod((0.42 * sign, 5.84, -0.1), (0.16, 0.44, 0.52), SHELL, FINE)
        robot.part("Head", "Steel").cylinder((0.44 * sign, 5.98, 0.16), (0.52 * sign, 5.98, 0.16), 0.11, segments=10)
    # The face: round glowing eyes over a grilled mouth.
    dark.pod((0, 5.88, -0.33), (0.6, 0.46, 0.14), SHELL, MID)
    glow = robot.part("Head", "Glow")
    for sign in (1, -1):
        glow.pod((0.15 * sign, 5.95, -0.41), (0.16, 0.16, 0.05), BALL, FINE)
    steel = robot.part("Head", "Steel")
    for y in (5.7, 5.76, 5.82):
        steel.pod((0, y, -0.4), (0.32, 0.03, 0.03), PLATE, FINE)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.4)
    dark.cylinder((1.5 * sign, 4.85, 0.02), (1.53 * sign, 4.12, 0.02), 0.28, segments=12)
    armor = robot.part(upper, "Armor")
    # A ball shoulder ringed in trim, and a rounded sleeve.
    armor.pod((1.62 * sign, 5.2, 0.0), (1.04, 0.88, 1.04), BALL, BIG)
    robot.part(upper, "Trim").pod((1.62 * sign, 4.98, 0.0), (1.06, 0.07, 1.06), PLATE, RIM)
    armor.pod((1.53 * sign, 4.46, 0.02), (0.6, 0.66, 0.62), SHELL, MID)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.24 * sign, 3.95, 0), (1.86 * sign, 3.95, 0), 0.32, segments=12)
    armor = robot.part(fore, "Armor")
    armor.pod((1.6 * sign, 3.38, 0.02), (0.86, 1.02, 0.88), SHELL, BIG, taper_x=(0.92, 1.04), taper_z=(0.92, 1.04))
    rivets(robot.part(fore, "Steel"), (1.6 * sign, 3.7, -0.46), (1.6 * sign, 3.06, -0.48), 3, (0, 0, -1))

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.92, 0), (1.62 * sign, 2.76, 0), 0.42, segments=12)
    armor = robot.part(hand, "Armor")
    # A huge padded glove, fuller at the knuckles, with a thumb and a laced cuff.
    armor.pod((1.64 * sign, 2.35, -0.02), (1.06, 0.92, 1.12), DOME, BIG, taper_x=(0.92, 1.04), taper_z=(0.92, 1.04))
    armor.pod((1.1 * sign, 2.44, -0.34), (0.28, 0.48, 0.34), SHELL, FINE, rot=(0, 0, 10 * sign))
    trim = robot.part(hand, "Trim")
    trim.pod((1.62 * sign, 2.82, 0.0), (0.98, 0.2, 1.02), PLATE, RIM)
    for y in (2.76, 2.88):
        robot.part(hand, "Steel").pod((1.62 * sign, y, -0.52), (0.3, 0.03, 0.04), PLATE, FINE)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.4)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.3, segments=12)
    armor = robot.part(thigh, "Armor")
    armor.pod((0.65 * sign, 2.3, 0.0), (0.92, 1.12, 0.94), SHELL, BIG, taper_x=(1.04, 0.88), taper_z=(1.04, 0.9))
    # A stripe down the side, like a fighter's trunks.
    robot.part(thigh, "Trim").pod((1.11 * sign, 2.42, 0.0), (0.05, 0.84, 0.3), PLATE, FINE)
    piston(dark, robot.part(thigh, "Steel"), (0.64 * sign, 2.85, 0.5), (0.64 * sign, 1.88, 0.54), 0.08)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.26 * sign, 1.62, 0), (1.02 * sign, 1.62, 0), 0.33, segments=12)
    armor = robot.part(shin, "Armor")
    armor.pod((0.64 * sign, 1.66, -0.42), (0.62, 0.5, 0.32), DOME, MID, rot=(-10, 0, 0))
    armor.pod((0.64 * sign, 1.04, 0.0), (0.84, 0.96, 0.88), SHELL, BIG, taper_x=(0.92, 1.04), taper_z=(0.92, 1.04))
    piston(dark, robot.part(shin, "Steel"), (0.64 * sign, 1.48, 0.46), (0.64 * sign, 0.78, 0.48), 0.075)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.3)
    dark.pod((0.66 * sign, 0.1, -0.16), (1.04, 0.2, 1.6), PLATE, MID)
    armor = robot.part(foot, "Armor")
    # High-top boots with a band at the top.
    armor.pod((0.66 * sign, 0.38, -0.18), (0.96, 0.5, 1.4), SHELL, BIG)
    armor.pod((0.65 * sign, 0.68, 0.04), (0.84, 0.4, 0.84), SHELL, MID)
    robot.part(foot, "Trim").pod((0.65 * sign, 0.86, 0.04), (0.86, 0.08, 0.86), PLATE, RIM)
