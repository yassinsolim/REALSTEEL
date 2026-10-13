"""The robots' add-on kits: the crests, a cosmetic choice for the head, which sit on the shared skeleton's joints and so
fit every frame. (Each chassis' look is its own frame now; see build_robot.FRAMES.)

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

KITS = {}
CRESTS = ("CrestFin", "CrestAntenna", "CrestHorns", "CrestHalo", "CrestCrown", "CrestMohawk")


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

    # Bought with coins (see Shop.luau).
    crown = Kit("CrestCrown")
    crown.cyl("Head", "Trim", (0, 6.38, 0.08), 0.92, 0.16)
    crown.cyl("Head", "Dark", (0, 6.48, 0.08), 0.78, 0.06)
    for index in range(5):
        # Five points around the band, one at the front, each leaning out a little and tipped with a gem.
        angle = math.pi / 2 + 2 * math.pi * index / 5
        x = 0.38 * math.cos(angle)
        z = 0.08 - 0.38 * math.sin(angle)
        crown.box("Head", "Trim", (x, 6.66, z), (0.16, 0.46, 0.16), (-12 * math.sin(angle), 0, 12 * math.cos(angle)))
        crown.ball("Head", "Glow", (1.12 * x, 6.94, 0.08 + 1.12 * (z - 0.08)), 0.16)

    mohawk = Kit("CrestMohawk")
    for z, height in ((-0.3, 0.46), (-0.06, 0.62), (0.18, 0.68), (0.42, 0.54)):
        # Blades front to back, swept back, a glowing edge along each.
        mohawk.box("Head", "Armor", (0, 6.34 + height / 2, z), (0.16, height, 0.26), (-24, 0, 0))
        mohawk.box("Head", "Glow", (0, 6.36 + height / 2, z - 0.14), (0.1, height * 0.8, 0.04), (-24, 0, 0))


def build():
    KITS.clear()
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
