"""The skeleton every REALSTEEL robot frame is built on: ANVIL's joints and pivots. Frames share it so they all play the
same animations (art/poses.py) and the game poses them alike; only their armor differs.
"""

SIDES = (("R", 1), ("L", -1))


def add_joints(robot):
    """ANVIL's joints, parents before children, pivots at the rest-pose joint centers (Roblox axes, studs)."""
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
