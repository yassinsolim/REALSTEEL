"""BASTION: a premium body for BULWARK, the tank. A rounded fortress: huge turret domes for shoulders with a glowing gun
slit in each, a broad round torso under a high turtle-shell collar that the small helmet sinks into, a wide glowing visor
under a heavy brow, hazard chevrons on the belt, rounded tower shields down the outside of the forearms, heavy fists with
steel knuckle plates, and thick legs that flare into elephant feet. The shells sit on a dark frame, so the gaps between
them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z. It
keeps BULWARK's size and reach, so it plays and reads exactly like the free BULWARK.
"""

from greebles import piston, place, rivets
from robotlib import Robot
from shells import BIG, DOME, FINE, MID, PLATE, RIM, SHELL
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.26, 0.3, 0.19), "material": "Metal", "tint": False},
    "Dark": {"color": (0.03, 0.032, 0.035), "material": "Metal", "tint": False},
    "Steel": {"color": (0.64, 0.66, 0.7), "material": "Metal", "tint": False},
    "Trim": {"color": (0.95, 0.6, 0.12), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.42, 0.12), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Bastion", smooth=True)
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
    robot.part("Pelvis", "Dark").pod((0, 3.02, 0.02), (1.5, 0.64, 1.02), SHELL, MID)
    armor = robot.part("Pelvis", "Armor")
    # A heavy armored belt with hazard chevrons on the front, and a plate over each hip.
    armor.pod((0, 3.12, 0.02), (1.9, 0.44, 1.22), PLATE, BIG, taper_x=(1.0, 0.95), taper_z=(1.0, 0.95))
    trim = robot.part("Pelvis", "Trim")
    for sign in (1, -1):
        armor.pod((0.98 * sign, 2.82, 0.0), (0.26, 0.72, 1.0), PLATE, MID, rot=(0, 0, 8 * sign))
        for offset in (0.16, 0.42):
            trim.pod((offset * sign, 3.12, -0.62), (0.1, 0.34, 0.05), PLATE, FINE, rot=(0, 0, 30 * sign))


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.pod((0, 4.66, 0.06), (2.0, 1.66, 1.2), SHELL, MID, taper_x=(1.1, 0.8))
    dark.pod((0, 3.72, 0.02), (1.0, 0.7, 0.86), SHELL, MID)
    armor = robot.part("Chest", "Armor")
    trim = robot.part("Chest", "Trim")
    steel = robot.part("Chest", "Steel")
    glow = robot.part("Chest", "Glow")
    for index, y in enumerate((3.56, 3.78, 4.0)):
        armor.pod((0, y, -0.3), (0.86 + 0.1 * index, 0.19, 0.44), PLATE, MID)
    # A broad round torso, two rounded slabs over the chest with a glowing seam between them, and a high turtle-shell
    # collar behind the head.
    armor.pod((0, 4.74, 0.08), (2.36, 1.36, 1.36), DOME, BIG, taper_x=(1.06, 0.84), taper_z=(1.0, 0.9))
    for sign in (1, -1):
        armor.pod((0.48 * sign, 4.86, -0.54), (0.86, 0.9, 0.34), PLATE, MID, rot=(-6, -10 * sign, 0))
        trim.pod((0.48 * sign, 4.44, -0.66), (0.78, 0.07, 0.1), PLATE, FINE, rot=(0, -10 * sign, 0))
        rivets(steel, (0.2 * sign, 5.26, -0.66), (0.8 * sign, 5.22, -0.56), 3, (0.2 * sign, 0, -1))
    glow.pod((0, 4.82, -0.67), (0.08, 0.62, 0.04), PLATE, FINE)
    armor.pod((0, 5.6, 0.3), (1.56, 0.66, 1.0), SHELL, BIG, taper_x=(0.84, 1.0), taper_z=(0.86, 1.0))
    trim.pod((0, 5.3, 0.3), (1.58, 0.05, 1.02), PLATE, RIM)
    # An engine pack on the back between two exhaust stacks.
    armor.pod((0, 4.8, 0.82), (1.56, 1.26, 0.56), PLATE, MID, taper_x=(1.0, 0.82))
    for sign in (1, -1):
        steel.cylinder((0.52 * sign, 4.3, 1.08), (0.52 * sign, 5.6, 1.08), 0.12, segments=12)
        steel.cylinder((0.52 * sign, 5.54, 1.08), (0.52 * sign, 5.66, 1.08), 0.16, segments=12)
        glow.pod((0.2 * sign, 4.8, 1.1), (0.07, 0.8, 0.04), SHELL, FINE)


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.36, 0.05), (0, 5.62, 0.05), 0.26, segments=12)
    armor = robot.part("Head", "Armor")
    # A small dome helmet sunk into the collar, a heavy brow over a wide glowing visor, and a jaw guard.
    armor.pod((0, 5.88, 0.06), (0.72, 0.62, 0.8), DOME, MID)
    armor.pod((0, 6.0, -0.28), (0.7, 0.14, 0.24), PLATE, FINE, rot=(-15, 0, 0))
    armor.pod((0, 5.66, -0.3), (0.52, 0.2, 0.22), PLATE, FINE, taper_x=(1.0, 0.82))
    dark.pod((0, 5.86, -0.28), (0.64, 0.22, 0.18), SHELL, MID)
    robot.part("Head", "Glow").pod((0, 5.86, -0.37), (0.54, 0.07, 0.04), PLATE, FINE)
    robot.part("Head", "Trim").pod((0, 6.15, 0.08), (0.12, 0.08, 0.6), SHELL, FINE)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.44)
    dark.cylinder((1.5 * sign, 4.85, 0.05), (1.53 * sign, 4.12, 0.05), 0.3, segments=12)
    armor = robot.part(upper, "Armor")
    # A turret dome for a shoulder, ringed in trim, with a glowing gun slit in its face.
    tilt = (0, 0, -12 * sign)
    turret = (1.76 * sign, 5.34, 0.0)
    armor.pod(turret, (1.4, 0.96, 1.46), DOME, BIG, rot=tilt)
    robot.part(upper, "Trim").pod(place(turret, tilt, (0, -0.37, 0)), (1.38, 0.07, 1.44), PLATE, RIM, rot=tilt)
    slit = place(turret, tilt, (0.06 * sign, 0.04, -0.66))
    robot.part(upper, "Dark").pod(slit, (0.62, 0.16, 0.12), PLATE, FINE, rot=tilt)
    robot.part(upper, "Glow").pod(place(turret, tilt, (0.06 * sign, 0.04, -0.71)), (0.5, 0.06, 0.04), PLATE, FINE, rot=tilt)
    armor.pod((1.56 * sign, 4.44, 0.04), (0.66, 0.7, 0.64), SHELL, MID)
    piston(dark, robot.part(upper, "Steel"), (1.5 * sign, 4.92, 0.46), (1.55 * sign, 3.96, 0.52), 0.1)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.2 * sign, 3.95, 0), (1.9 * sign, 3.95, 0), 0.34, segments=12)
    armor = robot.part(fore, "Armor")
    # A heavy forearm with a rounded tower shield down its outside, striped in trim.
    armor.pod((1.6 * sign, 3.36, 0.04), (1.0, 1.08, 1.0), PLATE, BIG, taper_x=(0.86, 1.06), taper_z=(0.86, 1.06))
    armor.pod((2.2 * sign, 3.34, 0.0), (0.16, 1.24, 1.06), PLATE, MID, taper_z=(0.86, 1.0))
    robot.part(fore, "Trim").pod((2.29 * sign, 3.52, 0.0), (0.04, 0.18, 0.86), PLATE, FINE)
    robot.part(fore, "Glow").pod((2.29 * sign, 3.2, 0.0), (0.04, 0.06, 0.66), PLATE, FINE)

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.92, 0), (1.62 * sign, 2.74, 0), 0.46, segments=12)
    armor = robot.part(hand, "Armor")
    # A heavy fist with a thumb, and four steel knuckle plates across its striking face (downward at rest).
    armor.pod((1.64 * sign, 2.35, 0.0), (1.12, 0.86, 1.12), PLATE, BIG)
    armor.pod((1.09 * sign, 2.42, -0.32), (0.26, 0.46, 0.34), SHELL, FINE, rot=(0, 0, 10 * sign))
    steel = robot.part(hand, "Steel")
    for z in (-0.39, -0.13, 0.13, 0.39):
        steel.pod((1.65 * sign, 1.92, z), (0.92, 0.14, 0.22), SHELL, FINE)
    robot.part(hand, "Trim").pod((1.64 * sign, 2.74, 0.0), (1.1, 0.08, 1.12), PLATE, RIM)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.42)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.34, segments=12)
    armor = robot.part(thigh, "Armor")
    armor.pod((0.66 * sign, 2.32, 0.0), (1.04, 1.18, 1.02), PLATE, BIG, taper_x=(1.06, 0.88), taper_z=(1.04, 0.88))
    armor.pod((0.66 * sign, 2.42, -0.52), (0.82, 0.86, 0.2), PLATE, MID, rot=(-6, 0, 0))
    piston(dark, robot.part(thigh, "Steel"), (0.64 * sign, 2.85, 0.52), (0.64 * sign, 1.88, 0.56), 0.09)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.24 * sign, 1.62, 0), (1.04 * sign, 1.62, 0), 0.35, segments=12)
    armor = robot.part(shin, "Armor")
    # A domed knee, and a shin that flares into an elephant foot, striped in trim.
    armor.pod((0.64 * sign, 1.66, -0.46), (0.7, 0.56, 0.36), DOME, MID, rot=(-10, 0, 0))
    armor.pod((0.64 * sign, 0.98, 0.02), (0.98, 1.04, 1.0), PLATE, BIG, taper_x=(0.86, 1.12), taper_z=(0.86, 1.12))
    robot.part(shin, "Trim").pod((0.64 * sign, 1.0, -0.5), (0.5, 0.07, 0.08), PLATE, FINE)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.32)
    dark.pod((0.66 * sign, 0.1, -0.14), (1.14, 0.2, 1.66), PLATE, MID)
    armor = robot.part(foot, "Armor")
    armor.pod((0.66 * sign, 0.38, -0.18), (1.08, 0.52, 1.46), PLATE, BIG)
    armor.pod((0.65 * sign, 0.64, 0.04), (0.92, 0.36, 0.9), SHELL, MID)
    robot.part(foot, "Trim").pod((0.66 * sign, 0.34, -0.86), (0.94, 0.3, 0.22), PLATE, FINE)
