"""MAUL: the heavy hitter. A hulking ex-industrial loader: a cab-like head with a strip light, beacon lamps and a roll bar,
an engine-block chest behind a grille, exhaust pipes up its back, hazard chevrons on its shoulders, big exposed pistons
driving its arms, hammer fists with steel striking plates and tread blocks on its feet. The armor plates sit on a dark
frame, so the gaps between them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z.
"""

from greebles import piston, place, rivets, vents
from robotlib import Robot
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.93, 0.66, 0.08), "material": "Metal", "tint": False},
    "Dark": {"color": (0.035, 0.035, 0.04), "material": "Metal", "tint": False},
    "Steel": {"color": (0.6, 0.62, 0.66), "material": "Metal", "tint": False},
    "Trim": {"color": (0.07, 0.07, 0.08), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.6, 0.12), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Maul", smooth=True)
    add_joints(robot)
    pelvis(robot)
    chest(robot)
    head(robot)
    for side, sign in SIDES:
        arm(robot, side, sign)
        leg(robot, side, sign)
    robot.finish()
    return robot


def chevrons(trim, center, rot, width, height, count, slant):
    """Diagonal hazard stripes, slanted by `slant` degrees, across the outward (+y) face of a plate centered at center
    and turned by rot."""
    pitch = width / count
    for index in range(count):
        offset = (-width / 2 + pitch * (index + 0.5), height / 2 + 0.012, 0)
        trim.box(place(center, rot, offset), (pitch * 0.45, 0.03, 0.62), bevel=0.01, segments=1,
                 rot=(rot[0], rot[1] + slant, rot[2]))


def pelvis(robot):
    dark = robot.part("Pelvis", "Dark")
    dark.box((0, 3.06, 0), (1.6, 0.52, 1.02), bevel=0.06)
    dark.box((0, 3.36, 0), (1.95, 0.2, 1.18), bevel=0.04)
    for sign in (1, -1):
        dark.cylinder((0.3 * sign, 3.0, 0), (1.0 * sign, 3.0, 0), 0.4, segments=12)
    armor = robot.part("Pelvis", "Armor")
    armor.box((0, 2.9, -0.56), (1.0, 0.5, 0.14), bevel=0.05, segments=3)
    for sign in (1, -1):
        armor.box((1.06 * sign, 2.95, 0.0), (0.18, 0.7, 1.0), bevel=0.06, segments=3)
    armor.box((0, 3.0, 0.56), (1.3, 0.55, 0.14), bevel=0.05)
    # A steel bumper across the front.
    steel = robot.part("Pelvis", "Steel")
    steel.cylinder((-0.85, 3.36, -0.66), (0.85, 3.36, -0.66), 0.08, segments=8)
    for sign in (1, -1):
        steel.cylinder((0.6 * sign, 3.36, -0.6), (0.6 * sign, 3.36, -0.7), 0.11, segments=8)
    robot.part("Pelvis", "Trim").box((0, 2.9, -0.64), (0.6, 0.12, 0.04), bevel=0.01, segments=1)


def chest(robot):
    dark = robot.part("Chest", "Dark")
    dark.taper((0, 4.72, 0.02), 1.3, (1.6, 1.05), (2.5, 1.25), bevel=0.08)
    dark.cylinder((0, 3.42, 0), (0, 4.06, 0), 0.5, segments=12)
    dark.cylinder((0, 5.32, 0.03), (0, 5.52, 0.03), 0.38, segments=12)
    armor = robot.part("Chest", "Armor")
    trim = robot.part("Chest", "Trim")
    steel = robot.part("Chest", "Steel")
    for y in (3.68, 3.86):
        armor.box((0, y, -0.02), (1.3, 0.13, 0.94), bevel=0.03)
    # The engine block: a frame around a radiator grille, side plates, a counterweight on the back.
    for sign in (1, -1):
        armor.box((0.78 * sign, 4.78, -0.68), (0.5, 1.1, 0.16), bevel=0.06, segments=3)
        armor.box((1.2 * sign, 4.7, -0.02), (0.18, 1.05, 1.05), bevel=0.06, segments=3)
        # Headlamps in the frame.
        steel.cylinder((0.78 * sign, 5.12, -0.75), (0.78 * sign, 5.12, -0.8), 0.15, segments=12)
        robot.part("Chest", "Glow").cylinder((0.78 * sign, 5.12, -0.8), (0.78 * sign, 5.12, -0.82), 0.1, segments=12)
        # Exhaust pipes up the back.
        steel.cylinder((0.72 * sign, 4.4, 0.78), (0.72 * sign, 6.2, 0.78), 0.12, segments=10)
        steel.cylinder((0.72 * sign, 6.14, 0.78), (0.72 * sign, 6.26, 0.78), 0.16, segments=10)
        rivets(steel, (1.29 * sign, 5.0, -0.4), (1.29 * sign, 5.0, 0.4), 3, (sign, 0, 0))
    armor.box((0, 5.3, -0.66), (1.06, 0.24, 0.16), bevel=0.05)
    armor.box((0, 4.24, -0.66), (1.06, 0.24, 0.16), bevel=0.05)
    vents(dark, (0, 4.77, -0.7), (0.98, 0.8, 0.08), 5)
    armor.box((0, 4.6, 0.72), (1.7, 1.2, 0.2), bevel=0.06, segments=3)
    armor.box((0, 5.32, 0.02), (2.6, 0.28, 1.25), bevel=0.08, segments=3)
    rivets(steel, (-0.7, 4.2, 0.83), (0.7, 4.2, 0.83), 5, (0, 0, 1))
    trim.box((0, 4.6, 0.83), (1.2, 0.08, 0.03), bevel=0.01, segments=1)


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.38, 0.05), (0, 5.66, 0.05), 0.28, segments=10)
    armor = robot.part("Head", "Armor")
    # A cab with a slanted windshield and a strip light across it.
    armor.box((0, 5.88, 0.08), (0.86, 0.6, 0.82), bevel=0.1, segments=3)
    dark.box((0, 5.9, -0.36), (0.72, 0.4, 0.12), bevel=0.03, rot=(-18, 0, 0))
    robot.part("Head", "Glow").box((0, 5.86, -0.42), (0.62, 0.08, 0.03), bevel=0.01, segments=1, rot=(-18, 0, 0))
    steel = robot.part("Head", "Steel")
    # A roll bar over the top and beacon lamps beside it.
    steel.cylinder((-0.46, 5.75, 0.3), (-0.46, 6.28, 0.3), 0.05, segments=8)
    steel.cylinder((0.46, 5.75, 0.3), (0.46, 6.28, 0.3), 0.05, segments=8)
    steel.cylinder((-0.46, 6.28, 0.3), (0.46, 6.28, 0.3), 0.05, segments=8)
    for sign in (1, -1):
        steel.cylinder((0.28 * sign, 6.18, -0.12), (0.28 * sign, 6.26, -0.12), 0.1, segments=10)
        robot.part("Head", "Glow").cylinder((0.28 * sign, 6.26, -0.12), (0.28 * sign, 6.38, -0.12), 0.07, segments=10)
        dark.box((0.45 * sign, 5.86, 0.08), (0.06, 0.4, 0.6), bevel=0.02)
    robot.part("Head", "Trim").box((0, 6.19, 0.08), (0.7, 0.03, 0.12), bevel=0.01, segments=1)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.44)
    dark.cylinder((1.5 * sign, 4.85, 0.05), (1.53 * sign, 4.12, 0.05), 0.3, segments=12)
    armor = robot.part(upper, "Armor")
    # A chunky shoulder with hazard chevrons, a housing on the upper arm and a big piston down its front.
    shoulder, tilt = (1.7 * sign, 5.38, 0.0), (0, 0, -12 * sign)
    armor.box(shoulder, (1.06, 0.6, 1.24), bevel=0.18, segments=3, rot=tilt)
    chevrons(robot.part(upper, "Trim"), shoulder, tilt, 0.9, 0.6, 4, 35 * sign)
    armor.box((1.56 * sign, 4.5, 0.22), (0.62, 0.72, 0.5), bevel=0.08, segments=3)
    steel = robot.part(upper, "Steel")
    piston(dark, steel, (1.5 * sign, 5.0, -0.42), (1.55 * sign, 3.92, -0.48), 0.13)
    rivets(steel, (1.88 * sign, 4.75, 0.05), (1.88 * sign, 4.25, 0.05), 3, (sign, 0, 0))

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.2 * sign, 3.95, 0), (1.9 * sign, 3.95, 0), 0.36, segments=12)
    armor = robot.part(fore, "Armor")
    armor.box((1.6 * sign, 3.34, 0.05), (1.02, 0.96, 1.04), bevel=0.12, segments=3)
    steel = robot.part(fore, "Steel")
    piston(dark, steel, (1.6 * sign, 3.84, 0.66), (1.62 * sign, 2.96, 0.68), 0.1)
    for y in (3.66, 3.02):
        rivets(steel, (1.3 * sign, y, -0.48), (1.9 * sign, y, -0.48), 3, (0, 0, -1))
    robot.part(fore, "Trim").box((1.6 * sign, 3.34, -0.48), (0.86, 0.12, 0.03), bevel=0.01, segments=1)

    hand = "Hand" + side
    dark = robot.part(hand, "Dark")
    dark.cylinder((1.62 * sign, 2.92, 0), (1.62 * sign, 2.76, 0), 0.46, segments=12)
    armor = robot.part(hand, "Armor")
    # A hammer fist: a square block with a thick steel striking plate, bolted at the corners.
    armor.box((1.64 * sign, 2.38, 0), (1.1, 0.78, 1.04), bevel=0.12, segments=3)
    armor.box((1.08 * sign, 2.44, -0.34), (0.24, 0.42, 0.3), bevel=0.06)
    steel = robot.part(hand, "Steel")
    steel.box((1.64 * sign, 1.94, 0), (1.06, 0.14, 1.0), bevel=0.04)
    for dx in (-0.38, 0.38):
        for dz in (-0.36, 0.36):
            steel.cylinder((1.64 * sign + dx, 1.9, dz), (1.64 * sign + dx, 1.85, dz), 0.06, segments=6)
    robot.part(hand, "Trim").box((1.64 * sign, 2.72, 0), (1.12, 0.1, 1.06), bevel=0.03)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.42)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.34, segments=10)
    armor = robot.part(thigh, "Armor")
    armor.box((0.64 * sign, 2.34, -0.04), (0.94, 1.1, 0.96), bevel=0.1, segments=3)
    robot.part(thigh, "Trim").box((0.64 * sign, 2.34, -0.53), (0.7, 0.1, 0.03), bevel=0.01, segments=1)
    piston(dark, robot.part(thigh, "Steel"), (0.64 * sign, 2.85, 0.56), (0.64 * sign, 1.86, 0.6), 0.1)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.22 * sign, 1.62, 0), (1.06 * sign, 1.62, 0), 0.36, segments=12)
    armor = robot.part(shin, "Armor")
    armor.box((0.64 * sign, 1.02, 0.0), (0.92, 0.98, 0.94), bevel=0.1, segments=3)
    steel = robot.part(shin, "Steel")
    # A steel bumper over the knee.
    steel.box((0.64 * sign, 1.66, -0.46), (0.7, 0.36, 0.22), bevel=0.08, rot=(-10, 0, 0))
    rivets(steel, (0.36 * sign, 0.75, -0.5), (0.92 * sign, 0.75, -0.5), 3, (0, 0, -1))
    robot.part(shin, "Trim").box((0.64 * sign, 1.1, -0.48), (0.66, 0.1, 0.03), bevel=0.01, segments=1)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.32)
    dark.box((0.66 * sign, 0.1, -0.15), (1.04, 0.2, 1.6), bevel=0.06)
    # Tread blocks along the outside of the sole.
    for index in range(5):
        dark.box((1.17 * sign, 0.17, -0.8 + index * 0.33), (0.12, 0.2, 0.24), bevel=0.03, segments=1)
    armor = robot.part(foot, "Armor")
    armor.box((0.66 * sign, 0.4, -0.2), (0.96, 0.42, 1.34), bevel=0.1, segments=3)
    armor.box((0.65 * sign, 0.64, 0.04), (0.86, 0.34, 0.86), bevel=0.08)
    robot.part(foot, "Steel").box((0.66 * sign, 0.34, -0.9), (0.94, 0.3, 0.16), bevel=0.05)
