"""BULWARK: the tank. A monolithic heavyweight: stacked slab pauldrons, a low visor-slit helmet sunk into a raised collar,
gauntlets that flare out to big knuckled fists, exhaust stacks on its back and pistons at its big joints. The armor plates
sit on a dark frame, so the gaps between them read as panel lines.

Built on the shared skeleton (skeleton.py), in Roblox axes and studs like ANVIL: standing, arms hanging, facing -z.
"""

from greebles import piston, place, rivets, vents
from robotlib import Robot
from skeleton import SIDES, add_joints

ROLES = {
    "Armor": {"color": (0.3, 0.31, 0.35), "material": "Metal", "tint": False},
    "Dark": {"color": (0.03, 0.032, 0.04), "material": "Metal", "tint": False},
    "Steel": {"color": (0.64, 0.66, 0.7), "material": "Metal", "tint": False},
    "Trim": {"color": (1.0, 0.58, 0.12), "material": "Metal", "tint": True},
    "Glow": {"color": (1.0, 0.55, 0.18), "material": "Neon", "tint": True},
}


def build():
    robot = Robot("Bulwark", smooth=True)
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
    dark.box((0, 3.06, 0), (1.55, 0.5, 1.0), bevel=0.06)
    dark.box((0, 3.36, 0), (2.0, 0.2, 1.2), bevel=0.04)
    for sign in (1, -1):
        dark.cylinder((0.3 * sign, 3.0, 0), (1.0 * sign, 3.0, 0), 0.4, segments=12)
    armor = robot.part("Pelvis", "Armor")
    # A heavy belt of plates: the cup in front, faulds over the hips, a plate behind.
    armor.taper((0, 2.86, -0.6), 0.62, (0.72, 0.14), (1.08, 0.16), bevel=0.05)
    for sign in (1, -1):
        armor.box((1.1 * sign, 2.95, -0.02), (0.2, 0.72, 1.02), bevel=0.06, rot=(0, 0, -8 * sign))
        armor.box((0.66 * sign, 2.98, -0.58), (0.36, 0.5, 0.12), bevel=0.04, rot=(0, 10 * sign, 0))
    armor.box((0, 3.0, 0.58), (1.2, 0.55, 0.14), bevel=0.05)
    robot.part("Pelvis", "Trim").box((0, 3.36, -0.64), (0.7, 0.3, 0.1), bevel=0.03)
    robot.part("Pelvis", "Glow").box((0, 3.36, -0.7), (0.46, 0.08, 0.04), bevel=0.01, segments=1)
    steel = robot.part("Pelvis", "Steel")
    for sign in (1, -1):
        rivets(steel, (0.5 * sign, 3.36, -0.6), (0.9 * sign, 3.36, -0.6), 3, (0, 0, -1))


def chest(robot):
    dark = robot.part("Chest", "Dark")
    # The frame under the plates: the rib cage, the waist and the neck ring.
    dark.taper((0, 4.7, 0.02), 1.3, (1.5, 0.95), (2.35, 1.15), bevel=0.08)
    dark.cylinder((0, 3.42, 0), (0, 4.05, 0), 0.48, segments=12)
    dark.cylinder((0, 5.32, 0.03), (0, 5.52, 0.03), 0.38, segments=12)
    armor = robot.part("Chest", "Armor")
    for y in (3.68, 3.86):
        armor.box((0, y, -0.02), (1.25, 0.13, 0.92), bevel=0.03)
    for sign in (1, -1):
        # Pectoral plates angled back at the sides, split down the middle for the sternum light.
        armor.box((0.62 * sign, 4.92, -0.66), (1.12, 0.85, 0.16), bevel=0.08, segments=3, rot=(-6, -10 * sign, 0))
        armor.box((0.62 * sign, 4.25, -0.55), (0.9, 0.45, 0.14), bevel=0.05, rot=(8, -6 * sign, 0))
        armor.box((1.12 * sign, 4.65, -0.05), (0.18, 1.0, 1.0), bevel=0.06, segments=3)
    # The shoulder yoke, and the raised collar the head sits down in.
    armor.box((0, 5.3, 0.02), (2.75, 0.3, 1.25), bevel=0.1, segments=3)
    armor.box((0, 5.66, 0.7), (1.55, 0.55, 0.3), bevel=0.1, segments=3, rot=(-8, 0, 0))
    for sign in (1, -1):
        armor.box((0.67 * sign, 5.62, 0.04), (0.22, 0.45, 0.95), bevel=0.05, rot=(0, 0, 10 * sign))
    armor.box((0, 4.7, 0.66), (1.9, 1.05, 0.14), bevel=0.05)
    robot.part("Chest", "Trim").box((0, 4.78, -0.77), (0.2, 1.0, 0.08), bevel=0.02)
    glow = robot.part("Chest", "Glow")
    glow.box((0, 4.78, -0.82), (0.07, 0.82, 0.03), bevel=0.01, segments=1)
    steel = robot.part("Chest", "Steel")
    for sign in (1, -1):
        # Exhaust stacks on the back, glowing at the mouth.
        dark.cylinder((0.5 * sign, 4.9, 0.78), (0.56 * sign, 5.95, 0.92), 0.15, segments=10)
        steel.cylinder((0.555 * sign, 5.88, 0.9), (0.565 * sign, 6.02, 0.93), 0.19, segments=10)
        glow.cylinder((0.565 * sign, 6.01, 0.93), (0.566 * sign, 6.03, 0.93), 0.11, segments=10)
        piston(dark, steel, (0.82 * sign, 3.5, -0.3), (0.9 * sign, 4.32, -0.42), 0.09)
        rivets(steel, (0.3 * sign, 5.45, -0.6), (1.15 * sign, 5.45, -0.6), 4, (0, 0, -1))
        vents(dark, (0.5 * sign, 4.45, 0.75), (0.55, 0.42, 0.06), 3)


def head(robot):
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.38, 0.05), (0, 5.66, 0.05), 0.27, segments=10)
    armor = robot.part("Head", "Armor")
    armor.taper((0, 5.86, 0.06), 0.6, (0.84, 0.86), (0.72, 0.8), bevel=0.1)
    armor.box((0, 6.1, -0.32), (0.86, 0.14, 0.3), bevel=0.04, rot=(-14, 0, 0))
    armor.box((0, 5.6, -0.34), (0.62, 0.18, 0.22), bevel=0.05)
    dark.box((0, 5.8, -0.38), (0.72, 0.36, 0.12), bevel=0.03)
    for sign in (1, -1):
        dark.cylinder((0.42 * sign, 5.86, 0.06), (0.5 * sign, 5.86, 0.06), 0.18, segments=10)
        armor.box((0.3 * sign, 5.66, -0.38), (0.14, 0.26, 0.14), bevel=0.03)
    robot.part("Head", "Glow").box((0, 5.86, -0.45), (0.58, 0.07, 0.03), bevel=0.01, segments=1)
    robot.part("Head", "Trim").box((0, 6.2, 0.08), (0.12, 0.1, 0.72), bevel=0.03)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.44)
    dark.cylinder((1.5 * sign, 4.85, 0), (1.53 * sign, 4.12, 0), 0.33, segments=12)
    armor = robot.part(upper, "Armor")
    # A stacked slab pauldron, drooping outward, with a ridge along the top and a trimmed outer edge.
    pauldron, tilt = (1.72 * sign, 5.48, 0.0), (0, 0, -16 * sign)
    step, step_tilt = (1.98 * sign, 5.1, 0.0), (0, 0, -30 * sign)
    armor.box(pauldron, (1.2, 0.62, 1.4), bevel=0.22, segments=3, rot=tilt)
    armor.box(place(pauldron, tilt, (0.08, 0.34, 0)), (0.26, 0.14, 1.22), bevel=0.06, rot=tilt)
    armor.box(step, (0.82, 0.36, 1.26), bevel=0.12, segments=3, rot=step_tilt)
    armor.box((1.5 * sign, 4.5, -0.3), (0.5, 0.62, 0.16), bevel=0.06)
    robot.part(upper, "Trim").box(place(step, step_tilt, (0.42 * sign, 0, 0)), (0.07, 0.3, 1.3), bevel=0.02, rot=step_tilt)
    steel = robot.part(upper, "Steel")
    rivets(steel, place(pauldron, tilt, (-0.4, 0.31, -0.5)), place(pauldron, tilt, (-0.4, 0.31, 0.5)), 4, (0, 1, 0))
    piston(dark, steel, (1.5 * sign, 4.9, 0.4), (1.54 * sign, 4.15, 0.42), 0.08)

    fore = "Forearm" + side
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.2 * sign, 3.95, 0), (1.9 * sign, 3.95, 0), 0.35, segments=12)
    armor = robot.part(fore, "Armor")
    # A gauntlet that flares out toward the fist, with a guard plate on the outside and a plate in front.
    armor.taper((1.6 * sign, 3.32, 0), 1.0, (1.18, 1.2), (0.86, 0.9), bevel=0.14, segments=3)
    armor.box((2.17 * sign, 3.32, 0.0), (0.12, 0.86, 1.0), bevel=0.04, rot=(0, 0, 9 * sign))
    armor.box((1.6 * sign, 3.4, -0.55), (0.7, 0.75, 0.1), bevel=0.04, rot=(9, 0, 0))
    robot.part(fore, "Trim").box((1.62 * sign, 2.9, 0), (1.24, 0.12, 1.26), bevel=0.04)
    steel = robot.part(fore, "Steel")
    rivets(steel, (1.42 * sign, 3.62, -0.6), (1.78 * sign, 3.62, -0.6), 3, (0, 0, -1))
    piston(dark, steel, (1.6 * sign, 3.85, 0.55), (1.62 * sign, 3.05, 0.66), 0.08)

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.92, 0), (1.62 * sign, 2.76, 0), 0.47, segments=12)
    armor = robot.part(hand, "Armor")
    armor.box((1.64 * sign, 2.36, 0), (1.06, 0.86, 1.12), bevel=0.26, segments=3)
    armor.box((1.1 * sign, 2.42, -0.36), (0.26, 0.46, 0.32), bevel=0.08)
    steel = robot.part(hand, "Steel")
    # Knuckle plates on the striking face, which hangs downward at rest.
    for z in (-0.39, -0.13, 0.13, 0.39):
        steel.box((1.66 * sign, 1.92, z), (0.84, 0.12, 0.22), bevel=0.04)
    robot.part(hand, "Trim").box((1.64 * sign, 2.72, 0), (1.08, 0.1, 1.14), bevel=0.03)
    robot.part(hand, "Glow").box((2.17 * sign, 2.36, 0), (0.03, 0.12, 0.7), bevel=0.01, segments=1)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.42)
    dark.cylinder((0.63 * sign, 2.9, 0), (0.64 * sign, 1.85, 0), 0.34, segments=10)
    armor = robot.part(thigh, "Armor")
    armor.taper((0.64 * sign, 2.32, -0.02), 1.2, (0.86, 0.9), (1.0, 1.04), bevel=0.1)
    armor.box((0.66 * sign, 2.4, -0.55), (0.7, 0.88, 0.12), bevel=0.04, rot=(-5, 0, 0))
    armor.box((1.14 * sign, 2.45, 0.0), (0.12, 0.8, 0.82), bevel=0.04, rot=(0, 0, 4 * sign))
    robot.part(thigh, "Trim").box((0.66 * sign, 2.4, -0.62), (0.12, 0.72, 0.04), bevel=0.01, segments=1)
    piston(dark, robot.part(thigh, "Steel"), (0.64 * sign, 2.85, 0.52), (0.64 * sign, 1.88, 0.56), 0.085)

    shin = "Shin" + side
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.24 * sign, 1.62, 0), (1.04 * sign, 1.62, 0), 0.35, segments=12)
    armor = robot.part(shin, "Armor")
    armor.box((0.64 * sign, 1.7, -0.44), (0.74, 0.62, 0.28), bevel=0.11, rot=(-12, 0, 0))
    armor.taper((0.64 * sign, 1.02, 0.0), 1.0, (0.88, 0.92), (0.78, 0.84), bevel=0.09)
    armor.box((0.64 * sign, 1.0, -0.5), (0.66, 0.74, 0.12), bevel=0.04, rot=(4, 0, 0))
    robot.part(shin, "Trim").box((0.64 * sign, 1.0, -0.57), (0.12, 0.6, 0.04), bevel=0.01, segments=1)
    piston(dark, robot.part(shin, "Steel"), (0.64 * sign, 1.5, 0.48), (0.64 * sign, 0.72, 0.5), 0.08)

    foot = "Foot" + side
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.32)
    dark.box((0.66 * sign, 0.1, -0.16), (1.02, 0.2, 1.62), bevel=0.06)
    dark.box((0.66 * sign, 0.3, 0.62), (0.56, 0.3, 0.26), bevel=0.05)
    armor = robot.part(foot, "Armor")
    armor.box((0.66 * sign, 0.38, -0.24), (0.94, 0.38, 1.32), bevel=0.1)
    armor.box((0.65 * sign, 0.6, 0.02), (0.84, 0.36, 0.86), bevel=0.08)
    armor.box((0.66 * sign, 0.32, -0.86), (0.9, 0.3, 0.28), bevel=0.08, rot=(10, 0, 0))
    robot.part(foot, "Trim").box((0.66 * sign, 0.4, -0.97), (0.6, 0.12, 0.08), bevel=0.02)
