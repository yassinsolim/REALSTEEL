"""MONARCH: a premium body for MAUL, the heavy hitter. A champion heavyweight in smooth, rounded armor with crisp edges and
a V-shaped build: huge swept pauldrons over sloping traps, a chest that narrows hard to a plated waist, sculpted plates
outlined in a gold V around a glowing core, a low helmet sunk between the traps with an angry brow over V-slit eyes and a
jutting jaw, a title belt, massive flared gauntlets with fin guards over huge fists, and thick legs in heavy boots. The
shells sit on a dark frame, so the gaps between them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z. It
keeps MAUL's size and reach, so it plays and reads exactly like the free MAUL.
"""

from greebles import piston, rivets
from robotlib import Robot
from shells import BIG, DOME, FINE, MID, PLATE, RIM, SHELL
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.2, 0.07, 0.36), "material": "Metal", "tint": False},
    "Dark": {"color": (0.025, 0.025, 0.03), "material": "Metal", "tint": False},
    "Steel": {"color": (0.62, 0.64, 0.68), "material": "Metal", "tint": False},
    "Trim": {"color": (0.95, 0.68, 0.18), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.74, 0.28), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Monarch", smooth=True)
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
    dark.pod((0, 3.02, 0.02), (1.46, 0.62, 1.0), SHELL, MID)
    armor = robot.part("Pelvis", "Armor")
    # The title belt, with a gold shield plate and a gem on the front, and a plate over each hip.
    armor.pod((0, 3.14, 0.02), (1.76, 0.38, 1.16), PLATE, BIG, taper_x=(1.0, 0.95), taper_z=(1.0, 0.95))
    for sign in (1, -1):
        armor.pod((0.96 * sign, 2.84, -0.04), (0.24, 0.68, 0.94), PLATE, MID, rot=(0, 0, 9 * sign))
    trim = robot.part("Pelvis", "Trim")
    trim.pod((0, 3.12, -0.6), (0.78, 0.5, 0.12), PLATE, MID, taper_x=(1.0, 0.62))
    trim.pod((0, 3.32, 0.02), (1.7, 0.05, 1.12), PLATE, RIM)
    robot.part("Pelvis", "Glow").pod((0, 3.14, -0.67), (0.2, 0.2, 0.05), PLATE, FINE, rot=(0, 0, 45))


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.pod((0, 4.62, 0.06), (1.7, 1.7, 1.1), SHELL, MID, taper_x=(1.25, 0.6))
    dark.pod((0, 3.72, 0.02), (0.96, 0.7, 0.82), SHELL, MID)
    armor = robot.part("Chest", "Armor")
    trim = robot.part("Chest", "Trim")
    glow = robot.part("Chest", "Glow")
    steel = robot.part("Chest", "Steel")
    # A plated waist, narrow under the chest.
    for index, y in enumerate((3.55, 3.78, 4.01)):
        armor.pod((0, y, -0.28), (0.78 + index * 0.08, 0.19, 0.42), PLATE, MID)
    # The chest narrows hard from the shoulders to the waist. Two sculpted plates sweep up toward the shoulders, outlined
    # below in a gold V, with the core glowing between them.
    armor.pod((0, 4.86, 0.1), (2.2, 1.1, 1.24), PLATE, BIG, taper_x=(1.12, 0.62), taper_z=(1.0, 0.86))
    for sign in (1, -1):
        armor.pod((0.55 * sign, 4.92, -0.5), (1.02, 0.86, 0.38), PLATE, MID, rot=(-8, -14 * sign, 10 * sign))
        trim.taper((0.5 * sign, 4.47, -0.66), 0.06, (1.0, 0.1), (1.0, 0.1), bevel=0.02, segments=1,
                   rot=(0, -10 * sign, 18 * sign))
        # Traps slope from the collar down to the pauldrons, so the helmet sits low.
        armor.pod((0.74 * sign, 5.44, 0.12), (0.92, 0.38, 1.0), PLATE, MID, rot=(0, 0, -22 * sign))
    steel.pod((0, 4.62, -0.64), (0.44, 0.44, 0.14), DOME, MID)
    glow.pod((0, 4.62, -0.7), (0.28, 0.28, 0.06), DOME, MID)
    armor.pod((0, 5.5, 0.24), (1.1, 0.4, 0.84), PLATE, MID)
    trim.pod((0, 5.69, 0.24), (0.96, 0.04, 0.74), PLATE, RIM)
    # A power pack on the back, glowing vents between two exhaust stacks.
    armor.pod((0, 4.8, 0.76), (1.4, 1.2, 0.5), PLATE, MID, taper_x=(1.0, 0.8))
    for sign in (1, -1):
        steel.cylinder((0.44 * sign, 4.32, 1.0), (0.44 * sign, 5.26, 1.0), 0.1, segments=12)
        glow.pod((0.16 * sign, 4.78, 1.02), (0.07, 0.82, 0.04), SHELL, FINE)
        rivets(steel, (1.16 * sign, 5.08, -0.3), (1.16 * sign, 5.08, 0.44), 3, (sign, 0, 0))


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.36, 0.05), (0, 5.62, 0.05), 0.26, segments=12)
    armor = robot.part("Head", "Armor")
    trim = robot.part("Head", "Trim")
    glow = robot.part("Head", "Glow")
    # A helmet under an angry V brow, with V-slit eyes, cheek guards and a jutting jaw around a dark face, and a swept
    # gold crest.
    armor.pod((0, 5.96, 0.1), (0.72, 0.72, 0.84), (0.5, 0.4), BIG, taper_x=(0.9, 1.0))
    for sign in (1, -1):
        armor.taper((0.17 * sign, 6.1, -0.34), 0.14, (0.4, 0.26), (0.36, 0.16), bevel=0.04, segments=2,
                    rot=(-20, 0, 14 * sign))
        glow.pod((0.15 * sign, 5.97, -0.42), (0.26, 0.06, 0.04), PLATE, FINE, rot=(0, 0, 14 * sign))
        armor.pod((0.34 * sign, 5.8, -0.12), (0.17, 0.46, 0.56), PLATE, FINE, rot=(0, -12 * sign, 0))
    dark.pod((0, 5.85, -0.29), (0.56, 0.44, 0.22), SHELL, MID)
    armor.pod((0, 5.66, -0.36), (0.46, 0.22, 0.28), PLATE, FINE, taper_x=(1.0, 0.8))
    trim.pod((0, 5.6, -0.5), (0.3, 0.05, 0.03), PLATE, FINE)
    trim.taper((0, 6.33, 0.14), 0.2, (0.1, 0.7), (0.05, 0.44), shift=(0, 0.12), bevel=0.02, segments=1)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.42)
    dark.cylinder((1.5 * sign, 4.85, 0.05), (1.53 * sign, 4.12, 0.05), 0.3, segments=12)
    armor = robot.part(upper, "Armor")
    trim = robot.part(upper, "Trim")
    # A huge domed pauldron crowned with a gold ridge and rimmed in gold, layered over a shoulder plate, and a bicep
    # shell.
    tilt = (0, 0, -18 * sign)
    armor.pod((1.78 * sign, 5.42, 0.02), (1.34, 0.9, 1.42), DOME, BIG, taper_z=(0.86, 1.0), rot=tilt)
    trim.pod((1.8 * sign, 5.08, 0.02), (1.28, 0.06, 1.36), PLATE, RIM, rot=tilt)
    trim.pod((1.76 * sign, 5.86, 0.02), (0.14, 0.12, 1.12), PLATE, FINE, rot=tilt)
    armor.pod((1.98 * sign, 4.96, 0.0), (0.86, 0.42, 1.16), PLATE, MID, rot=(0, 0, -30 * sign))
    robot.part(upper, "Glow").pod((1.7 * sign, 5.36, -0.7), (0.44, 0.07, 0.04), PLATE, FINE, rot=tilt)
    armor.pod((1.56 * sign, 4.46, 0.06), (0.58, 0.66, 0.56), SHELL, MID)
    piston(dark, robot.part(upper, "Steel"), (1.5 * sign, 4.95, 0.44), (1.55 * sign, 3.96, 0.5), 0.1)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.2 * sign, 3.95, 0), (1.9 * sign, 3.95, 0), 0.34, segments=12)
    armor = robot.part(fore, "Armor")
    # A massive gauntlet that flares out toward the fist, a fin guard down its outer side and a gold band at the wrist.
    armor.pod((1.6 * sign, 3.34, 0.04), (1.08, 1.12, 1.06), PLATE, BIG, taper_x=(0.84, 1.1), taper_z=(0.84, 1.1))
    armor.taper((2.17 * sign, 3.3, 0.04), 0.92, (0.14, 0.84), (0.1, 0.52), bevel=0.04, segments=2, rot=(0, 0, 8 * sign))
    robot.part(fore, "Trim").pod((1.6 * sign, 2.88, 0.04), (1.14, 0.08, 1.12), PLATE, RIM)
    robot.part(fore, "Glow").pod((1.6 * sign, 3.42, -0.56), (0.07, 0.58, 0.04), PLATE, FINE)

    hand = "Hand" + side
    dark = robot.part(hand, "Dark")
    dark.cylinder((1.62 * sign, 2.92, 0), (1.62 * sign, 2.74, 0), 0.44, segments=12)
    armor = robot.part(hand, "Armor")
    # A huge fist with a thumb, and four steel knuckles across its striking face.
    armor.pod((1.64 * sign, 2.35, 0.0), (1.14, 0.86, 1.1), PLATE, BIG)
    armor.pod((1.09 * sign, 2.42, -0.3), (0.26, 0.46, 0.34), SHELL, FINE, rot=(0, 0, 10 * sign))
    steel = robot.part(hand, "Steel")
    for dz in (-0.39, -0.13, 0.13, 0.39):
        steel.pod((1.64 * sign, 1.95, dz), (1.0, 0.18, 0.21), SHELL, FINE)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.4)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.32, segments=12)
    armor = robot.part(thigh, "Armor")
    # A thick thigh with a plate layered over its front and a gold stripe down its outer side.
    armor.pod((0.66 * sign, 2.32, 0.0), (1.0, 1.16, 0.96), PLATE, BIG, taper_x=(1.08, 0.84), taper_z=(1.04, 0.88))
    armor.pod((0.66 * sign, 2.4, -0.5), (0.8, 0.86, 0.2), PLATE, MID, rot=(-8, 0, 0))
    robot.part(thigh, "Trim").taper((1.16 * sign, 2.36, -0.02), 0.8, (0.05, 0.36), (0.05, 0.56), bevel=0.02,
                                    segments=1)
    piston(dark, robot.part(thigh, "Steel"), (0.64 * sign, 2.85, 0.5), (0.64 * sign, 1.88, 0.54), 0.09)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.22 * sign, 1.62, 0), (1.06 * sign, 1.62, 0), 0.34, segments=12)
    armor = robot.part(shin, "Armor")
    # A domed knee cap with a light, and a shin that flares into the boot with a ridge down its front.
    armor.pod((0.64 * sign, 1.66, -0.44), (0.62, 0.48, 0.34), DOME, MID, rot=(-10, 0, 0))
    robot.part(shin, "Glow").pod((0.64 * sign, 1.66, -0.62), (0.26, 0.05, 0.04), PLATE, FINE, rot=(-10, 0, 0))
    armor.pod((0.64 * sign, 0.98, 0.02), (0.94, 1.02, 0.96), PLATE, BIG, taper_x=(0.86, 1.1), taper_z=(0.86, 1.1))
    armor.taper((0.64 * sign, 1.04, -0.5), 0.8, (0.3, 0.12), (0.2, 0.1), bevel=0.04, segments=2)
    robot.part(shin, "Trim").pod((0.64 * sign, 0.58, 0.02), (1.02, 0.06, 1.04), PLATE, RIM)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.3)
    dark.pod((0.66 * sign, 0.1, -0.16), (1.1, 0.2, 1.64), PLATE, MID)
    armor = robot.part(foot, "Armor")
    # A heavy boot with a gold toe cap.
    armor.pod((0.66 * sign, 0.36, -0.2), (1.04, 0.5, 1.44), PLATE, BIG)
    armor.pod((0.65 * sign, 0.62, 0.06), (0.88, 0.36, 0.86), SHELL, MID)
    robot.part(foot, "Trim").pod((0.66 * sign, 0.32, -0.86), (0.9, 0.28, 0.2), PLATE, FINE)
