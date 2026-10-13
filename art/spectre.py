"""SPECTRE: a premium body for LANCE, the long-reach poker. A sleek stealth fencer in smooth, pearl-like armor: an egg-shaped
head tilted back with a single vertical glowing slit and a swept fin, a hard V torso narrowing to a slim waist around a
glowing core, swept shoulder shells with fins, dorsal fins on the back, slim limbs, blades down the forearms, fists that
end in smooth lance tips, and pointed runner's feet with heel spurs. The shells sit on a dark frame, so the gaps between
them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z. It
keeps LANCE's size and reach, so it plays and reads exactly like the free LANCE.
"""

from greebles import cables
from robotlib import Robot
from shells import BIG, DOME, FINE, MID, PLATE, RIM, SHELL
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.88, 0.9, 0.94), "material": "Metal", "tint": False},
    "Dark": {"color": (0.03, 0.035, 0.045), "material": "Metal", "tint": False},
    "Steel": {"color": (0.66, 0.68, 0.72), "material": "Metal", "tint": False},
    "Trim": {"color": (0.08, 0.72, 0.95), "material": "Metal", "tint": True},
    "Glow": {"color": (0.3, 0.95, 1.0), "material": "Neon", "tint": True},
}

# An egg: rounder at the ends than a shell.
EGG = (0.62, 0.5)


def build():
    robot = Robot("Spectre", smooth=True)
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
    robot.part("Pelvis", "Dark").pod((0, 3.04, 0.02), (1.2, 0.56, 0.84), SHELL, MID)
    armor = robot.part("Pelvis", "Armor")
    # A narrow hip belt, a plate in front, and a swept fin over each hip.
    armor.pod((0, 3.16, 0.02), (1.46, 0.3, 1.0), PLATE, BIG, taper_x=(1.0, 0.9))
    armor.pod((0, 2.9, -0.42), (0.5, 0.44, 0.14), PLATE, MID, taper_x=(1.0, 0.6))
    for sign in (1, -1):
        armor.pod((0.86 * sign, 2.92, 0.08), (0.16, 0.6, 0.7), PLATE, MID, rot=(0, 0, 10 * sign))
    robot.part("Pelvis", "Trim").pod((0, 3.3, 0.02), (1.4, 0.04, 0.96), PLATE, RIM)


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.pod((0, 4.66, 0.06), (1.6, 1.66, 1.0), SHELL, MID, taper_x=(1.25, 0.55))
    dark.pod((0, 3.7, 0.02), (0.74, 0.7, 0.7), SHELL, MID)
    armor = robot.part("Chest", "Armor")
    trim = robot.part("Chest", "Trim")
    for index, y in enumerate((3.6, 3.82, 4.04)):
        armor.pod((0, y, -0.24), (0.56 + 0.06 * index, 0.17, 0.34), PLATE, MID)
    # A hard V torso, swept plates over the chest outlined in trim, and a glowing core between them.
    armor.pod((0, 4.82, 0.06), (2.0, 1.2, 1.06), PLATE, BIG, taper_x=(1.15, 0.5), taper_z=(1.0, 0.85))
    for sign in (1, -1):
        armor.pod((0.42 * sign, 4.98, -0.44), (0.76, 0.66, 0.26), PLATE, MID, rot=(-8, -16 * sign, 14 * sign))
        trim.taper((0.34 * sign, 4.58, -0.5), 0.05, (0.8, 0.08), (0.8, 0.08), bevel=0.02, segments=1,
                   rot=(0, -12 * sign, 30 * sign))
    robot.part("Chest", "Steel").pod((0, 4.62, -0.5), (0.34, 0.34, 0.12), DOME, MID)
    robot.part("Chest", "Glow").pod((0, 4.62, -0.55), (0.22, 0.22, 0.05), DOME, MID)
    armor.pod((0, 5.46, 0.18), (1.0, 0.3, 0.74), PLATE, MID, taper_x=(0.85, 1.0))
    # Swept dorsal fins on the back, with a glowing line between them.
    for sign in (1, -1):
        armor.pod((0.28 * sign, 5.0, 0.6), (0.1, 0.92, 0.5), PLATE, MID, rot=(-20, 0, 8 * sign))
    robot.part("Chest", "Glow").pod((0, 4.9, 0.56), (0.05, 0.7, 0.04), PLATE, FINE)


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.36, 0.05), (0, 5.62, 0.05), 0.2, segments=12)
    armor = robot.part("Head", "Armor")
    # An egg-shaped head tilted back, a dark face with a single vertical glowing slit, cheek fins and a swept fin on top.
    armor.pod((0, 5.98, 0.12), (0.6, 0.86, 0.8), EGG, BIG, taper_z=(0.8, 1.0), rot=(10, 0, 0))
    dark.pod((0, 5.94, -0.22), (0.44, 0.52, 0.16), SHELL, MID, rot=(10, 0, 0))
    robot.part("Head", "Glow").pod((0, 5.98, -0.3), (0.06, 0.36, 0.04), PLATE, FINE, rot=(10, 0, 0))
    for sign in (1, -1):
        armor.pod((0.33 * sign, 5.86, 0.02), (0.06, 0.4, 0.5), PLATE, FINE, rot=(0, -10 * sign, 0))
    robot.part("Head", "Trim").taper((0, 6.4, 0.26), 0.2, (0.08, 0.7), (0.04, 0.4), shift=(0, 0.14), bevel=0.02,
                                     segments=1)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.34)
    dark.cylinder((1.5 * sign, 4.85, 0), (1.53 * sign, 4.1, 0), 0.22, segments=12)
    armor = robot.part(upper, "Armor")
    # A swept shoulder shell with a fin over it, and a slim sleeve.
    armor.pod((1.62 * sign, 5.28, 0.06), (0.86, 0.5, 1.0), PLATE, BIG, taper_z=(0.86, 1.0), rot=(0, 0, -14 * sign))
    robot.part(upper, "Trim").taper((1.74 * sign, 5.58, 0.3), 0.5, (0.08, 0.7), (0.06, 0.3), shift=(0, 0.2), bevel=0.02,
                                    segments=1, rot=(0, 0, -14 * sign))
    armor.pod((1.52 * sign, 4.48, 0.0), (0.46, 0.68, 0.46), SHELL, MID)
    cables(robot.part(upper, "Steel"), (1.4 * sign, 4.88, 0.2), (1.44 * sign, 4.1, 0.22), [(0, 0, 0)], radius=0.05)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.3 * sign, 3.95, 0), (1.8 * sign, 3.95, 0), 0.26, segments=12)
    armor = robot.part(fore, "Armor")
    # A slim forearm with a blade down its outside that juts past the elbow.
    armor.pod((1.6 * sign, 3.36, 0.02), (0.66, 1.08, 0.68), PLATE, BIG, taper_x=(0.86, 1.0), taper_z=(0.86, 1.0))
    robot.part(fore, "Trim").taper((1.96 * sign, 3.52, 0.05), 1.3, (0.08, 0.2), (0.08, 0.62), bevel=0.03)
    robot.part(fore, "Glow").pod((1.6 * sign, 3.4, -0.34), (0.06, 0.7, 0.03), PLATE, FINE)

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.9, 0), (1.62 * sign, 2.77, 0), 0.31, segments=12)
    armor = robot.part(hand, "Armor")
    # A slim fist with a thumb, ending in a smooth lance tip over the knuckles (downward at rest).
    armor.pod((1.63 * sign, 2.42, 0.0), (0.64, 0.58, 0.72), PLATE, MID)
    armor.pod((1.34 * sign, 2.47, -0.22), (0.16, 0.3, 0.22), SHELL, FINE)
    robot.part(hand, "Steel").pod((1.64 * sign, 2.0, 0.0), (0.6, 0.32, 0.68), DOME, MID, taper_x=(1.0, 0.3),
                                  taper_z=(1.0, 0.4))
    robot.part(hand, "Trim").pod((1.63 * sign, 2.72, 0.0), (0.68, 0.07, 0.76), PLATE, RIM)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.34)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.22, segments=12)
    armor = robot.part(thigh, "Armor")
    armor.pod((0.64 * sign, 2.36, -0.12), (0.62, 1.06, 0.48), PLATE, BIG, taper_x=(1.1, 0.8))
    armor.pod((0.92 * sign, 2.45, 0.02), (0.08, 0.76, 0.56), PLATE, MID, rot=(0, 0, 6 * sign))
    robot.part(thigh, "Trim").pod((0.64 * sign, 2.36, -0.37), (0.06, 0.72, 0.03), PLATE, FINE)
    cables(robot.part(thigh, "Steel"), (0.52 * sign, 2.85, 0.2), (0.54 * sign, 1.88, 0.22), [(0, 0, 0)], radius=0.05)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.36 * sign, 1.62, 0), (0.92 * sign, 1.62, 0), 0.27, segments=12)
    dark.cylinder((0.64 * sign, 1.5, 0.0), (0.64 * sign, 0.62, 0.0), 0.2, segments=12)
    armor = robot.part(shin, "Armor")
    # A domed knee, a blade down the shin and a calf swept back, for a runner's leg.
    armor.pod((0.64 * sign, 1.7, -0.3), (0.46, 0.4, 0.24), DOME, MID, rot=(-14, 0, 0))
    armor.pod((0.64 * sign, 1.04, -0.2), (0.5, 0.96, 0.32), PLATE, BIG, taper_x=(1.1, 0.7))
    armor.pod((0.64 * sign, 1.18, 0.28), (0.42, 0.64, 0.24), SHELL, MID, rot=(18, 0, 0))
    robot.part(shin, "Glow").pod((0.64 * sign, 1.04, -0.37), (0.05, 0.6, 0.03), PLATE, FINE)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.25)
    dark.pod((0.66 * sign, 0.09, -0.22), (0.62, 0.18, 1.42), PLATE, MID)
    armor = robot.part(foot, "Armor")
    # A pointed runner's foot with a heel spur.
    armor.pod((0.66 * sign, 0.33, -0.3), (0.56, 0.32, 1.2), PLATE, BIG, taper_x=(0.82, 1.0))
    armor.pod((0.65 * sign, 0.56, 0.02), (0.5, 0.3, 0.6), SHELL, MID)
    armor.pod((0.66 * sign, 0.32, 0.55), (0.28, 0.26, 0.32), PLATE, FINE, rot=(-22, 0, 0))
    robot.part(foot, "Trim").pod((0.66 * sign, 0.24, -0.98), (0.36, 0.18, 0.2), PLATE, FINE)
