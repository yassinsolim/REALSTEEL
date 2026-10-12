"""The robot's add-on kits: armor, pistons, fins and crests that sit on ANVIL's joints. Chassis kits are always on for
that chassis, module kits show when the module is equipped, and crests are a cosmetic choice for the head.

Authored at rest in Roblox axes and studs, like anvil.py: x is the robot's right, y up, the robot faces -z. Every piece is
one primitive (a box, a cylinder or a ball) given in the same rest coordinates as the rig, so the game can draw it as a
plain Part today and a mesh later; the generated Luau (RobotKits.luau) and the Blender previews both read this file.
This module needs no Blender: python art/kits.py --luau src/shared writes RobotKits.luau on its own.

A piece is a dict: joint, role (Armor, Dark, Trim or Glow), shape (box, cyl or ball), center, size and rot. A cylinder's
axis is its local Y, and its size is (diameter, length, diameter). rot is Euler degrees applied as
CFrame.fromEulerAnglesYXZ(rx, ry, rz) about the piece's own center.
"""

import argparse
import math
import os

SIDES = (("R", 1), ("L", -1))

KITS = {}
# Which kits belong to which choice, so the game and the previews agree. Chassis: the kit that chassis always wears.
CHASSIS_KITS = {"BULWARK": "Bulwark", "LANCE": "Lance", "RAZOR": "Razor", "MAUL": "Maul"}
MODULE_KITS = {
    "ARMS": {2: "PistonFists", 3: "ServoWrists"},
    "CORE": {2: "Plating", 3: "ShockDampers"},
    "LEGS": {2: "HydraulicBoots", 3: "SpringGreaves"},
}
CRESTS = ("CrestFin", "CrestAntenna", "CrestHorns", "CrestHalo")


class Kit:
    def __init__(self, name):
        self.name = name
        self.pieces = []
        KITS[name] = self.pieces

    def box(self, joint, role, center, size, rot=(0, 0, 0)):
        self.pieces.append(
            {"joint": joint, "role": role, "shape": "box", "center": tuple(center), "size": tuple(size), "rot": tuple(rot)}
        )

    def ball(self, joint, role, center, diameter):
        self.pieces.append(
            {
                "joint": joint,
                "role": role,
                "shape": "ball",
                "center": tuple(center),
                "size": (diameter, diameter, diameter),
                "rot": (0, 0, 0),
            }
        )

    def cyl(self, joint, role, center, diameter, length, rot=(0, 0, 0)):
        self.pieces.append(
            {
                "joint": joint,
                "role": role,
                "shape": "cyl",
                "center": tuple(center),
                "size": (diameter, length, diameter),
                "rot": tuple(rot),
            }
        )

    def rod(self, joint, role, start, end, diameter):
        """A cylinder between two points."""
        dx, dy, dz = (end[i] - start[i] for i in range(3))
        length = math.sqrt(dx * dx + dy * dy + dz * dz)
        center = tuple((start[i] + end[i]) / 2 for i in range(3))
        # CFrame.fromEulerAnglesYXZ(rx, ry, 0) turns local +Y into (sin rx sin ry, cos rx, sin rx cos ry).
        rx = math.degrees(math.acos(max(-1.0, min(1.0, dy / length))))
        ry = math.degrees(math.atan2(dx, dz)) if abs(dx) + abs(dz) > 1e-9 else 0.0
        self.cyl(joint, role, center, diameter, length, (rx, ry, 0))

    def rings(self, joint, role, x, z, y_low, y_high, count, diameter, thickness):
        """Thin rings stacked along a vertical axis, like a coil."""
        for index in range(count):
            y = y_low + (y_high - y_low) * (index / max(count - 1, 1))
            self.cyl(joint, role, (x, y, z), diameter, thickness)


def sided(builder):
    """Calls builder(side, sign) for the right side then the left."""
    for side, sign in SIDES:
        builder(side, sign)


# --- Chassis kits ---------------------------------------------------------------------------------------------------


def bulwark():
    k = Kit("Bulwark")

    def side(name, sign):
        upper, fore, hand, shin = "UpperArm" + name, "Forearm" + name, "Hand" + name, "Shin" + name
        # Heavy two-tier pauldrons.
        k.box(upper, "Armor", (1.8 * sign, 5.42, 0), (1.3, 0.6, 1.7))
        k.box(upper, "Armor", (2.0 * sign, 4.98, 0), (1.05, 0.42, 1.5))
        k.box(upper, "Trim", (1.8 * sign, 5.76, 0), (0.95, 0.08, 1.4))
        k.cyl(upper, "Dark", (1.3 * sign, 5.6, -0.6), 0.2, 0.2, (90, 0, 0))
        # Broad bracers and a heavier fist.
        k.box(fore, "Armor", (1.6 * sign, 3.6, 0), (1.34, 0.55, 1.34))
        k.box(fore, "Trim", (1.6 * sign, 3.3, 0), (1.38, 0.08, 1.38))
        k.box(hand, "Armor", (1.64 * sign, 2.02, 0), (1.06, 0.24, 1.18))
        # Knee plates.
        k.box(shin, "Armor", (0.64 * sign, 1.68, -0.6), (0.76, 0.6, 0.32))
        k.box(shin, "Trim", (0.64 * sign, 1.4, -0.64), (0.54, 0.06, 0.24))
        # Cheek plates on the helmet.
        k.box("Head", "Armor", (0.6 * sign, 5.95, -0.08), (0.22, 0.64, 0.78))

    sided(side)
    # A thick collar, plates either side of the core, and a slab of armor down the back.
    k.box("Chest", "Armor", (0, 5.16, -0.56), (2.3, 0.5, 0.44))
    k.box("Chest", "Trim", (0, 5.16, -0.8), (1.8, 0.07, 0.04))
    for sign in (1, -1):
        k.box("Chest", "Armor", (0.78 * sign, 4.45, -0.8), (0.7, 0.95, 0.18))
        k.box("Chest", "Dark", (1.22 * sign, 4.7, -0.3), (0.16, 0.9, 0.7))
    k.box("Chest", "Armor", (0, 4.65, 0.86), (2.0, 1.4, 0.22))
    k.box("Chest", "Trim", (0, 4.65, 1.0), (1.4, 0.08, 0.06))
    k.box("Pelvis", "Armor", (0, 2.82, 0.66), (1.4, 0.6, 0.18))
    k.box("Head", "Dark", (0, 6.22, -0.52), (1.1, 0.16, 0.24))


def lance():
    k = Kit("Lance")

    def side(name, sign):
        upper, fore, hand = "UpperArm" + name, "Forearm" + name, "Hand" + name
        # Slim pauldrons sloping outward.
        k.box(upper, "Armor", (1.8 * sign, 5.52, 0), (1.15, 0.12, 1.2), (0, 0, -12 * sign))
        k.box(upper, "Trim", (2.12 * sign, 5.38, 0), (0.5, 0.06, 1.0), (0, 0, -12 * sign))
        # Long blades along the forearms, reaching past the fist: the reach of the build.
        k.box(fore, "Armor", (2.12 * sign, 3.0, -0.1), (0.14, 1.9, 0.62))
        k.box(fore, "Trim", (2.2 * sign, 3.0, -0.1), (0.05, 1.5, 0.24))
        k.box(fore, "Dark", (1.9 * sign, 3.9, 0), (0.36, 0.2, 0.56))
        k.box(hand, "Armor", (2.12 * sign, 2.1, -0.1), (0.12, 0.5, 0.42))
        # Back fins.
        k.box("Chest", "Armor", (0.6 * sign, 4.95, 0.8), (0.1, 1.0, 0.4), (16, 0, 0))

    sided(side)
    # A tall blade crest, swept back, on a dark base.
    k.box("Head", "Dark", (0, 6.5, 0.05), (0.3, 0.14, 0.62))
    k.box("Head", "Trim", (0, 6.98, 0.2), (0.12, 0.8, 0.4), (-16, 0, 0))
    k.box("Chest", "Trim", (0, 4.7, -0.8), (0.1, 1.2, 0.1))


def razor():
    k = Kit("Razor")

    def side(name, sign):
        shin, fore = "Shin" + name, "Forearm" + name
        # Swept-back head blades.
        k.box("Head", "Trim", (0.62 * sign, 6.12, 0.4), (0.12, 0.6, 1.1), (-40, 0, 0))
        # Heel fins, close to the calf, and a blade on the front of the shin.
        k.box(shin, "Armor", (0.64 * sign, 1.0, 0.54), (0.56, 0.95, 0.2), (22, 0, 0))
        k.box(shin, "Trim", (0.64 * sign, 0.62, 0.7), (0.4, 0.34, 0.1), (22, 0, 0))
        k.box(shin, "Trim", (0.64 * sign, 1.2, -0.56), (0.24, 0.8, 0.12), (-18, 0, 0))
        # Back thrusters with glowing mouths, and swept wings.
        k.rod("Chest", "Dark", (0.5 * sign, 4.4, 0.78), (0.5 * sign, 5.4, 1.06), 0.56)
        k.rod("Chest", "Glow", (0.5 * sign, 5.4, 1.06), (0.5 * sign, 5.52, 1.1), 0.42)
        k.box("Chest", "Armor", (1.2 * sign, 5.0, 0.95), (1.0, 0.08, 0.85), (18, 0, -22 * sign))
        k.box("Chest", "Trim", (1.62 * sign, 4.86, 1.04), (0.4, 0.1, 0.55), (18, 0, -22 * sign))
        # Forearm edge blades.
        k.box(fore, "Armor", (1.94 * sign, 3.3, -0.22), (0.1, 1.05, 0.5), (-8, 0, 0))
        k.box(fore, "Trim", (2.0 * sign, 3.3, -0.22), (0.04, 0.8, 0.2), (-8, 0, 0))

    sided(side)
    k.box("Chest", "Trim", (0, 4.75, -0.78), (0.12, 1.1, 0.2))
    k.box("Pelvis", "Trim", (0, 3.05, -0.68), (0.14, 0.5, 0.14))


def maul():
    k = Kit("Maul")

    def side(name, sign):
        upper, hand, shin = "UpperArm" + name, "Hand" + name, "Shin" + name
        # Round pauldrons.
        k.ball(upper, "Armor", (1.8 * sign, 5.2, 0), 1.4)
        k.cyl(upper, "Trim", (1.8 * sign, 5.2, 0), 1.46, 0.1)
        # Wrecking-ball fists with studs on the striking face.
        k.ball(hand, "Armor", (1.64 * sign, 2.3, 0), 1.32)
        k.cyl(hand, "Trim", (1.64 * sign, 2.3, 0), 1.38, 0.1)
        for dx in (-0.3, 0.3):
            for dz in (-0.3, 0.3):
                k.cyl(hand, "Dark", (1.64 * sign + dx, 1.62, dz), 0.2, 0.34)
        # Knee guards.
        k.box(shin, "Armor", (0.64 * sign, 1.64, -0.54), (0.84, 0.64, 0.32))
        # Side slabs on the chest.
        k.box("Chest", "Armor", (1.0 * sign, 4.7, -0.72), (0.5, 0.95, 0.28))

    sided(side)
    # Exhaust stacks on the back, with glowing tips.
    for sign in (1, -1):
        k.rod("Chest", "Dark", (0.55 * sign, 4.2, 0.9), (0.55 * sign, 6.0, 0.9), 0.44)
        k.cyl("Chest", "Trim", (0.55 * sign, 5.5, 0.9), 0.54, 0.14)
        k.cyl("Chest", "Trim", (0.55 * sign, 4.6, 0.9), 0.54, 0.14)
        k.cyl("Chest", "Glow", (0.55 * sign, 6.02, 0.9), 0.32, 0.06)
    k.box("Pelvis", "Armor", (0, 2.82, -0.7), (1.3, 0.6, 0.16))


# --- Module kits ----------------------------------------------------------------------------------------------------


def piston_fists():
    k = Kit("PistonFists")

    def side(name, sign):
        fore, hand = "Forearm" + name, "Hand" + name
        for dx in (-0.4, 0.4):
            k.rod(fore, "Dark", ((1.6 + dx) * sign, 3.95, -0.66), ((1.6 + dx) * sign, 3.0, -0.66), 0.3)
            k.cyl(fore, "Trim", ((1.6 + dx) * sign, 3.3, -0.66), 0.38, 0.1)
        k.box(fore, "Armor", (1.6 * sign, 3.1, 0), (1.3, 0.26, 1.3))
        k.box(hand, "Armor", (1.64 * sign, 2.0, 0), (1.12, 0.22, 1.2))
        for dz in (-0.36, 0, 0.36):
            k.box(hand, "Glow", (1.64 * sign, 1.88, dz), (0.82, 0.05, 0.16))

    sided(side)


def servo_wrists():
    k = Kit("ServoWrists")

    def side(name, sign):
        fore, hand = "Forearm" + name, "Hand" + name
        k.box(fore, "Trim", (1.62 * sign, 2.95, 0), (1.22, 0.12, 1.22))
        k.rod(fore, "Dark", (0.95 * sign, 3.25, 0), (2.32 * sign, 3.25, 0), 0.5)
        k.rod(fore, "Glow", (2.32 * sign, 3.25, 0), (2.4 * sign, 3.25, 0), 0.34)
        k.box(fore, "Glow", (1.62 * sign, 3.6, -0.58), (0.34, 0.8, 0.05))
        k.box(fore, "Glow", (1.62 * sign, 3.6, 0.58), (0.34, 0.8, 0.05))
        k.box(hand, "Dark", (1.64 * sign, 2.72, 0), (0.56, 0.2, 1.1))

    sided(side)


def plating():
    k = Kit("Plating")
    for sign in (1, -1):
        k.box("Chest", "Armor", (1.3 * sign, 4.65, 0), (0.3, 1.3, 1.4))
        k.box("Chest", "Trim", (1.48 * sign, 4.65, 0), (0.05, 1.0, 0.6))
        k.box("Pelvis", "Armor", (1.15 * sign, 2.85, 0), (0.28, 0.8, 1.15))
        k.box("UpperArm" + ("R" if sign == 1 else "L"), "Armor", (1.8 * sign, 5.66, 0), (1.05, 0.18, 1.3))
    k.box("Chest", "Armor", (0, 4.7, 0.86), (1.95, 1.3, 0.28))
    k.box("Chest", "Trim", (0, 4.7, 1.02), (1.3, 0.08, 0.05))
    k.box("Pelvis", "Armor", (0, 2.85, -0.7), (1.3, 0.6, 0.16))
    k.box("Pelvis", "Trim", (0, 2.85, -0.79), (0.8, 0.06, 0.04))
    k.box("Chest", "Armor", (0, 5.55, 0), (1.5, 0.18, 1.1))


def shock_dampers():
    k = Kit("ShockDampers")
    for sign in (1, -1):
        # Hip dampers: a rod with coils.
        k.rod("Pelvis", "Dark", (1.3 * sign, 2.4, 0.3), (1.3 * sign, 3.6, 0.3), 0.26)
        k.rings("Pelvis", "Trim", 1.3 * sign, 0.3, 2.55, 3.45, 5, 0.52, 0.1)
        # Back-mounted dampers behind the shoulders.
        k.rod("Chest", "Dark", (0.95 * sign, 4.5, 0.92), (0.95 * sign, 5.8, 0.92), 0.26)
        k.rings("Chest", "Trim", 0.95 * sign, 0.92, 4.65, 5.65, 5, 0.52, 0.1)
    k.box("Chest", "Dark", (0, 5.15, 0.8), (2.1, 0.22, 0.28))


def hydraulic_boots():
    k = Kit("HydraulicBoots")

    def side(name, sign):
        shin, foot = "Shin" + name, "Foot" + name
        k.box(foot, "Armor", (0.66 * sign, 0.52, -0.22), (1.04, 0.74, 1.56))
        k.box(foot, "Trim", (0.66 * sign, 0.3, -1.0), (0.96, 0.28, 0.14))
        k.box(foot, "Dark", (0.66 * sign, 0.42, 0.68), (0.84, 0.5, 0.22))
        k.rod(shin, "Dark", (0.64 * sign, 1.95, 0.62), (0.64 * sign, 0.85, 0.64), 0.3)
        k.rings(shin, "Trim", 0.64 * sign, 0.63, 1.0, 1.8, 3, 0.42, 0.1)

    sided(side)


def spring_greaves():
    k = Kit("SpringGreaves")

    def side(name, sign):
        shin = "Shin" + name
        k.rod(shin, "Dark", (0.64 * sign, 1.8, 0.58), (0.64 * sign, 0.7, 0.58), 0.18)
        k.rings(shin, "Trim", 0.64 * sign, 0.58, 0.82, 1.7, 6, 0.64, 0.1)
        k.box("Foot" + name, "Armor", (0.66 * sign, 0.62, 0.8), (0.4, 1.0, 0.14), (-26, 0, 0))
        k.box(shin, "Dark", (0.64 * sign, 1.82, 0.58), (0.6, 0.16, 0.4))

    sided(side)


# --- Crests ----------------------------------------------------------------------------------------------------------


def crests():
    fin = Kit("CrestFin")
    fin.box("Head", "Armor", (0, 6.78, 0.1), (0.16, 0.8, 1.15))
    fin.box("Head", "Trim", (0, 7.2, 0.1), (0.2, 0.1, 1.18))

    antenna = Kit("CrestAntenna")
    for sign in (1, -1):
        antenna.rod("Head", "Dark", (0.25 * sign, 6.38, 0.1), (0.72 * sign, 7.2, 0.1), 0.12)
        antenna.ball("Head", "Glow", (0.72 * sign, 7.26, 0.1), 0.26)

    horns = Kit("CrestHorns")
    for sign in (1, -1):
        horns.box("Head", "Armor", (0.46 * sign, 6.66, 0.02), (0.24, 0.8, 0.28), (0, 0, -18 * sign))
        horns.box("Head", "Trim", (0.6 * sign, 7.08, 0.02), (0.2, 0.2, 0.24), (0, 0, -18 * sign))

    halo = Kit("CrestHalo")
    halo.cyl("Head", "Glow", (0, 7.1, 0.05), 1.6, 0.08)
    halo.rod("Head", "Dark", (0, 6.38, 0.05), (0, 7.06, 0.05), 0.12)

def build():
    KITS.clear()
    bulwark()
    lance()
    razor()
    maul()
    piston_fists()
    servo_wrists()
    plating()
    shock_dampers()
    hydraulic_boots()
    spring_greaves()
    crests()
    return KITS


# --- Luau export ----------------------------------------------------------------------------------------------------


def number(value):
    text = ("%.3f" % value).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def vector3(vector):
    return "Vector3.new(%s, %s, %s)" % tuple(number(value) for value in vector)


def luau_kits():
    lines = [
        "--!strict",
        "",
        "-- Generated by art/kits.py. Do not edit by hand.",
        "-- Add-on pieces for the robot's joints, in the same rest-pose axes as RobotRigs. rot is degrees applied as",
        "-- CFrame.fromEulerAnglesYXZ about the piece's own center; a cylinder's axis is its local Y.",
        "",
        "export type Piece = {",
        "\tjoint: string,",
        "\trole: string,",
        '\tshape: string,',
        "\tcenter: Vector3,",
        "\tsize: Vector3,",
        "\trot: Vector3,",
        "}",
        "",
        "local kits: { [string]: { Piece } } = {",
    ]
    for name in sorted(KITS):
        lines.append("\t%s = {" % name)
        for piece in KITS[name]:
            lines.append(
                '\t\t{ joint = "%s", role = "%s", shape = "%s", center = %s, size = %s, rot = %s },'
                % (
                    piece["joint"],
                    piece["role"],
                    piece["shape"],
                    vector3(piece["center"]),
                    vector3(piece["size"]),
                    vector3(piece["rot"]),
                )
            )
        lines.append("\t},")
    lines += ["}", "", "return kits", ""]
    return "\n".join(lines)


def export_luau(path):
    with open(path, "w", encoding="ascii", newline="\n") as handle:
        handle.write(luau_kits())
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--luau", default="", help="folder that gets RobotKits.luau")
    options = parser.parse_args()
    build()
    total = sum(len(pieces) for pieces in KITS.values())
    print("%d kits, %d pieces" % (len(KITS), total))
    for name in sorted(KITS):
        print("  %-15s %3d pieces" % (name, len(KITS[name])))
    if options.luau:
        print(export_luau(os.path.join(options.luau, "RobotKits.luau")))


if __name__ == "__main__":
    main()
