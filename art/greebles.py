"""Hard-surface details the robot frames share: hydraulic pistons, cable runs, rivet rows and vent slats. Each takes the
part builders to draw into (see robotlib.Robot.part), so a detail lands on the joint and material role it belongs to.
"""

from mathutils import Vector

from robotlib import rotation_matrix


def place(center, rot, offset):
    """Where a point `offset` from a plate's center ends up once the plate is turned by rot about that center, so trim and
    rivets can be seated on angled plates."""
    return tuple(Vector(center) + rotation_matrix(rot).to_3x3() @ Vector(offset))


def piston(housing, rod, start, end, radius, split=0.55, segments=10):
    """A hydraulic piston from start to end: a housing for the first `split` of the way with a collar where the thinner,
    polished rod comes out."""
    start = Vector(start)
    end = Vector(end)
    axis = (end - start).normalized()
    middle = start.lerp(end, split)
    housing.cylinder(start, middle, radius, segments=segments)
    housing.cylinder(middle - axis * 0.05, middle + axis * 0.05, radius * 1.22, segments=segments)
    rod.cylinder(middle, end, radius * 0.5, segments=8)
    rod.cylinder(end - axis * 0.06, end + axis * 0.02, radius * 0.85, segments=8)


def cables(builder, start, end, offsets, radius=0.04, segments=6):
    """Parallel cables from start to end, one for each offset (a shift applied to both ends)."""
    for offset in offsets:
        shift = Vector(offset)
        builder.cylinder(Vector(start) + shift, Vector(end) + shift, radius, segments=segments)


def rivets(builder, start, end, count, normal, radius=0.045, height=0.035):
    """A row of `count` rivet heads from start to end, standing `height` proud of the surface along `normal`."""
    start = Vector(start)
    end = Vector(end)
    out = Vector(normal).normalized()
    for index in range(count):
        point = start.lerp(end, index / (count - 1)) if count > 1 else start.lerp(end, 0.5)
        builder.cylinder(point - out * 0.02, point + out * height, radius, segments=6)


def vents(builder, center, size, count, gap=0.05):
    """`count` horizontal slats stacked in a block of `size` (width, height, depth) around center."""
    width, height, depth = size
    slat = (height - gap * (count - 1)) / count
    bottom = center[1] - height / 2 + slat / 2
    for index in range(count):
        y = bottom + index * (slat + gap)
        builder.box((center[0], y, center[2]), (width, slat, depth), bevel=0.01, segments=1)
