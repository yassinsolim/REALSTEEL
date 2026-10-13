"""RONIN: a premium body for RAZOR, the rushdown. A samurai in smooth, lacquered armor: a domed kabuto helmet with a
flared neck guard, turned-back side flaps and a gold crescent on its brow, a dark face mask with angry glowing eye slits,
a rounded cuirass with a glowing crest, a gold sash over a skirt of plates, three flared plates stacked on each shoulder,
bracers banded in gold, and slim legs in shin guards. The shells sit on a dark frame, so the gaps between them read as
panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z. It
keeps RAZOR's size and reach, so it plays and reads exactly like the free RAZOR.
"""

from greebles import place
from robotlib import Robot
from shells import BIG, DOME, FINE, MID, PLATE, RIM, SHELL
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.55, 0.05, 0.07), "material": "Metal", "tint": False},
    "Dark": {"color": (0.03, 0.03, 0.035), "material": "Metal", "tint": False},
    "Steel": {"color": (0.66, 0.68, 0.72), "material": "Metal", "tint": False},
    "Trim": {"color": (0.95, 0.72, 0.25), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.5, 0.18), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Ronin", smooth=True)
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
    robot.part("Pelvis", "Dark").pod((0, 3.04, 0.02), (1.24, 0.56, 0.86), SHELL, MID)
    # A gold sash, and a skirt of plates that flare out toward the legs: front, back and sides.
    robot.part("Pelvis", "Trim").pod((0, 3.24, 0.02), (1.5, 0.22, 1.02), PLATE, BIG)
    armor = robot.part("Pelvis", "Armor")
    armor.pod((0, 2.82, -0.48), (0.56, 0.64, 0.12), PLATE, MID, rot=(10, 0, 0))
    armor.pod((0, 2.86, 0.46), (0.56, 0.6, 0.12), PLATE, MID, rot=(-10, 0, 0))
    for sign in (1, -1):
        armor.pod((0.74 * sign, 2.84, -0.04), (0.12, 0.62, 0.66), PLATE, MID, rot=(0, 0, 10 * sign))


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.pod((0, 4.64, 0.04), (1.62, 1.6, 1.0), SHELL, MID, taper_x=(1.18, 0.62))
    dark.pod((0, 3.7, 0.02), (0.8, 0.7, 0.74), SHELL, MID)
    armor = robot.part("Chest", "Armor")
    # Lames down the waist, a rounded cuirass with a gold crest that glows at its heart, and a collar.
    for index, y in enumerate((3.6, 3.82, 4.04)):
        armor.pod((0, y, -0.22), (0.7 + 0.1 * index, 0.2, 0.5), PLATE, MID)
    armor.pod((0, 4.72, 0.04), (1.84, 1.36, 1.1), DOME, BIG, taper_x=(1.08, 0.7), taper_z=(1.0, 0.86))
    robot.part("Chest", "Trim").pod((0, 4.86, -0.6), (0.38, 0.38, 0.06), DOME, MID)
    robot.part("Chest", "Glow").pod((0, 4.86, -0.63), (0.16, 0.16, 0.04), DOME, FINE)
    armor.pod((0, 5.42, 0.12), (1.06, 0.28, 0.8), PLATE, MID)
    armor.pod((0, 4.76, 0.62), (1.3, 1.1, 0.3), PLATE, MID, taper_x=(1.0, 0.8))


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.36, 0.05), (0, 5.62, 0.05), 0.22, segments=12)
    armor = robot.part("Head", "Armor")
    trim = robot.part("Head", "Trim")
    # A domed helmet bowl over a two-tier neck guard that flares around the back and sides, with turned-back side flaps.
    armor.pod((0, 6.04, 0.12), (0.76, 0.56, 0.84), DOME, BIG)
    armor.pod((0, 5.86, 0.2), (1.06, 0.2, 0.92), PLATE, BIG, taper_x=(0.8, 1.0), taper_z=(0.82, 1.0))
    armor.pod((0, 5.7, 0.26), (1.16, 0.16, 0.86), PLATE, BIG, taper_x=(0.86, 1.0), taper_z=(0.86, 1.0))
    trim.pod((0, 5.62, 0.26), (1.16, 0.04, 0.86), PLATE, RIM)
    armor.pod((0, 6.08, -0.3), (0.72, 0.08, 0.3), PLATE, FINE, rot=(-10, 0, 0))
    for sign in (1, -1):
        armor.pod((0.5 * sign, 5.92, -0.14), (0.08, 0.3, 0.26), PLATE, FINE, rot=(0, -30 * sign, 0))
        # The gold crescent: a horn sweeping up and out on each side of a disc.
        trim.taper((0.2 * sign, 6.38, -0.36), 0.44, (0.08, 0.06), (0.04, 0.04), bevel=0.015, segments=1,
                   rot=(0, 0, -30 * sign))
    trim.pod((0, 6.16, -0.4), (0.14, 0.14, 0.04), DOME, FINE)
    # A dark face mask with angry glowing eye slits, and a guard over the mouth.
    dark.pod((0, 5.82, -0.3), (0.56, 0.42, 0.18), SHELL, MID)
    armor.pod((0, 5.68, -0.36), (0.5, 0.2, 0.16), PLATE, FINE, taper_x=(1.0, 0.8))
    glow = robot.part("Head", "Glow")
    for sign in (1, -1):
        glow.pod((0.13 * sign, 5.9, -0.39), (0.18, 0.05, 0.04), PLATE, FINE, rot=(0, 0, 12 * sign))


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.36)
    dark.cylinder((1.5 * sign, 4.85, 0), (1.53 * sign, 4.1, 0), 0.22, segments=12)
    armor = robot.part(upper, "Armor")
    # Three plates stacked on the shoulder, each flaring further out, the lowest edged in gold; a sleeve under them.
    for center, size, angle in (
        ((1.68, 5.36, 0.0), (0.86, 0.36, 1.0), -20),
        ((1.78, 5.08, 0.0), (0.84, 0.34, 1.02), -26),
        ((1.86, 4.8, 0.0), (0.8, 0.32, 1.04), -32),
    ):
        armor.pod((center[0] * sign, center[1], center[2]), size, PLATE, MID, rot=(0, 0, angle * sign))
    lowest, tilt = (1.86 * sign, 4.8, 0.0), (0, 0, -32 * sign)
    robot.part(upper, "Trim").pod(place(lowest, tilt, (0, -0.15, 0)), (0.78, 0.04, 1.04), PLATE, RIM, rot=tilt)
    armor.pod((1.52 * sign, 4.46, 0.0), (0.48, 0.66, 0.48), SHELL, MID)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.3 * sign, 3.95, 0), (1.8 * sign, 3.95, 0), 0.26, segments=12)
    armor = robot.part(fore, "Armor")
    # A bracer banded in gold.
    armor.pod((1.6 * sign, 3.36, 0.0), (0.68, 1.04, 0.72), PLATE, BIG, taper_x=(0.86, 1.0), taper_z=(0.86, 1.0))
    trim = robot.part(fore, "Trim")
    trim.pod((1.6 * sign, 3.7, 0.0), (0.66, 0.05, 0.7), PLATE, RIM)
    trim.pod((1.6 * sign, 3.02, 0.0), (0.7, 0.05, 0.74), PLATE, RIM)

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.9, 0), (1.62 * sign, 2.77, 0), 0.3, segments=12)
    armor = robot.part(hand, "Armor")
    # A quick, compact fist with a thumb and a steel plate over the knuckles.
    armor.pod((1.63 * sign, 2.4, 0.0), (0.66, 0.68, 0.74), PLATE, MID)
    armor.pod((1.35 * sign, 2.45, -0.22), (0.16, 0.3, 0.22), SHELL, FINE)
    robot.part(hand, "Steel").pod((1.64 * sign, 1.99, 0.0), (0.54, 0.12, 0.66), SHELL, FINE)
    robot.part(hand, "Trim").pod((1.63 * sign, 2.74, 0.0), (0.7, 0.07, 0.78), PLATE, RIM)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.34)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.2, segments=12)
    armor = robot.part(thigh, "Armor")
    armor.pod((0.64 * sign, 2.38, -0.12), (0.62, 1.0, 0.46), PLATE, BIG, taper_x=(1.08, 0.86))
    armor.pod((0.9 * sign, 2.45, 0.02), (0.08, 0.72, 0.54), PLATE, MID, rot=(0, 0, 6 * sign))

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.38 * sign, 1.62, 0), (0.9 * sign, 1.62, 0), 0.25, segments=12)
    dark.cylinder((0.64 * sign, 1.5, 0.0), (0.64 * sign, 0.62, 0.0), 0.19, segments=12)
    armor = robot.part(shin, "Armor")
    # A domed knee, a shin guard with a gold line down it, and a calf plate.
    armor.pod((0.64 * sign, 1.7, -0.3), (0.44, 0.38, 0.22), DOME, MID, rot=(-12, 0, 0))
    armor.pod((0.64 * sign, 1.04, -0.18), (0.5, 0.94, 0.3), PLATE, BIG, taper_x=(1.06, 0.8))
    robot.part(shin, "Trim").pod((0.64 * sign, 1.04, -0.34), (0.06, 0.7, 0.04), PLATE, FINE)
    armor.pod((0.64 * sign, 1.16, 0.24), (0.38, 0.58, 0.22), SHELL, MID, rot=(14, 0, 0))

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.24)
    dark.pod((0.66 * sign, 0.09, -0.2), (0.6, 0.18, 1.36), PLATE, MID)
    armor = robot.part(foot, "Armor")
    armor.pod((0.66 * sign, 0.32, -0.28), (0.54, 0.3, 1.12), PLATE, BIG)
    armor.pod((0.65 * sign, 0.54, 0.02), (0.48, 0.28, 0.56), SHELL, MID)
    robot.part(foot, "Trim").pod((0.66 * sign, 0.28, -0.86), (0.4, 0.16, 0.14), PLATE, FINE)
