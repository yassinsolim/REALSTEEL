"""ANVIL: the first fighter. A heavyweight boxing robot built from beveled plates, pistons and joint hubs.

Authored at rest in Roblox axes and studs: standing, arms hanging, facing -z, feet on y = 0. Each joint owns one mesh
per material role (Armor, Dark, Trim, Glow); the game recolors Trim and Glow per player.
"""

from robotlib import Robot

ROLES = {
    # color is linear-ish sRGB 0-1; material is the Roblox Enum.Material used in game; tint parts take the team color.
    "Armor": {"color": (0.38, 0.41, 0.48), "material": "Metal", "tint": False},
    "Dark": {"color": (0.055, 0.06, 0.075), "material": "Metal", "tint": False},
    "Trim": {"color": (0.18, 0.5, 1.0), "material": "Metal", "tint": True},
    "Glow": {"color": (0.35, 0.85, 1.0), "material": "Neon", "tint": True},
}

# Parents come before children. Pivots are the rest-pose joint centers.
SIDES = (("R", 1), ("L", -1))


def build():
    robot = Robot("Anvil")
    robot.joint("Pelvis", None, (0, 3.10, 0))
    robot.joint("Chest", "Pelvis", (0, 3.65, 0))
    robot.joint("Head", "Chest", (0, 5.45, 0.05))
    for name, sign in SIDES:
        robot.joint("UpperArm" + name, "Chest", (1.45 * sign, 5.0, 0))
        robot.joint("Forearm" + name, "UpperArm" + name, (1.55 * sign, 3.95, 0))
        robot.joint("Hand" + name, "Forearm" + name, (1.62 * sign, 2.85, 0))
        robot.joint("Thigh" + name, "Pelvis", (0.62 * sign, 3.0, 0))
        robot.joint("Shin" + name, "Thigh" + name, (0.64 * sign, 1.62, 0))
        robot.joint("Foot" + name, "Shin" + name, (0.64 * sign, 0.50, 0))

    pelvis(robot)
    chest(robot)
    head(robot)
    for name, sign in SIDES:
        arm(robot, name, sign)
        leg(robot, name, sign)
    robot.finish()
    return robot


def pelvis(robot):
    armor = robot.part("Pelvis", "Armor")
    armor.box((0, 3.05, 0), (1.75, 0.55, 1.1), bevel=0.08)
    armor.box((0, 2.78, -0.58), (0.8, 0.5, 0.12), bevel=0.05)
    for sign in (1, -1):
        armor.box((1.0 * sign, 3.0, 0), (0.22, 0.65, 0.95), bevel=0.06)
    dark = robot.part("Pelvis", "Dark")
    dark.box((0, 3.33, 0), (1.95, 0.22, 1.2), bevel=0.04)
    for sign in (1, -1):
        dark.cylinder((0.35 * sign, 3.0, 0), (0.95 * sign, 3.0, 0), 0.38, segments=10)
    robot.part("Pelvis", "Trim").box((0, 3.33, -0.64), (0.62, 0.32, 0.12), bevel=0.03)
    robot.part("Pelvis", "Glow").box((0, 3.33, -0.71), (0.44, 0.1, 0.04), bevel=0.01, segments=1)


def chest(robot):
    armor = robot.part("Chest", "Armor")
    armor.taper((0, 4.7, 0), 1.25, (1.7, 1.05), (2.4, 1.2), bevel=0.09)
    armor.box((0, 4.78, -0.66), (1.6, 0.85, 0.12), bevel=0.04)
    armor.box((0, 4.7, 0.62), (1.8, 1.0, 0.1), bevel=0.04)
    armor.box((0, 5.25, 0), (2.5, 0.28, 1.1), bevel=0.07)
    for y in (3.72, 3.95):
        armor.box((0, y, 0), (1.3, 0.14, 0.9), bevel=0.03)
    for sign in (1, -1):
        armor.cylinder((0.45 * sign, 5.0, 0.78), (0.45 * sign, 5.65, 0.78), 0.13, segments=8)
    dark = robot.part("Chest", "Dark")
    dark.cylinder((0, 3.45, 0), (0, 4.1, 0), 0.5, segments=10)
    dark.cylinder((0, 5.3, 0), (0, 5.5, 0), 0.36, segments=10)
    dark.box((0, 4.75, 0.72), (1.3, 0.8, 0.25), bevel=0.04)
    dark.cylinder((0, 4.85, -0.7), (0, 4.85, -0.76), 0.36, segments=12)
    for sign in (1, -1):
        for y in (4.3, 4.42, 4.54):
            dark.box((0.45 * sign, y, -0.63), (0.5, 0.05, 0.05), bevel=0.01, segments=1)
        dark.cylinder((0.45 * sign, 5.65, 0.78), (0.45 * sign, 5.72, 0.78), 0.1, segments=8)
    robot.part("Chest", "Glow").cylinder((0, 4.85, -0.76), (0, 4.85, -0.8), 0.24, segments=12)
    trim = robot.part("Chest", "Trim")
    for sign in (1, -1):
        trim.box((0.66 * sign, 4.5, -0.68), (0.14, 0.7, 0.05), bevel=0.01, segments=1)


def head(robot):
    armor = robot.part("Head", "Armor")
    armor.box((0, 5.97, 0), (1.0, 0.78, 1.0), bevel=0.14)
    armor.box((0, 6.23, -0.38), (0.9, 0.14, 0.34), bevel=0.04)
    dark = robot.part("Head", "Dark")
    dark.cylinder((0, 5.38, 0), (0, 5.7, 0), 0.24, segments=10)
    dark.box((0, 5.62, -0.36), (0.7, 0.26, 0.4), bevel=0.05)
    dark.box((0, 5.93, -0.5), (0.84, 0.3, 0.14), bevel=0.03)
    for sign in (1, -1):
        dark.cylinder((0.5 * sign, 5.95, 0), (0.64 * sign, 5.95, 0), 0.22, segments=10)
    robot.part("Head", "Glow").box((0, 5.93, -0.58), (0.7, 0.13, 0.05), bevel=0.01, segments=1)
    robot.part("Head", "Trim").box((0, 6.4, 0.05), (0.16, 0.2, 0.85), bevel=0.04)


def arm(robot, side, sign):
    upper = "UpperArm" + side
    armor = robot.part(upper, "Armor")
    armor.box((1.68 * sign, 5.2, 0), (0.95, 0.55, 1.15), bevel=0.16)
    armor.cylinder((1.48 * sign, 4.9, 0), (1.53 * sign, 4.1, 0), 0.34, radius_end=0.3, segments=10)
    armor.box((1.82 * sign, 4.6, 0), (0.16, 0.65, 0.55), bevel=0.04)
    dark = robot.part(upper, "Dark")
    dark.sphere((1.45 * sign, 5.0, 0), 0.42)
    dark.cylinder((1.5 * sign, 4.85, -0.4), (1.5 * sign, 4.25, -0.4), 0.07, segments=8)
    dark.cylinder((1.52 * sign, 4.15, 0), (1.52 * sign, 4.0, 0), 0.33, segments=10)
    robot.part(upper, "Trim").box((1.72 * sign, 5.48, 0), (0.6, 0.08, 0.95), bevel=0.02)

    fore = "Forearm" + side
    armor = robot.part(fore, "Armor")
    armor.taper((1.6 * sign, 3.4, 0), 1.05, (1.0, 1.0), (0.66, 0.66), bevel=0.12)
    dark = robot.part(fore, "Dark")
    dark.cylinder((1.3 * sign, 3.95, 0), (1.82 * sign, 3.95, 0), 0.33, segments=10)
    dark.cylinder((1.6 * sign, 3.75, -0.5), (1.62 * sign, 3.15, -0.52), 0.06, segments=8)
    robot.part(fore, "Trim").box((1.62 * sign, 3.0, 0), (1.06, 0.14, 1.06), bevel=0.05)

    hand = "Hand" + side
    robot.part(hand, "Dark").cylinder((1.62 * sign, 2.9, 0), (1.62 * sign, 2.78, 0), 0.4, segments=10)
    robot.part(hand, "Armor").box((1.64 * sign, 2.42, 0), (0.86, 0.72, 0.98), bevel=0.18)
    robot.part(hand, "Trim").box((1.64 * sign, 2.08, 0), (0.74, 0.14, 0.88), bevel=0.04)
    robot.part(hand, "Glow").box((1.64 * sign, 2.0, 0), (0.6, 0.05, 0.72), bevel=0.01, segments=1)


def leg(robot, side, sign):
    thigh = "Thigh" + side
    armor = robot.part(thigh, "Armor")
    armor.taper((0.64 * sign, 2.3, 0), 1.4, (0.74, 0.8), (0.92, 0.95), bevel=0.1)
    armor.box((0.64 * sign, 2.45, -0.5), (0.62, 0.95, 0.1), bevel=0.04)
    dark = robot.part(thigh, "Dark")
    dark.sphere((0.62 * sign, 3.0, 0), 0.4)
    dark.cylinder((0.64 * sign, 2.9, 0.5), (0.64 * sign, 1.9, 0.56), 0.08, segments=8)
    robot.part(thigh, "Trim").box((0.64 * sign, 2.45, -0.57), (0.12, 0.8, 0.04), bevel=0.01, segments=1)

    shin = "Shin" + side
    armor = robot.part(shin, "Armor")
    armor.box((0.64 * sign, 1.64, -0.42), (0.6, 0.5, 0.2), bevel=0.1)
    armor.taper((0.64 * sign, 1.05, 0), 1.0, (0.62, 0.7), (0.76, 0.78), bevel=0.08)
    armor.box((0.64 * sign, 1.15, 0.38), (0.55, 0.7, 0.18), bevel=0.05)
    dark = robot.part(shin, "Dark")
    dark.cylinder((0.3 * sign, 1.62, 0), (0.98 * sign, 1.62, 0), 0.33, segments=10)
    dark.cylinder((0.64 * sign, 1.4, 0.46), (0.64 * sign, 0.8, 0.44), 0.08, segments=8)
    robot.part(shin, "Trim").box((0.64 * sign, 1.1, -0.38), (0.1, 0.7, 0.04), bevel=0.01, segments=1)

    foot = "Foot" + side
    armor = robot.part(foot, "Armor")
    armor.box((0.66 * sign, 0.38, -0.2), (0.8, 0.36, 1.25), bevel=0.1)
    armor.box((0.65 * sign, 0.58, 0.02), (0.72, 0.4, 0.8), bevel=0.08)
    dark = robot.part(foot, "Dark")
    dark.sphere((0.64 * sign, 0.5, 0), 0.3)
    dark.box((0.66 * sign, 0.1, -0.15), (0.9, 0.2, 1.5), bevel=0.06)
    robot.part(foot, "Trim").box((0.66 * sign, 0.36, -0.82), (0.74, 0.3, 0.2), bevel=0.06)
