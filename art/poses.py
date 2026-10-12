"""ANVIL's poses and clips. Angles are degrees applied as CFrame.fromEulerAnglesYXZ(rx, ry, rz) about each joint pivot,
in the parent joint's frame (Ry * Rx * Rz: roll, then pitch, then yaw).

For a robot facing -z: +rx swings a hanging limb forward (and leans an upright part back), +ry turns the part to its
left, +rz swings a limb's lower end toward +x. `pos` shifts the pelvis. Poses are grounded after authoring so the
lowest sole point sits on y = 0, which keeps feet planted without hand-tuning heights.
"""

import math

import robotlib

SIDES = ("L", "R")


def P(pos=(0, 0, 0), ground="feet", **rot):
    return {"pos": tuple(pos), "ground": ground, "rot": {joint: tuple(angles) for joint, angles in rot.items()}}


def tweak(base, pos=None, ground="inherit", add=None, **rot):
    result = {
        "pos": tuple(pos) if pos is not None else base["pos"],
        "ground": base["ground"] if ground == "inherit" else ground,
        "rot": dict(base["rot"]),
    }
    for joint, angles in (add or {}).items():
        current = result["rot"].get(joint, (0, 0, 0))
        result["rot"][joint] = tuple(c + a for c, a in zip(current, angles))
    for joint, angles in rot.items():
        result["rot"][joint] = tuple(angles)
    return result


STANCE = P(
    pos=(0, -0.3, 0),
    Pelvis=(0, -14, 0),
    Chest=(-9, -12, 0),
    Head=(3, 24, 0),
    UpperArmL=(42, 0, -8),
    ForearmL=(100, 0, 0),
    UpperArmR=(30, 0, -5),
    ForearmR=(118, 0, 0),
    ThighL=(26, 0, -6),
    ShinL=(-42, 0, 0),
    FootL=(16, 0, 0),
    ThighR=(-10, 0, 6),
    ShinR=(-30, 0, 0),
    FootR=(25, 0, 0),
)

GUARD = tweak(
    STANCE,
    pos=(0, -0.45, 0.05),
    Pelvis=(0, -10, 0),
    Chest=(-16, -10, 0),
    Head=(10, 18, 0),
    UpperArmL=(62, 0, -14),
    ForearmL=(118, 0, 0),
    UpperArmR=(58, 0, -10),
    ForearmR=(122, 0, 0),
    ThighL=(32, 0, -8),
    ShinL=(-52, 0, 0),
    FootL=(20, 0, 0),
    ThighR=(-4, 0, 8),
    ShinR=(-40, 0, 0),
    FootR=(18, 0, 0),
)

IDLE_B = tweak(
    STANCE,
    pos=(0, -0.36, 0),
    add={"Chest": (2.5, 0, 0), "Head": (-1.5, 0, 0), "UpperArmL": (-3, 0, 0), "UpperArmR": (-2, 0, 0)},
)

JAB_CHAMBER = tweak(
    STANCE,
    pos=(0, -0.34, 0.06),
    Pelvis=(0, -18, 0),
    Chest=(-11, -20, 0),
    UpperArmL=(30, 0, -8),
    ForearmL=(122, 0, 0),
)
JAB_STRIKE = tweak(
    STANCE,
    pos=(0, -0.34, -0.55),
    Pelvis=(0, -14, 0),
    Chest=(-14, -14, 0),
    Head=(4, 30, 0),
    UpperArmL=(88, 26, -3),
    ForearmL=(3, 0, 0),
    ThighL=(38, 0, -6),
    ShinL=(-40, 0, 0),
    FootL=(2, 0, 0),
    ThighR=(-18, 0, 6),
    ShinR=(-14, 0, 0),
    FootR=(30, 0, 0),
)
JAB_HOLD = tweak(JAB_STRIKE, pos=(0, -0.34, -0.62), add={"Chest": (-2, -2, 0), "UpperArmL": (3, 0, 0)})

STRAIGHT_CHAMBER = tweak(
    STANCE,
    pos=(0, -0.42, 0.12),
    Pelvis=(0, -26, 0),
    Chest=(-12, -34, 0),
    Head=(3, 36, 0),
    UpperArmR=(26, 0, -6),
    ForearmR=(128, 0, 0),
    UpperArmL=(46, 0, -8),
    ForearmL=(110, 0, 0),
    ThighR=(-16, 0, 6),
    ShinR=(-46, 0, 0),
    FootR=(40, 0, 0),
    ThighL=(22, 0, -6),
    ShinL=(-34, 0, 0),
    FootL=(12, 0, 0),
)
STRAIGHT_STRIKE = tweak(
    STANCE,
    pos=(0, -0.4, -0.7),
    Pelvis=(0, 14, 0),
    Chest=(-16, 34, 0),
    Head=(5, -22, 0),
    UpperArmR=(86, -48, -2),
    ForearmR=(3, 0, 0),
    UpperArmL=(56, -10, -10),
    ForearmL=(120, 0, 0),
    ThighL=(34, 0, -6),
    ShinL=(-44, 0, 0),
    FootL=(8, 0, 0),
    ThighR=(-24, 0, 6),
    ShinR=(-10, 0, 0),
    FootR=(40, 0, 0),
)
STRAIGHT_HOLD = tweak(STRAIGHT_STRIKE, pos=(0, -0.4, -0.8), add={"Chest": (0, 4, 0), "UpperArmR": (3, 0, 0)})

# Snap kick: a quick front thrust with the lead (left) leg while the rear leg carries the weight.
SNAP_CHAMBER = tweak(
    STANCE,
    pos=(0, -0.34, 0.12),
    Pelvis=(0, -8, 0),
    Chest=(6, -8, 0),
    Head=(-4, 14, 0),
    UpperArmL=(48, 0, -10),
    ForearmL=(105, 0, 0),
    UpperArmR=(40, 0, -6),
    ForearmR=(115, 0, 0),
    ThighL=(74, 0, -4),
    ShinL=(-112, 0, 0),
    FootL=(24, 0, 0),
    ThighR=(-2, 0, 6),
    ShinR=(-18, 0, 0),
    FootR=(20, 0, 0),
)
SNAP_STRIKE = tweak(
    SNAP_CHAMBER,
    pos=(0, -0.34, -0.5),
    Pelvis=(0, -4, 0),
    Chest=(12, -6, 0),
    Head=(-6, 10, 0),
    UpperArmL=(35, 0, -12),
    ForearmL=(110, 0, 0),
    UpperArmR=(50, 0, -8),
    ForearmR=(112, 0, 0),
    ThighL=(86, 0, -3),
    ShinL=(-4, 0, 0),
    FootL=(-6, 0, 0),
    ThighR=(-6, 0, 6),
    ShinR=(-16, 0, 0),
    FootR=(22, 0, 0),
)
SNAP_HOLD = tweak(SNAP_STRIKE, pos=(0, -0.34, -0.58), add={"ThighL": (2, 0, 0), "Chest": (2, 0, 0)})

# Power kick: the rear (right) leg winds up with the hips turned away, then drives through with the whole body.
POWER_CHAMBER = tweak(
    STANCE,
    pos=(0, -0.5, 0.2),
    Pelvis=(0, -26, 0),
    Chest=(8, -30, 0),
    Head=(0, 44, 0),
    UpperArmL=(60, 0, -14),
    ForearmL=(112, 0, 0),
    UpperArmR=(-20, 0, 30),
    ForearmR=(60, 0, 0),
    ThighL=(10, 0, -8),
    ShinL=(-22, 0, 0),
    FootL=(12, 0, 0),
    ThighR=(70, 0, 12),
    ShinR=(-120, 0, 0),
    FootR=(30, 0, 0),
)
POWER_STRIKE = tweak(
    POWER_CHAMBER,
    pos=(0, -0.5, -0.85),
    Pelvis=(0, 12, 0),
    Chest=(22, 22, 0),
    Head=(4, -20, 0),
    UpperArmL=(40, 0, -34),
    ForearmL=(70, 0, 0),
    UpperArmR=(-30, 0, 40),
    ForearmR=(40, 0, 0),
    ThighL=(12, 0, -6),
    ShinL=(-20, 0, 0),
    FootL=(10, 0, 0),
    ThighR=(92, 0, 6),
    ShinR=(-6, 0, 0),
    FootR=(-4, 0, 0),
)
POWER_HOLD = tweak(POWER_STRIKE, pos=(0, -0.5, -0.95), add={"Chest": (2, 0, 0), "ThighR": (2, 0, 0)})

HIT_LIGHT_IMPACT = tweak(
    STANCE,
    pos=(0, -0.3, 0.2),
    add={"Chest": (9, 0, 0), "Head": (14, 0, 0), "Pelvis": (3, 0, 0)},
    UpperArmL=(34, 0, -14),
    ForearmL=(86, 0, 0),
)
HIT_LIGHT_PEAK = tweak(
    STANCE,
    pos=(0, -0.34, 0.4),
    add={"Chest": (15, 0, 6), "Head": (24, 0, 0), "Pelvis": (6, 0, 0)},
    UpperArmL=(12, 0, -26),
    ForearmL=(62, 0, 0),
    UpperArmR=(14, 0, 14),
    ForearmR=(84, 0, 0),
)
HIT_HEAVY_IMPACT = tweak(
    STANCE,
    pos=(0, -0.4, 0.4),
    add={"Chest": (16, 0, 0), "Head": (22, 0, 0), "Pelvis": (6, 0, 0)},
    UpperArmL=(22, 0, -20),
    ForearmL=(70, 0, 0),
    UpperArmR=(18, 0, 10),
    ForearmR=(84, 0, 0),
)
HIT_HEAVY_PEAK = tweak(
    STANCE,
    pos=(0, -0.6, 0.75),
    add={"Chest": (26, 0, 8), "Head": (36, 0, 0), "Pelvis": (10, 0, 0)},
    UpperArmL=(-8, 0, -40),
    ForearmL=(34, 0, 0),
    UpperArmR=(-4, 0, 36),
    ForearmR=(44, 0, 0),
    ThighL=(36, 0, -8),
    ShinL=(-62, 0, 0),
    FootL=(26, 0, 0),
)
BLOCK_RECOIL = tweak(
    GUARD, pos=(0, -0.45, 0.28), add={"Chest": (9, 0, 0), "Head": (6, 0, 0), "UpperArmL": (-6, 0, 0)}
)

KO_BUCKLE = tweak(
    HIT_HEAVY_PEAK,
    ground=False,
    pos=(0, -0.95, 0.95),
    Pelvis=(22, -4, 0),
    Chest=(24, 0, 6),
    Head=(30, 0, 0),
    UpperArmL=(10, 0, -46),
    ForearmL=(40, 0, 0),
    UpperArmR=(8, 0, 46),
    ForearmR=(40, 0, 0),
    ThighL=(50, 0, -8),
    ShinL=(-84, 0, 0),
    ThighR=(34, 0, 8),
    ShinR=(-70, 0, 0),
)
KO_FALL = tweak(
    KO_BUCKLE,
    ground="all",
    pos=(0, -1.7, 1.6),
    Pelvis=(58, 0, 0),
    Chest=(14, 0, 4),
    Head=(14, 0, 0),
    UpperArmL=(0, 0, -62),
    ForearmL=(24, 0, 0),
    UpperArmR=(0, 0, 62),
    ForearmR=(24, 0, 0),
    ThighL=(18, 0, -10),
    ShinL=(-48, 0, 0),
    ThighR=(8, 0, 10),
    ShinR=(-30, 0, 0),
)
KO_DOWN = tweak(
    KO_FALL,
    ground="all",
    pos=(0, -2.3, 2.2),
    Pelvis=(88, 0, 0),
    Chest=(0, 0, 0),
    Head=(-8, 0, 0),
    UpperArmL=(0, 0, -78),
    ForearmL=(8, 0, 0),
    UpperArmR=(0, 0, 78),
    ForearmR=(8, 0, 0),
    ThighL=(4, 0, -12),
    ShinL=(-8, 0, 0),
    FootL=(0, 0, 0),
    ThighR=(-4, 0, 14),
    ShinR=(-14, 0, 0),
    FootR=(0, 0, 0),
)
KO_SETTLE = tweak(
    KO_DOWN, add={"Head": (0, 0, 0)}, UpperArmL=(0, 0, -86), UpperArmR=(0, 0, 84), ForearmL=(2, 0, 0), ForearmR=(2, 0, 0)
)

DASH_COIL = tweak(
    STANCE,
    pos=(0, -0.55, 0),
    Chest=(-18, -12, 0),
    ThighL=(36, 0, -6),
    ShinL=(-62, 0, 0),
    FootL=(22, 0, 0),
    ThighR=(8, 0, 6),
    ShinR=(-52, 0, 0),
    FootR=(40, 0, 0),
)
DASH_F = tweak(
    STANCE,
    pos=(0, -0.3, -0.2),
    Pelvis=(-8, -14, 0),
    Chest=(-14, -12, 0),
    UpperArmL=(34, 0, -10),
    ForearmL=(112, 0, 0),
    UpperArmR=(28, 0, -6),
    ForearmR=(122, 0, 0),
    ThighL=(46, 0, -6),
    ShinL=(-62, 0, 0),
    FootL=(14, 0, 0),
    ThighR=(-36, 0, 6),
    ShinR=(-26, 0, 0),
    FootR=(44, 0, 0),
)
DASH_B = tweak(
    STANCE,
    pos=(0, -0.3, 0.2),
    Pelvis=(6, -14, 0),
    Chest=(2, -12, 0),
    ThighL=(-8, 0, -6),
    ShinL=(-34, 0, 0),
    FootL=(34, 0, 0),
    ThighR=(34, 0, 6),
    ShinR=(-54, 0, 0),
    FootR=(14, 0, 0),
)
DASH_R = tweak(
    STANCE,
    pos=(0.15, -0.3, 0),
    Pelvis=(0, -14, 6),
    Chest=(-12, -12, -10),
    ThighL=(20, 0, 26),
    ShinL=(-44, 0, 0),
    FootL=(18, 0, -26),
    ThighR=(-10, 0, -2),
    ShinR=(-42, 0, 0),
    FootR=(34, 0, 0),
)
DASH_L = tweak(
    STANCE,
    pos=(-0.15, -0.3, 0),
    Pelvis=(0, -14, -6),
    Chest=(-12, -12, 10),
    ThighL=(22, 0, -2),
    ShinL=(-44, 0, 0),
    FootL=(18, 0, 0),
    ThighR=(-8, 0, -24),
    ShinR=(-36, 0, 0),
    FootR=(28, 0, 24),
)


# Emotes. They play while a fighter stands free: the intro flex before a round, the win, and the loss on the clock.
INTRO_A = tweak(
    STANCE,
    pos=(0, -0.55, 0),
    Pelvis=(0, -8, 0),
    Chest=(-4, -8, 0),
    Head=(6, 14, 0),
    UpperArmL=(30, 0, -48),
    ForearmL=(125, 0, 0),
    UpperArmR=(30, 0, 48),
    ForearmR=(125, 0, 0),
    ThighL=(24, 0, -16),
    ShinL=(-44, 0, 0),
    FootL=(18, 0, 0),
    ThighR=(24, 0, 16),
    ShinR=(-44, 0, 0),
    FootR=(18, 0, 0),
)
INTRO_B = tweak(
    INTRO_A,
    pos=(0, -0.4, 0),
    add={"Chest": (-3, 0, 0), "UpperArmL": (10, 0, 4), "UpperArmR": (10, 0, -4), "Head": (-3, 0, 0)},
)

VICTORY_A = tweak(
    STANCE,
    pos=(0, -0.1, 0),
    Pelvis=(0, 0, 0),
    Chest=(6, 0, 0),
    Head=(8, 0, 0),
    UpperArmL=(172, 0, -24),
    ForearmL=(12, 0, 0),
    UpperArmR=(48, 0, 6),
    ForearmR=(110, 0, 0),
    ThighL=(8, 0, -8),
    ShinL=(-12, 0, 0),
    FootL=(6, 0, 0),
    ThighR=(8, 0, 8),
    ShinR=(-12, 0, 0),
    FootR=(6, 0, 0),
)
VICTORY_B = tweak(
    VICTORY_A,
    pos=(0, -0.3, 0),
    Chest=(8, 0, 0),
    UpperArmL=(48, 0, -6),
    ForearmL=(110, 0, 0),
    UpperArmR=(172, 0, 24),
    ForearmR=(12, 0, 0),
)

SLUMP = tweak(
    STANCE,
    pos=(0, -0.2, 0),
    Pelvis=(0, 0, 0),
    Chest=(-16, 0, 0),
    Head=(-22, 0, 0),
    UpperArmL=(10, 0, -8),
    ForearmL=(18, 0, 0),
    UpperArmR=(8, 0, 8),
    ForearmR=(14, 0, 0),
    ThighL=(8, 0, -6),
    ShinL=(-14, 0, 0),
    FootL=(6, 0, 0),
    ThighR=(8, 0, 6),
    ShinR=(-14, 0, 0),
    FootR=(6, 0, 0),
)


def gait(forward, side, phase):
    """A step cycle toward local direction (forward, side), sampled at phase 0-1. The arms stay in guard."""
    pose = tweak(STANCE)
    for leg, offset in (("L", 0.0), ("R", 0.5)):
        angle = 2 * math.pi * (phase + offset)
        swing = math.sin(angle)
        lift = max(0.0, math.cos(angle))
        thigh = pose["rot"]["Thigh" + leg]
        shin = pose["rot"]["Shin" + leg]
        foot = pose["rot"]["Foot" + leg]
        dthigh = forward * 18 * swing
        dshin = -26 * lift * max(abs(forward), abs(side) * 0.7)
        pose["rot"]["Thigh" + leg] = (thigh[0] + dthigh, thigh[1], thigh[2] + side * 16 * swing)
        pose["rot"]["Shin" + leg] = (shin[0] + dshin, shin[1], shin[2])
        pose["rot"]["Foot" + leg] = (foot[0] - dthigh - dshin, foot[1], foot[2] - side * 16 * swing)
    chest = pose["rot"]["Chest"]
    pose["rot"]["Chest"] = (
        chest[0],
        chest[1] + math.sin(2 * math.pi * phase) * 3 * forward,
        chest[2] + math.sin(2 * math.pi * phase) * 2 * side,
    )
    return pose


def authored():
    poses = {
        "Stance": STANCE,
        "IdleB": IDLE_B,
        "Guard": GUARD,
        "JabChamber": JAB_CHAMBER,
        "JabStrike": JAB_STRIKE,
        "JabHold": JAB_HOLD,
        "StraightChamber": STRAIGHT_CHAMBER,
        "StraightStrike": STRAIGHT_STRIKE,
        "StraightHold": STRAIGHT_HOLD,
        "SnapChamber": SNAP_CHAMBER,
        "SnapStrike": SNAP_STRIKE,
        "SnapHold": SNAP_HOLD,
        "PowerChamber": POWER_CHAMBER,
        "PowerStrike": POWER_STRIKE,
        "PowerHold": POWER_HOLD,
        "HitLightImpact": HIT_LIGHT_IMPACT,
        "HitLightPeak": HIT_LIGHT_PEAK,
        "HitHeavyImpact": HIT_HEAVY_IMPACT,
        "HitHeavyPeak": HIT_HEAVY_PEAK,
        "BlockRecoil": BLOCK_RECOIL,
        "KoBuckle": KO_BUCKLE,
        "KoFall": KO_FALL,
        "KoDown": KO_DOWN,
        "KoSettle": KO_SETTLE,
        "DashCoil": DASH_COIL,
        "DashF": DASH_F,
        "DashB": DASH_B,
        "DashL": DASH_L,
        "DashR": DASH_R,
        "IntroA": INTRO_A,
        "IntroB": INTRO_B,
        "VictoryA": VICTORY_A,
        "VictoryB": VICTORY_B,
        "Slump": SLUMP,
    }
    for name, forward, side in (("WalkF", 1, 0), ("WalkB", -1, 0), ("WalkL", 0, -1), ("WalkR", 0, 1)):
        for step in range(4):
            poses["%s%d" % (name, step)] = gait(forward, side, step / 4)
    return poses


# Keys are (u, pose, ease). u is a phase position (startup 0-1, active 1-2, recovery 2-3), normalized time, seconds, or
# loop phase, depending on kind. Ease shapes the segment that starts at the key.
def walk_clip(name):
    return {"kind": "loop", "keys": [(step / 4, "%s%d" % (name, step), "linear") for step in range(4)]}


CLIPS = {
    "Idle": {"kind": "loop", "period": 1.6, "keys": [(0, "Stance", "smooth"), (0.5, "IdleB", "smooth")]},
    "Guard": {"kind": "hold", "keys": [(0, "Guard", "linear")]},
    "Jab": {
        "kind": "phase",
        "keys": [
            (0, "Stance", "in"),
            (0.55, "JabChamber", "out"),
            (1, "JabStrike", "linear"),
            (2, "JabHold", "linear"),
            (2.08, "JabHold", "smooth"),
            (3, "Stance", "smooth"),
        ],
    },
    "Straight": {
        "kind": "phase",
        "keys": [
            (0, "Stance", "in"),
            (0.6, "StraightChamber", "out"),
            (1, "StraightStrike", "linear"),
            (2, "StraightHold", "linear"),
            (2.08, "StraightHold", "smooth"),
            (3, "Stance", "smooth"),
        ],
    },
    "SnapKick": {
        "kind": "phase",
        "keys": [
            (0, "Stance", "in"),
            (0.6, "SnapChamber", "out"),
            (1, "SnapStrike", "linear"),
            (2, "SnapHold", "linear"),
            (2.08, "SnapHold", "smooth"),
            (3, "Stance", "smooth"),
        ],
    },
    "PowerKick": {
        "kind": "phase",
        "keys": [
            (0, "Stance", "in"),
            (0.65, "PowerChamber", "out"),
            (1, "PowerStrike", "linear"),
            (2, "PowerHold", "linear"),
            (2.08, "PowerHold", "smooth"),
            (3, "Stance", "smooth"),
        ],
    },
    "HitLight": {
        "kind": "norm",
        "keys": [
            (0, "HitLightImpact", "out"),
            (0.18, "HitLightPeak", "smooth"),
            (0.55, "HitLightImpact", "smooth"),
            (1, "Stance", "smooth"),
        ],
    },
    "HitHeavy": {
        "kind": "norm",
        "keys": [
            (0, "HitHeavyImpact", "out"),
            (0.2, "HitHeavyPeak", "smooth"),
            (0.6, "HitHeavyImpact", "smooth"),
            (1, "Stance", "smooth"),
        ],
    },
    "Block": {
        "kind": "norm",
        "keys": [(0, "BlockRecoil", "out"), (0.3, "BlockRecoil", "smooth"), (1, "Guard", "smooth")],
    },
    "Ko": {
        "kind": "seconds",
        "keys": [
            (0, "HitHeavyPeak", "out"),
            (0.22, "KoBuckle", "in"),
            (0.5, "KoFall", "in"),
            (0.78, "KoDown", "out"),
            (1.2, "KoSettle", "smooth"),
        ],
    },
    "DashF": {
        "kind": "norm",
        "keys": [(0, "Stance", "out"), (0.1, "DashCoil", "out"), (0.22, "DashF", "linear"), (0.6, "DashF", "smooth"), (1, "Stance", "smooth")],
    },
    "DashB": {
        "kind": "norm",
        "keys": [(0, "Stance", "out"), (0.1, "DashCoil", "out"), (0.22, "DashB", "linear"), (0.6, "DashB", "smooth"), (1, "Stance", "smooth")],
    },
    "DashL": {
        "kind": "norm",
        "keys": [(0, "Stance", "out"), (0.1, "DashCoil", "out"), (0.22, "DashL", "linear"), (0.6, "DashL", "smooth"), (1, "Stance", "smooth")],
    },
    "DashR": {
        "kind": "norm",
        "keys": [(0, "Stance", "out"), (0.1, "DashCoil", "out"), (0.22, "DashR", "linear"), (0.6, "DashR", "smooth"), (1, "Stance", "smooth")],
    },
    "Intro": {"kind": "loop", "period": 1.3, "keys": [(0, "IntroA", "smooth"), (0.5, "IntroB", "smooth")]},
    "Victory": {"kind": "loop", "period": 1.1, "keys": [(0, "VictoryA", "smooth"), (0.5, "VictoryB", "smooth")]},
    "Slump": {"kind": "hold", "keys": [(0, "Slump", "linear")]},
    "WalkF": walk_clip("WalkF"),
    "WalkB": walk_clip("WalkB"),
    "WalkL": walk_clip("WalkL"),
    "WalkR": walk_clip("WalkR"),
}


def finalize(robot):
    """The authored poses with feet (or the whole body, for a fallen robot) resting on the ground."""
    result = {}
    for name, pose in authored().items():
        grounding = pose["ground"]
        result[name] = robotlib.grounded(robot, pose, grounding) if grounding else pose
    return result
