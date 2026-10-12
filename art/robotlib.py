"""Geometry and rig helpers for REALSTEEL's procedural robots (Blender 5, run headless by scripts/art.ps1).

Everything is authored in Roblox axes and studs: x is the robot's right, y is up, and the robot faces -z. Rig data,
poses and the Luau runtime share that one coordinate system. Blender is Z-up, so meshes are converted when they are
created; the FBX exporter converts them back (see exporters.export_fbx for the axis and scale settings Roblox needs).
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

# Roblox (x, y, z) -> Blender (-x, z, y): a robot facing Roblox -z faces Blender -y, the usual front, and Roblox
# imports an FBX from Blender back to (-x, z, y) again. A proper rotation, so face winding is kept.
BASIS = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def to_blender(point):
    return Vector((-point[0], point[2], point[1]))


def to_roblox(point):
    return Vector((-point[0], point[2], point[1]))


class Joint:
    def __init__(self, name, parent, pivot):
        self.name = name
        self.parent = parent
        self.pivot = Vector(pivot)


class Part:
    """One mesh: the geometry of a single joint in a single material role."""

    def __init__(self, name, joint, role, center, size, obj, triangles):
        self.name = name
        self.joint = joint
        self.role = role
        self.center = center
        self.size = size
        self.obj = obj
        self.triangles = triangles


class PartBuilder:
    """Accumulates primitives for one (joint, role) pair, in Roblox axes."""

    def __init__(self, name, joint, role):
        self.name = name
        self.joint = joint
        self.role = role
        self.bm = bmesh.new()

    def _merge(self, other):
        other.verts.index_update()
        copies = [self.bm.verts.new(vert.co) for vert in other.verts]
        for face in other.faces:
            self.bm.faces.new([copies[vert.index] for vert in face.verts])
        other.free()

    @staticmethod
    def _bevel(bm, amount, segments):
        if amount > 0:
            bmesh.ops.bevel(
                bm,
                geom=bm.edges[:],
                offset=amount,
                segments=segments,
                profile=0.5,
                affect="EDGES",
                clamp_overlap=True,
            )

    def _rotate(self, bm, center, rot):
        """Turns freshly made geometry about its center by rot (degrees, as in rotation_matrix), for angled plates."""
        if rot is not None:
            pivot = Vector(center)
            turn = Matrix.Translation(pivot) @ rotation_matrix(rot) @ Matrix.Translation(-pivot)
            bmesh.ops.transform(bm, matrix=turn, verts=bm.verts[:])

    def box(self, center, size, bevel=0.05, segments=2, rot=None):
        tmp = bmesh.new()
        bmesh.ops.create_cube(tmp, size=1.0)
        for vert in tmp.verts:
            vert.co = Vector((vert.co.x * size[0], vert.co.y * size[1], vert.co.z * size[2])) + Vector(center)
        self._bevel(tmp, min(bevel, min(size) * 0.45), segments)
        self._rotate(tmp, center, rot)
        self._merge(tmp)

    def taper(self, center, height, bottom, top, shift=(0, 0), bevel=0.05, segments=2, rot=None):
        """A block whose bottom face is bottom=(width, depth) and top face top=(width, depth), top shifted by shift."""
        tmp = bmesh.new()
        cx, cy, cz = center
        low = cy - height / 2
        high = cy + height / 2
        corners = []
        for (width, depth), y, dx, dz in ((bottom, low, 0, 0), (top, high, shift[0], shift[1])):
            for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                corners.append(tmp.verts.new(Vector((cx + dx + sx * width / 2, y, cz + dz + sz * depth / 2))))
        low_ring = corners[:4]
        high_ring = corners[4:]
        tmp.faces.new(low_ring)
        tmp.faces.new(high_ring)
        for index in range(4):
            nxt = (index + 1) % 4
            tmp.faces.new((low_ring[index], low_ring[nxt], high_ring[nxt], high_ring[index]))
        bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces[:])
        self._bevel(tmp, min(bevel, height * 0.45, min(bottom) * 0.45, min(top) * 0.45), segments)
        self._rotate(tmp, center, rot)
        self._merge(tmp)

    def cylinder(self, start, end, radius, radius_end=None, segments=12, bevel=0.0):
        start = Vector(start)
        end = Vector(end)
        axis = end - start
        tmp = bmesh.new()
        bmesh.ops.create_cone(
            tmp,
            cap_ends=True,
            cap_tris=False,
            segments=segments,
            radius1=radius,
            radius2=radius if radius_end is None else radius_end,
            depth=axis.length,
        )
        up = "X" if abs(axis.normalized().y) > 0.99 else "Y"
        rotation = axis.to_track_quat("Z", up).to_matrix().to_4x4()
        bmesh.ops.transform(tmp, matrix=Matrix.Translation((start + end) / 2) @ rotation, verts=tmp.verts[:])
        if bevel > 0:
            self._bevel(tmp, min(bevel, radius * 0.4), 1)
        self._merge(tmp)

    def sphere(self, center, radius, scale=(1, 1, 1), subdivisions=2):
        tmp = bmesh.new()
        bmesh.ops.create_icosphere(tmp, subdivisions=subdivisions, radius=radius)
        for vert in tmp.verts:
            vert.co = Vector((vert.co.x * scale[0], vert.co.y * scale[1], vert.co.z * scale[2])) + Vector(center)
        self._merge(tmp)

    def finish(self, smooth=False):
        bm = self.bm
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        low = Vector([min(vert.co[axis] for vert in bm.verts) for axis in range(3)])
        high = Vector([max(vert.co[axis] for vert in bm.verts) for axis in range(3)])
        center = (low + high) / 2
        for vert in bm.verts:
            vert.co = to_blender(vert.co - center)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        triangles = len(bm.faces)
        bm.free()
        for polygon in mesh.polygons:
            polygon.use_smooth = False
        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = to_blender(center)
        bpy.context.scene.collection.objects.link(obj)
        if smooth:
            _smooth_bevels(obj)
        return Part(self.name, self.joint, self.role, center, high - low, obj, triangles)


# Edges sharper than this stay sharp when a robot is shaded smoothly.
SHARP_ANGLE = math.radians(36)


def _smooth_bevels(obj):
    """Shades rounded edges smoothly and keeps big faces flat: smooth shading with the sharp edges kept, and normals
    weighted by face area, so a bevel catches the light like a machined edge instead of showing its facets."""
    mesh = obj.data
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    mesh.set_sharp_from_angle(angle=SHARP_ANGLE)
    modifier = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    modifier.mode = "FACE_AREA"
    modifier.weight = 50
    modifier.keep_sharp = True
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


class Robot:
    def __init__(self, name, smooth=False):
        self.name = name
        self.smooth = smooth
        self.joints = []
        self.parts = []
        self._builders = {}

    def joint(self, name, parent, pivot):
        self.joints.append(Joint(name, parent, pivot))

    def part(self, joint, role):
        """The builder for a joint and role, created on first use. Parts are named <Joint>_<Role>."""
        key = (joint, role)
        if key not in self._builders:
            self._builders[key] = PartBuilder("%s_%s" % (joint, role), joint, role)
        return self._builders[key]

    def finish(self):
        self.parts = [builder.finish(self.smooth) for builder in self._builders.values()]
        self._builders = {}

    def joint_map(self):
        return {joint.name: joint for joint in self.joints}


def rotation_matrix(euler_degrees):
    """CFrame.fromEulerAnglesYXZ(rx, ry, rz): Ry * Rx * Rz, so a vector is rolled about z first, then pitched, then yawed."""
    rx, ry, rz = (math.radians(angle) for angle in euler_degrees)
    return Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(rz, 4, "Z")


def solve(robot, pose):
    """Joint world matrices (Roblox axes) for a pose: {'pos': (x, y, z), 'rot': {joint: (rx, ry, rz) degrees}}."""
    joints = robot.joint_map()
    world = {}
    for joint in robot.joints:
        rotation = rotation_matrix(pose.get("rot", {}).get(joint.name, (0, 0, 0)))
        if joint.parent is None:
            local = Matrix.Translation(joint.pivot + Vector(pose.get("pos", (0, 0, 0))))
            world[joint.name] = local @ rotation
        else:
            local = Matrix.Translation(joint.pivot - joints[joint.parent].pivot)
            world[joint.name] = world[joint.parent] @ local @ rotation
    return world


def part_matrix(robot, world, part):
    pivot = robot.joint_map()[part.joint].pivot
    return world[part.joint] @ Matrix.Translation(part.center - pivot)


def world_vertices(robot, pose, joints, roles=None):
    """Every vertex of the parts on the given joints, in Roblox axes, for a pose."""
    world = solve(robot, pose)
    for part in robot.parts:
        if part.joint in joints and (roles is None or part.role in roles):
            matrix = part_matrix(robot, world, part)
            for vertex in part.obj.data.vertices:
                yield matrix @ to_roblox(vertex.co)


def grounded(robot, pose, mode="feet"):
    """The pose shifted vertically so its lowest point rests on y = 0: the soles ("feet") or any part ("all")."""
    joints = ("FootL", "FootR") if mode == "feet" else tuple(joint.name for joint in robot.joints)
    roles = ("Dark",) if mode == "feet" else None
    low = min(point.y for point in world_vertices(robot, pose, joints, roles))
    result = dict(pose)
    x, y, z = pose.get("pos", (0, 0, 0))
    result["pos"] = (x, y - low, z)
    return result


def front_extent(robot, pose, joint):
    """How far in front of the root (along -z) the joint's geometry reaches."""
    return max(-point.z for point in world_vertices(robot, pose, (joint,)))