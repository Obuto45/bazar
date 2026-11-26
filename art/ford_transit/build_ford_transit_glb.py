#!/usr/bin/env python3
"""
Procedural glTF 2.0 (.glb) generator for a game-ready Ford Transit Mk8
single-cab flatbed truck ("GARDAŞLAR SEBZE MEYVE") tailored for Godot 4 VehicleBody3D.

Coordinate convention:
- Units: meters
- +Y = Up, ground plane at Y = 0
- +Z = Forward (Godot 4 VehicleBody3D forward axis)
- +X = Vehicle Left (right-handed system)

Exports:
- assets/models/ford_transit_complete.glb
- assets/models/ford_transit_chassis.glb
- assets/models/wheel_front.glb
- assets/models/wheel_rear.glb
- preview_renders.png (4-angle shaded software render for verification)
"""

import json
import math
import os
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS_DIR = ROOT / "assets" / "models"
TEX_PATH = ROOT / "assets" / "textures" / "rear_banner.png"
PREVIEW_PATH = ROOT / "preview_renders.png"

WHEEL_RADIUS = 0.37
FRONT_Z = 1.82
REAR_Z = -1.78
FRONT_X = 0.86
REAR_X = 0.82


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def v_norm(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if l < 1e-9:
        return (0.0, 1.0, 0.0)
    return (v[0] / l, v[1] / l, v[2] / l)


def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


class MeshBuilder:
    """Collects geometry bucketed by material name."""

    def __init__(self):
        self.buckets = {}  # mat_name -> {pos:[], norm:[], uv:[], idx:[]}

    def _bucket(self, mat):
        if mat not in self.buckets:
            self.buckets[mat] = {"pos": [], "norm": [], "uv": [], "idx": []}
        return self.buckets[mat]

    def add_quad(self, mat, p0, p1, p2, p3, uvs=None):
        """Add CCW quad (p0, p1, p2, p3) with flat outward normal."""
        b = self._bucket(mat)
        n = v_norm(v_cross(v_sub(p1, p0), v_sub(p2, p0)))
        if uvs is None:
            uvs = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
        base = len(b["pos"])
        for p, uv in zip((p0, p1, p2, p3), uvs):
            b["pos"].append(p)
            b["norm"].append(n)
            b["uv"].append(uv)
        b["idx"].extend([base, base + 1, base + 2, base, base + 2, base + 3])

    def add_tri(self, mat, p0, p1, p2, uvs=None):
        b = self._bucket(mat)
        n = v_norm(v_cross(v_sub(p1, p0), v_sub(p2, p0)))
        if uvs is None:
            uvs = [(0.0, 0.0), (1.0, 0.0), (0.5, 1.0)]
        base = len(b["pos"])
        for p, uv in zip((p0, p1, p2), uvs):
            b["pos"].append(p)
            b["norm"].append(n)
            b["uv"].append(uv)
        b["idx"].extend([base, base + 1, base + 2])

    def add_box(self, mat, x0, x1, y0, y1, z0, z1):
        """Axis-aligned box with verified outward CCW faces (right-handed Y-up)."""
        if x0 > x1:
            x0, x1 = x1, x0
        if y0 > y1:
            y0, y1 = y1, y0
        if z0 > z1:
            z0, z1 = z1, z0
        # +Z front: normal (0, 0, +1)
        self.add_quad(mat, (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))
        # -Z rear: normal (0, 0, -1)
        self.add_quad(mat, (x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0))
        # +X left: normal (+1, 0, 0)
        self.add_quad(mat, (x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1))
        # -X right: normal (-1, 0, 0)
        self.add_quad(mat, (x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0))
        # +Y top: normal (0, +1, 0)
        self.add_quad(mat, (x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0))
        # -Y bottom: normal (0, -1, 0)
        self.add_quad(mat, (x0, y0, z1), (x0, y0, z0), (x1, y0, z0), (x1, y0, z1))

    def add_prism_x(self, mat, x0, x1, yz_loop):
        """
        Extrude a 2D polygon in (y, z) plane along X from x0 to x1.
        yz_loop must be ordered CCW when viewed from +X looking toward -X
        (i.e. +Z right, +Y up in side view -> actually from +X looking toward origin,
        right is -Z and up is +Y, so we compute signed area and normalize automatically!).
        """
        # Signed area in (z, y): if > 0 then CCW in (z, y) plane -> outward normal is -X.
        # Compute 2D shoelace in (z, y)
        area = 0.0
        n_pts = len(yz_loop)
        for i in range(n_pts):
            y_a, z_a = yz_loop[i]
            y_b, z_b = yz_loop[(i + 1) % n_pts]
            area += z_a * y_b - z_b * y_a
        pts = list(yz_loop)
        if area < 0:
            pts.reverse()
        # Now pts is CCW in (z, y), meaning when looking from -X toward +X (right=+Z, up=+Y),
        # pts is CCW! Let's verify cross product:
        # e1 = (0, dy1, dz1), e2 = (0, dy2, dz2) -> e1 x e2 = (dy1*dz2 - dz1*dy2, 0, 0).
        # With z*y area > 0, dz1*dy2 - dy1*dz2 > 0 -> cross.x < 0 (points -X!).
        # So -X cap uses pts in forward order (fan from 0), +X cap uses reversed order!
        if x0 > x1:
            x0, x1 = x1, x0
        # Side quads
        for i in range(n_pts):
            ya, za = pts[i]
            yb, zb = pts[(i + 1) % n_pts]
            # Check outward normal of side: (x1-x0,0,0) x (0, yb-ya, zb-za) = (0, -(x1-x0)*(zb-za), (x1-x0)*(yb-ya))
            # For CCW in (z, y), tangent is (dz, dy), outward normal in (z, y) is (dy, -dz) -> (0, -dz, dy)!
            # So quad (p_a0, p_a1, p_b1, p_b0) has e1=(dx,0,0), e2=(0,dy,dz) -> normal=(0, -dx*dz, dx*dy) -> OUTWARD!
            self.add_quad(
                mat,
                (x0, ya, za),
                (x1, ya, za),
                (x1, yb, zb),
                (x0, yb, zb),
            )
        # Caps (fan triangulation - safe for convex/star-convex cab profiles)
        cy = sum(p[0] for p in pts) / n_pts
        cz = sum(p[1] for p in pts) / n_pts
        for i in range(n_pts):
            ya, za = pts[i]
            yb, zb = pts[(i + 1) % n_pts]
            # -X cap at x0 (outward -X)
            self.add_tri(mat, (x0, cy, cz), (x0, ya, za), (x0, yb, zb))
            # +X cap at x1 (outward +X)
            self.add_tri(mat, (x1, cy, cz), (x1, yb, zb), (x1, ya, za))

    def add_cylinder_x(self, mat, x0, x1, cy, cz, r, segments=24, cap0=True, cap1=True):
        """Cylinder aligned along X axis (wheels, axles, lights)."""
        if x0 > x1:
            x0, x1 = x1, x0
        b = self._bucket(mat)
        ring = []
        for i in range(segments):
            ang = 2.0 * math.pi * i / segments
            ring.append((math.sin(ang), math.cos(ang)))
        # Side faces (smooth normals radially)
        for i in range(segments):
            s0, c0 = ring[i]
            s1, c1 = ring[(i + 1) % segments]
            p00 = (x0, cy + r * s0, cz + r * c0)
            p10 = (x1, cy + r * s0, cz + r * c0)
            p11 = (x1, cy + r * s1, cz + r * c1)
            p01 = (x0, cy + r * s1, cz + r * c1)
            n0 = (0.0, s0, c0)
            n1 = (0.0, s1, c1)
            # Verify winding: e1=(dx,0,0), e2=(0, r*(s1-s0), r*(c1-c0))
            # e1 x e2 = (0, -dx*r*(c1-c0), dx*r*(s1-s0))
            # For small dtheta > 0: c1-c0 ~ -s*dtheta, s1-s0 ~ c*dtheta
            # So e1 x e2 ~ (0, +s, +c) -> OUTWARD!
            base = len(b["pos"])
            for p, n, uv in (
                (p00, n0, (0.0, i / segments)),
                (p10, n0, (1.0, i / segments)),
                (p11, n1, (1.0, (i + 1) / segments)),
                (p01, n1, (0.0, (i + 1) / segments)),
            ):
                b["pos"].append(p)
                b["norm"].append(n)
                b["uv"].append(uv)
            b["idx"].extend([base, base + 1, base + 2, base, base + 2, base + 3])
        if cap0:
            for i in range(segments):
                s0, c0 = ring[i]
                s1, c1 = ring[(i + 1) % segments]
                # Outward -X: (c, s) increases angle -> (p0 - center) x (p1 - center) has x = r^2*(s0*c1 - c0*s1) = -r^2*sin(dtheta) < 0 -> OUTWARD -X!
                self.add_tri(
                    mat,
                    (x0, cy, cz),
                    (x0, cy + r * s0, cz + r * c0),
                    (x0, cy + r * s1, cz + r * c1),
                )
        if cap1:
            for i in range(segments):
                s0, c0 = ring[i]
                s1, c1 = ring[(i + 1) % segments]
                self.add_tri(
                    mat,
                    (x1, cy, cz),
                    (x1, cy + r * s1, cz + r * c1),
                    (x1, cy + r * s0, cz + r * c0),
                )

    def add_tapered_frustum_x(self, mat, x0, x1, cy, cz, r0, r1, segments=24):
        """Truncated cone along X for tire sidewalls and rim dish."""
        if x0 > x1:
            x0, x1 = x1, x0
            r0, r1 = r1, r0
        ring = []
        for i in range(segments):
            ang = 2.0 * math.pi * i / segments
            ring.append((math.sin(ang), math.cos(ang)))
        for i in range(segments):
            s0, c0 = ring[i]
            s1, c1 = ring[(i + 1) % segments]
            p00 = (x0, cy + r0 * s0, cz + r0 * c0)
            p10 = (x1, cy + r1 * s0, cz + r1 * c0)
            p11 = (x1, cy + r1 * s1, cz + r1 * c1)
            p01 = (x0, cy + r0 * s1, cz + r0 * c1)
            self.add_quad(mat, p00, p10, p11, p01)


def build_wheel_mesh(dually=False):
    """Build wheel centered at local (0,0,0), rolling axis X, radius WHEEL_RADIUS."""
    mb = MeshBuilder()
    r = WHEEL_RADIUS
    r_side = r * 0.94
    r_rim = r * 0.56
    r_hub = r * 0.25

    def add_single_tire(x_center, width):
        hw = width * 0.5
        tread_hw = hw * 0.78
        # Main tread
        mb.add_cylinder_x("tire_rubber", x_center - tread_hw, x_center + tread_hw, 0.0, 0.0, r, 24, False, False)
        # Beveled shoulders
        mb.add_tapered_frustum_x("tire_rubber", x_center - hw, x_center - tread_hw, 0.0, 0.0, r_side, r, 24)
        mb.add_tapered_frustum_x("tire_rubber", x_center + tread_hw, x_center + hw, 0.0, 0.0, r, r_side, 24)
        # Sidewall faces down to rim
        mb.add_cylinder_x("tire_rubber", x_center - hw, x_center + hw, 0.0, 0.0, r_side, 24, True, True)

    if not dually:
        # Front single commercial tire (22cm wide)
        add_single_tire(0.0, 0.22)
        # Steel wheel rim + Transit hubcap
        mb.add_cylinder_x("rim_silver", -0.115, 0.115, 0.0, 0.0, r_rim, 20, True, True)
        mb.add_cylinder_x("chrome", -0.125, 0.125, 0.0, 0.0, r_hub, 16, True, True)
        # Decorative lug studs around both faces
        for side in (-0.12, 0.12):
            for i in range(6):
                a = i * math.pi / 3.0
                ly = math.sin(a) * (r_rim * 0.62)
                lz = math.cos(a) * (r_rim * 0.62)
                mb.add_box("dark_trim", side - 0.01, side + 0.01, ly - 0.016, ly + 0.016, lz - 0.016, lz + 0.016)
    else:
        # Rear heavy-duty dually tire pair (matching Ford Transit 350/470 flatbed)
        add_single_tire(-0.115, 0.19)
        add_single_tire(0.115, 0.19)
        # Deep-dish steel rim & heavy axle hub
        mb.add_cylinder_x("rim_silver", -0.215, 0.215, 0.0, 0.0, r_rim, 20, True, True)
        mb.add_cylinder_x("dark_trim", -0.225, 0.225, 0.0, 0.0, r_hub * 0.9, 16, True, True)
        for side in (-0.22, 0.22):
            for i in range(8):
                a = i * math.pi / 4.0
                ly = math.sin(a) * (r_rim * 0.68)
                lz = math.cos(a) * (r_rim * 0.68)
                mb.add_box("dark_trim", side - 0.01, side + 0.01, ly - 0.016, ly + 0.016, lz - 0.016, lz + 0.016)
    return mb


def build_chassis_mesh():
    """Build Ford Transit Mk8 Single-Cab + Turkish ribbed aluminum flatbed cargo box."""
    mb = MeshBuilder()

    # =========================================================================
    # 1. LADDER CHASSIS FRAME & AXLES
    # =========================================================================
    for sx in (-0.42, 0.42):
        mb.add_box("chassis_dark", sx - 0.06, sx + 0.06, 0.46, 0.66, -2.85, 2.75)
    for cz in (-2.70, -1.78, -0.60, 0.60, 1.82, 2.65):
        mb.add_box("chassis_dark", -0.48, 0.48, 0.48, 0.62, cz - 0.06, cz + 0.06)
    # Rear & front axle tubes
    mb.add_cylinder_x("chassis_dark", -0.82, 0.82, WHEEL_RADIUS, REAR_Z, 0.065, 12)
    mb.add_cylinder_x("chassis_dark", -0.78, 0.78, WHEEL_RADIUS, FRONT_Z, 0.055, 12)
    # Rear differential pumpkin
    mb.add_box("chassis_dark", -0.14, 0.14, WHEEL_RADIUS - 0.12, WHEEL_RADIUS + 0.12, REAR_Z - 0.14, REAR_Z + 0.14)

    # =========================================================================
    # 2. FORD TRANSIT MK8 SINGLE CAB (White paint, z = 0.78 .. 3.00)
    # =========================================================================
    # Main sculpted side profile of Transit cab (y, z) extruded along X = -0.97 .. +0.97
    cab_profile = [
        (0.56, 0.80),   # rear lower cab corner
        (2.30, 0.80),   # rear upper cab roof corner
        (2.33, 1.62),   # front roof header above windshield
        (1.48, 2.26),   # base of windshield (steep Transit rake!)
        (1.22, 2.94),   # front nose top edge
        (0.80, 2.98),   # above front bumper
        (0.56, 2.86),   # lower nose
    ]
    mb.add_prism_x("cab_white", -0.97, 0.97, cab_profile)

    # Slight cab roof crown
    mb.add_prism_x("cab_white", -0.86, 0.86, [
        (2.30, 0.84),
        (2.37, 0.95),
        (2.38, 1.56),
        (2.32, 1.64),
    ])

    # Lower cab sill & door skirt (white middle + dark grey Transit lower cladding)
    mb.add_box("cab_white", -0.98, 0.98, 0.56, 0.84, 0.80, 1.38)
    mb.add_box("dark_trim", -0.995, 0.995, 0.42, 0.58, 0.80, 1.40)

    # Front bumper (matte dark charcoal wrap-around Transit Mk8 bumper)
    mb.add_box("dark_trim", -0.98, 0.98, 0.36, 0.82, 2.74, 3.04)
    # Bumper corner chamfers
    for side in (-1, 1):
        x_in = side * 0.90
        x_out = side * 1.00
        mb.add_box("dark_trim", x_in, x_out, 0.38, 0.80, 2.24, 2.96)
        # Front wheel arch flare (black plastic arch around FRONT_Z)
        mb.add_box("dark_trim", side * 0.94, side * 1.02, 0.78, 0.89, FRONT_Z - 0.42, FRONT_Z + 0.42)
        mb.add_box("dark_trim", side * 0.94, side * 1.02, 0.42, 0.84, FRONT_Z - 0.47, FRONT_Z - 0.36)
        mb.add_box("dark_trim", side * 0.94, side * 1.02, 0.42, 0.84, FRONT_Z + 0.36, FRONT_Z + 0.47)
        # Side orange turn-marker on door trim
        mb.add_box("amber_light", side * 0.99, side * 1.01, 0.48, 0.53, 1.15, 1.24)

    # Front hexagonal Transit grille (matte black outer + 3 horizontal bars)
    mb.add_box("grille_black", -0.52, 0.52, 0.78, 1.20, 2.95, 3.025)
    for gy in (0.86, 0.98, 1.10):
        mb.add_box("dark_trim", -0.48, 0.48, gy - 0.022, gy + 0.022, 3.01, 3.045)
    # Blue oval Ford-style badge centered in grille
    mb.add_box("ford_blue", -0.11, 0.11, 0.96, 1.05, 3.03, 3.055)
    mb.add_box("chrome", -0.125, 0.125, 0.95, 1.06, 3.025, 3.045)

    # Lower bumper air intake & license plate recess
    mb.add_box("grille_black", -0.46, 0.46, 0.42, 0.56, 3.02, 3.05)
    mb.add_box("cab_white", -0.26, 0.26, 0.58, 0.69, 3.035, 3.055)  # front license plate blank
    mb.add_box("ford_blue", 0.20, 0.26, 0.58, 0.69, 3.04, 3.06)     # TR blue plate band

    # Fog lights recessed in bumper corners (warm glowing)
    for side in (-1, 1):
        mb.add_box("grille_black", side * 0.62, side * 0.86, 0.47, 0.59, 3.02, 3.05)
        mb.add_box("headlight_glow", side * 0.65, side * 0.83, 0.49, 0.56, 3.035, 3.06)

    # Swept-back Transit headlights (outer crystal + LED DRL strip)
    for side in (-1, 1):
        mb.add_box("headlight_glow", side * 0.56, side * 0.94, 0.92, 1.16, 2.74, 3.00)
        mb.add_box("chrome", side * 0.55, side * 0.95, 0.90, 0.93, 2.76, 3.01)
        mb.add_box("dark_trim", side * 0.55, side * 0.95, 1.15, 1.18, 2.72, 2.99)

    # Windshield (dark glossy tinted glass slightly proud of front rake, outward +Y/+Z normal)
    mb.add_quad(
        "glass_dark",
        (-0.85, 1.50, 2.278),
        (0.85, 1.50, 2.278),
        (0.81, 2.25, 1.708),
        (-0.81, 2.25, 1.708),
    )
    # Windshield surround black trim + cowl & dual black wipers
    mb.add_box("dark_trim", -0.88, 0.88, 1.44, 1.51, 2.22, 2.34)
    for wx in (-0.36, 0.22):
        mb.add_box("grille_black", wx, wx + 0.48, 1.52, 1.56, 2.24, 2.30)

    # Side cab windows + B-pillar trim + door handles + large commercial dual-pane mirrors
    for side in (-1, 1):
        xs = side * 0.978
        # Side window polygon (outward +X for side=+1, outward -X for side=-1)
        p_front_bot = (xs, 1.38, 1.98)
        p_rear_bot = (xs, 1.38, 0.98)
        p_rear_top = (xs, 2.18, 0.98)
        p_front_top = (xs, 2.18, 1.62)
        if side > 0:
            mb.add_quad("glass_dark", p_front_bot, p_rear_bot, p_rear_top, p_front_top)
        else:
            mb.add_quad("glass_dark", p_rear_bot, p_front_bot, p_front_top, p_rear_top)

        # Black triangular mirror gusset at front lower window corner
        mb.add_box("dark_trim", side * 0.95, side * 1.01, 1.36, 1.64, 1.88, 2.10)
        # Mirror arm
        mb.add_box("dark_trim", side * 0.98, side * 1.16, 1.44, 1.52, 1.86, 1.94)
        # Tall dual-pane Transit side mirror housing
        mb.add_box("dark_trim", side * 1.10, side * 1.24, 1.40, 1.86, 1.80, 1.96)
        mb.add_box("amber_light", side * 1.14, side * 1.25, 1.56, 1.61, 1.94, 1.97)
        # Mirror reflective glass (facing -Z)
        mx0 = min(side * 1.11, side * 1.23)
        mx1 = max(side * 1.11, side * 1.23)
        mb.add_quad(
            "chrome",
            (mx1, 1.43, 1.795),
            (mx0, 1.43, 1.795),
            (mx0, 1.83, 1.795),
            (mx1, 1.83, 1.795),
        )
        # Vertical door handle
        mb.add_box("dark_trim", side * 0.96, side * 1.01, 1.10, 1.24, 1.02, 1.08)

    # =========================================================================
    # 3. TURKISH HIGH RIBBED METAL CARGO BOX ("AÇIK HAL KASASI")
    # z = -2.95 .. +0.72, width = 2.16 (-1.08 .. +1.08), bed floor y = 0.88, top y = 2.74
    # =========================================================================
    z_rear = -2.95
    z_front = 0.72
    x_box = 1.08
    y_bed = 0.88
    y_top = 2.74

    # Cargo bed steel base & interior deck (hollow open-top box so cargo fits inside!)
    mb.add_box("cargo_silver", -x_box, x_box, y_bed - 0.12, y_bed, z_rear, z_front)
    mb.add_box("bed_floor", -x_box + 0.06, x_box - 0.06, y_bed, y_bed + 0.04, z_rear + 0.06, z_front - 0.06)

    # Front headboard (behind cab) + cab-over top lip + iconic orange inner trim from photo!
    mb.add_box("cargo_silver", -x_box, x_box, y_bed, y_top, z_front - 0.07, z_front)
    mb.add_box("cargo_orange", -x_box + 0.07, x_box - 0.07, y_bed + 0.04, y_top - 0.10, z_front - 0.10, z_front - 0.07)
    # Cab-over visor lip (visible above white cab roof in front photo!)
    mb.add_box("cargo_silver", -x_box, x_box, 2.54, y_top, z_front, z_front + 0.24)
    mb.add_box("chrome", -x_box - 0.01, x_box + 0.01, 2.66, y_top + 0.02, z_front, z_front + 0.25)

    # Vertical stainless steel corner & center posts (4 per side)
    post_zs = [z_rear + 0.05, -1.72, -0.50, z_front - 0.05]
    for side in (-1, 1):
        xp = side * (x_box - 0.04)
        for pz in post_zs:
            mb.add_box("chrome", xp - 0.045, xp + 0.045, y_bed - 0.06, y_top + 0.02, pz - 0.045, pz + 0.045)
        # Top longitudinal stainless steel rail
        mb.add_box("chrome", xp - 0.04, xp + 0.04, y_top - 0.07, y_top + 0.01, z_rear, z_front)

        # Horizontal ribbed champagne-silver aluminum side panels (lower dropside + mid wall + upper slats!)
        # Lower dropside wall: 4 distinct protruding ribs (y = 0.92 .. 1.66)
        mb.add_box("cargo_silver", side * (x_box - 0.06), side * (x_box - 0.01), 0.90, 1.68, z_rear + 0.06, z_front - 0.06)
        for ry in (0.98, 1.15, 1.32, 1.49, 1.63):
            mb.add_box("cargo_rib", side * (x_box - 0.01), side * (x_box + 0.022), ry - 0.035, ry + 0.035, z_rear + 0.08, z_front - 0.08)

        # Upper wall slats with realistic open gaps (matching the slatted hal truck sides in both photos!)
        for slat_y in (1.76, 1.94, 2.12, 2.30, 2.50):
            mb.add_box("cargo_silver", side * (x_box - 0.055), side * (x_box + 0.018), slat_y - 0.055, slat_y + 0.055, z_rear + 0.08, z_front - 0.08)
            mb.add_box("cargo_rib", side * (x_box + 0.005), side * (x_box + 0.026), slat_y - 0.018, slat_y + 0.018, z_rear + 0.09, z_front - 0.09)

        # Side chrome hinge latches along dropside seam
        for lz in (-2.55, -2.05, -1.35, -0.85, -0.15, 0.35):
            mb.add_box("chrome", side * (x_box + 0.01), side * (x_box + 0.04), 1.62, 1.74, lz - 0.025, lz + 0.025)

        # Side under-run protection guardrails (between wheels and behind rear wheel)
        for seg_z0, seg_z1 in ((-1.15, 0.55), (-2.80, -2.28)):
            mb.add_box("chrome", side * 0.96, side * 1.02, 0.44, 0.50, seg_z0, seg_z1)
            mb.add_box("chrome", side * 0.96, side * 1.02, 0.62, 0.68, seg_z0, seg_z1)
            mb.add_box("chrome", side * 0.96, side * 1.02, 0.44, 0.76, seg_z0, seg_z0 + 0.05)
            mb.add_box("chrome", side * 0.96, side * 1.02, 0.44, 0.76, seg_z1 - 0.05, seg_z1)

        # White rear wheel mudflaps behind rear tires
        mb.add_box("mudflap_white", side * 0.62, side * 1.03, 0.24, 0.72, REAR_Z - 0.48, REAR_Z - 0.44)

    # =========================================================================
    # 4. REAR TAILGATE + "GARDAŞLAR SEBZE MEYVE" BANNER + STACKED TAIL LIGHTS
    # =========================================================================
    # Rear top beam (black/chrome frame)
    mb.add_box("grille_black", -x_box + 0.06, x_box - 0.06, 2.52, y_top, z_rear, z_rear + 0.08)
    mb.add_box("chrome", -x_box, x_box, y_top - 0.05, y_top + 0.02, z_rear - 0.01, z_rear + 0.09)

    # Lower rear champagne tailgate lip
    mb.add_box("cargo_silver", -x_box + 0.06, x_box - 0.06, y_bed - 0.02, 1.24, z_rear, z_rear + 0.07)

    # Glossy black rear tailgate upper backing box (y = 1.24 .. 2.52)
    mb.add_box("grille_black", -x_box + 0.06, x_box - 0.06, 1.24, 2.52, z_rear, z_rear + 0.07)

    # Diamond-plate chrome divider strip across rear tailgate (matches photo!)
    mb.add_box("chrome", -x_box + 0.08, x_box - 0.08, 1.66, 1.73, z_rear - 0.015, z_rear + 0.02)
    # Rear tailgate silver latches
    for lx in (-0.52, 0.0, 0.52):
        mb.add_box("chrome", lx - 0.04, lx + 0.04, 1.54, 1.65, z_rear - 0.025, z_rear)

    # UV-MAPPED REAR BANNER PANEL ("GARDAŞLAR SEBZE MEYVE")
    # Facing -Z outward! Viewer behind truck looking toward +Z:
    # viewer left = +X (u=0), viewer right = -X (u=1), top = +Y (v=0), bottom = +Y low (v=1).
    # Outward normal = (0, 0, -1): quad order (BL=+X, BR=-X, TR=-X, TL=+X) ->
    # e1 = BR - BL = (-dx, 0, 0), e2 = TR - BL = (-dx, +dy, 0) -> e1 x e2 = (0, 0, -dx*dy) -> -Z OUTWARD!
    bx_left, bx_right = 0.98, -0.98
    by0, by1 = 1.74, 2.50
    bz = z_rear - 0.015
    mb.add_quad(
        "rear_banner",
        (bx_left, by0, bz),   # viewer bottom-left  (u=0, v=1)
        (bx_right, by0, bz),  # viewer bottom-right (u=1, v=1)
        (bx_right, by1, bz),  # viewer top-right    (u=1, v=0)
        (bx_left, by1, bz),   # viewer top-left     (u=0, v=0)
        uvs=[(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)],
    )

    # Rear tail light bumper housing + iconic double-row red rectangular tail lights (from photo!)
    mb.add_box("chassis_dark", -x_box + 0.04, x_box - 0.04, 0.50, 0.86, z_rear + 0.02, z_rear + 0.16)
    for side in (-1, 1):
        # Corner bumper end-caps (champagne metal)
        mb.add_box("cargo_silver", side * 0.94, side * 1.07, 0.50, 0.88, z_rear - 0.02, z_rear + 0.14)
        # Double-stacked red tail light clusters (top row & bottom row, 3 segments each)
        for row_y in (0.58, 0.74):
            for seg in range(3):
                sx0 = side * (0.38 + seg * 0.175)
                sx1 = side * (0.53 + seg * 0.175)
                mat = "amber_light" if (row_y > 0.70 and seg == 2) else "tail_red"
                mb.add_box(mat, sx0, sx1, row_y - 0.055, row_y + 0.055, z_rear - 0.015, z_rear + 0.04)

    # Wide white Turkish rear mudflap / spray guard below rear bumper + chrome bottom bar
    mb.add_box("mudflap_white", -0.96, 0.96, 0.22, 0.50, z_rear + 0.02, z_rear + 0.06)
    mb.add_box("chrome", -0.97, 0.97, 0.21, 0.25, z_rear + 0.01, z_rear + 0.07)

    return mb


def get_materials(has_banner_tex=False):
    """PBR material definitions for glTF 2.0."""
    mats = {
        "cab_white": {
            "name": "CabWhite",
            "pbrMetallicRoughness": {"baseColorFactor": [0.94, 0.95, 0.96, 1.0], "metallicFactor": 0.08, "roughnessFactor": 0.28},
        },
        "dark_trim": {
            "name": "DarkPlasticTrim",
            "pbrMetallicRoughness": {"baseColorFactor": [0.13, 0.14, 0.15, 1.0], "metallicFactor": 0.05, "roughnessFactor": 0.72},
        },
        "grille_black": {
            "name": "GrilleBlack",
            "pbrMetallicRoughness": {"baseColorFactor": [0.05, 0.055, 0.06, 1.0], "metallicFactor": 0.15, "roughnessFactor": 0.35},
        },
        "chassis_dark": {
            "name": "ChassisSteel",
            "pbrMetallicRoughness": {"baseColorFactor": [0.10, 0.10, 0.11, 1.0], "metallicFactor": 0.65, "roughnessFactor": 0.60},
        },
        "glass_dark": {
            "name": "TintedGlass",
            "pbrMetallicRoughness": {"baseColorFactor": [0.06, 0.10, 0.14, 1.0], "metallicFactor": 0.15, "roughnessFactor": 0.08},
        },
        "cargo_silver": {
            "name": "CargoChampagneMetal",
            "pbrMetallicRoughness": {"baseColorFactor": [0.72, 0.68, 0.60, 1.0], "metallicFactor": 0.65, "roughnessFactor": 0.36},
        },
        "cargo_rib": {
            "name": "CargoRibHighlight",
            "pbrMetallicRoughness": {"baseColorFactor": [0.80, 0.76, 0.68, 1.0], "metallicFactor": 0.78, "roughnessFactor": 0.28},
        },
        "cargo_orange": {
            "name": "CargoInnerOrange",
            "pbrMetallicRoughness": {"baseColorFactor": [0.82, 0.26, 0.10, 1.0], "metallicFactor": 0.10, "roughnessFactor": 0.50},
        },
        "chrome": {
            "name": "StainlessChrome",
            "pbrMetallicRoughness": {"baseColorFactor": [0.86, 0.88, 0.90, 1.0], "metallicFactor": 0.92, "roughnessFactor": 0.18},
        },
        "bed_floor": {
            "name": "CargoBedFloor",
            "pbrMetallicRoughness": {"baseColorFactor": [0.24, 0.22, 0.20, 1.0], "metallicFactor": 0.25, "roughnessFactor": 0.82},
        },
        "tire_rubber": {
            "name": "TireRubber",
            "pbrMetallicRoughness": {"baseColorFactor": [0.09, 0.09, 0.10, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.88},
        },
        "rim_silver": {
            "name": "SteelRim",
            "pbrMetallicRoughness": {"baseColorFactor": [0.76, 0.78, 0.80, 1.0], "metallicFactor": 0.80, "roughnessFactor": 0.30},
        },
        "mudflap_white": {
            "name": "WhiteMudflap",
            "pbrMetallicRoughness": {"baseColorFactor": [0.90, 0.90, 0.90, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.65},
        },
        "ford_blue": {
            "name": "EmblemBlue",
            "pbrMetallicRoughness": {"baseColorFactor": [0.05, 0.20, 0.56, 1.0], "metallicFactor": 0.35, "roughnessFactor": 0.25},
        },
        "headlight_glow": {
            "name": "HeadlightGlass",
            "pbrMetallicRoughness": {"baseColorFactor": [0.96, 0.97, 1.0, 1.0], "metallicFactor": 0.1, "roughnessFactor": 0.10},
            "emissiveFactor": [0.55, 0.55, 0.50],
        },
        "tail_red": {
            "name": "TailLightRed",
            "pbrMetallicRoughness": {"baseColorFactor": [0.85, 0.07, 0.07, 1.0], "metallicFactor": 0.1, "roughnessFactor": 0.15},
            "emissiveFactor": [0.55, 0.04, 0.04],
        },
        "amber_light": {
            "name": "AmberIndicator",
            "pbrMetallicRoughness": {"baseColorFactor": [0.95, 0.55, 0.05, 1.0], "metallicFactor": 0.1, "roughnessFactor": 0.20},
            "emissiveFactor": [0.40, 0.20, 0.02],
        },
        "rear_banner": {
            "name": "RearBannerDecal",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                "metallicFactor": 0.05,
                "roughnessFactor": 0.35,
            },
        },
    }
    if has_banner_tex:
        mats["rear_banner"]["pbrMetallicRoughness"]["baseColorTexture"] = {"index": 0}
    return mats


def export_glb(out_path: Path, node_defs, banner_png_bytes=None):
    """
    node_defs: list of dicts:
      {"name": str, "mesh": MeshBuilder, "translation": (x,y,z), "rotation": (x,y,z,w) optional}
    """
    has_tex = banner_png_bytes is not None and any("rear_banner" in n["mesh"].buckets for n in node_defs)
    mat_catalog = get_materials(has_banner_tex=has_tex)

    used_mats = []
    mat_index = {}
    for nd in node_defs:
        for m in nd["mesh"].buckets:
            if m not in mat_index:
                mat_index[m] = len(used_mats)
                used_mats.append(mat_catalog[m])

    bin_chunks = bytearray()
    buffer_views = []
    accessors = []

    def append_bytes(data: bytes, target=None):
        pad = (4 - (len(bin_chunks) % 4)) % 4
        if pad:
            bin_chunks.extend(b"\x00" * pad)
        offset = len(bin_chunks)
        bin_chunks.extend(data)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target is not None:
            bv["target"] = target
        idx = len(buffer_views)
        buffer_views.append(bv)
        return idx

    gltf_images = []
    gltf_textures = []
    gltf_samplers = []
    if has_tex:
        img_bv = append_bytes(banner_png_bytes)
        gltf_images.append({"bufferView": img_bv, "mimeType": "image/png", "name": "rear_banner"})
        gltf_samplers.append({"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071})
        gltf_textures.append({"sampler": 0, "source": 0})

    gltf_meshes = []
    gltf_nodes = []

    for nd in node_defs:
        primitives = []
        for mat_name, data in nd["mesh"].buckets.items():
            pos = data["pos"]
            norm = data["norm"]
            uv = data["uv"]
            indices = data["idx"]
            if not indices:
                continue

            pos_bytes = b"".join(struct.pack("<fff", *p) for p in pos)
            norm_bytes = b"".join(struct.pack("<fff", *n) for n in norm)
            uv_bytes = b"".join(struct.pack("<ff", *t) for t in uv)
            idx_bytes = b"".join(struct.pack("<I", i) for i in indices)

            bv_pos = append_bytes(pos_bytes, 34962)
            bv_norm = append_bytes(norm_bytes, 34962)
            bv_uv = append_bytes(uv_bytes, 34962)
            bv_idx = append_bytes(idx_bytes, 34963)

            mins = [min(p[c] for p in pos) for c in range(3)]
            maxs = [max(p[c] for p in pos) for c in range(3)]

            acc_pos = len(accessors)
            accessors.append({
                "bufferView": bv_pos, "componentType": 5126, "count": len(pos),
                "type": "VEC3", "min": mins, "max": maxs,
            })
            acc_norm = len(accessors)
            accessors.append({
                "bufferView": bv_norm, "componentType": 5126, "count": len(norm), "type": "VEC3",
            })
            acc_uv = len(accessors)
            accessors.append({
                "bufferView": bv_uv, "componentType": 5126, "count": len(uv), "type": "VEC2",
            })
            acc_idx = len(accessors)
            accessors.append({
                "bufferView": bv_idx, "componentType": 5125, "count": len(indices), "type": "SCALAR",
            })

            primitives.append({
                "attributes": {"POSITION": acc_pos, "NORMAL": acc_norm, "TEXCOORD_0": acc_uv},
                "indices": acc_idx,
                "material": mat_index[mat_name],
            })

        mesh_idx = len(gltf_meshes)
        gltf_meshes.append({"name": nd["name"], "primitives": primitives})
        node_obj = {"name": nd["name"], "mesh": mesh_idx}
        if nd.get("translation") and nd["translation"] != (0.0, 0.0, 0.0):
            node_obj["translation"] = list(nd["translation"])
        if nd.get("rotation"):
            node_obj["rotation"] = list(nd["rotation"])
        gltf_nodes.append(node_obj)

    # Pad binary buffer to 4 bytes
    pad = (4 - (len(bin_chunks) % 4)) % 4
    if pad:
        bin_chunks.extend(b"\x00" * pad)

    gltf = {
        "asset": {"version": "2.0", "generator": "FordTransitGodotBuilder"},
        "scene": 0,
        "scenes": [{"name": "FordTransit", "nodes": list(range(len(gltf_nodes)))}],
        "nodes": gltf_nodes,
        "meshes": gltf_meshes,
        "materials": used_mats,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_chunks)}],
    }
    if gltf_images:
        gltf["images"] = gltf_images
        gltf["textures"] = gltf_textures
        gltf["samplers"] = gltf_samplers

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    jpad = (4 - (len(json_bytes) % 4)) % 4
    if jpad:
        json_bytes += b" " * jpad

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_chunks)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total_len))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(bin_chunks), 0x004E4942))
        f.write(bin_chunks)


def decode_png_rgb(png_bytes: bytes):
    """Minimal pure-Python PNG decoder (RGB/RGBA 8-bit non-interlaced) for preview rendering."""
    if png_bytes[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos = 8
    w = h = color_type = 0
    idat = bytearray()
    while pos < len(png_bytes):
        length, ctype = struct.unpack(">I4s", png_bytes[pos : pos + 8])
        chunk = png_bytes[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            w, h, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if bit_depth != 8 or interlace != 0 or color_type not in (2, 6):
                return None
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
    raw = zlib.decompress(bytes(idat))
    bpp = 3 if color_type == 2 else 4
    stride = w * bpp
    recon = bytearray(h * stride)
    for y in range(h):
        ftype = raw[y * (stride + 1)]
        row_in = raw[y * (stride + 1) + 1 : (y + 1) * (stride + 1)]
        row_out = y * stride
        for x in range(stride):
            a = recon[row_out + x - bpp] if x >= bpp else 0
            b = recon[row_out - stride + x] if y > 0 else 0
            c = recon[row_out - stride + x - bpp] if (x >= bpp and y > 0) else 0
            val = row_in[x]
            if ftype == 0:
                recon[row_out + x] = val
            elif ftype == 1:
                recon[row_out + x] = (val + a) & 0xFF
            elif ftype == 2:
                recon[row_out + x] = (val + b) & 0xFF
            elif ftype == 3:
                recon[row_out + x] = (val + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                recon[row_out + x] = (val + pr) & 0xFF
    return w, h, bpp, bytes(recon)


def write_png(path: Path, w: int, h: int, rgb: bytearray):
    def chunk(ctype: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + ctype + data + struct.pack(">I", zlib.crc32(ctype + data) & 0xFFFFFFFF)

    rows = bytearray()
    stride = w * 3
    for y in range(h):
        rows.append(0)
        rows.extend(rgb[y * stride : (y + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b"")
    path.write_bytes(data)


def render_preview(node_defs, banner_png_bytes=None):
    """Render a 2x2 verification sheet (front 3/4, rear 3/4, side, top) to PREVIEW_PATH."""
    mats = get_materials(has_banner_tex=False)
    tex = decode_png_rgb(banner_png_bytes) if banner_png_bytes else None

    tris = []  # (p0, p1, p2, n, rgb_base, uv0, uv1, uv2, is_tex)
    for nd in node_defs:
        tx, ty, tz = nd.get("translation", (0.0, 0.0, 0.0))
        for mname, data in nd["mesh"].buckets.items():
            cf = mats[mname]["pbrMetallicRoughness"]["baseColorFactor"]
            em = mats[mname].get("emissiveFactor", [0.0, 0.0, 0.0])
            col = (
                min(1.0, cf[0] + em[0] * 0.5),
                min(1.0, cf[1] + em[1] * 0.5),
                min(1.0, cf[2] + em[2] * 0.5),
            )
            is_tex = (mname == "rear_banner" and tex is not None)
            pos = data["pos"]
            uv = data["uv"]
            idx = data["idx"]
            for i in range(0, len(idx), 3):
                i0, i1, i2 = idx[i], idx[i + 1], idx[i + 2]
                p0 = (pos[i0][0] + tx, pos[i0][1] + ty, pos[i0][2] + tz)
                p1 = (pos[i1][0] + tx, pos[i1][1] + ty, pos[i1][2] + tz)
                p2 = (pos[i2][0] + tx, pos[i2][1] + ty, pos[i2][2] + tz)
                n = v_norm(v_cross(v_sub(p1, p0), v_sub(p2, p0)))
                tris.append((p0, p1, p2, n, col, uv[i0], uv[i1], uv[i2], is_tex))

    vw, vh = 480, 320
    full_w, full_h = vw * 2, vh * 2
    img = bytearray([225, 232, 240] * (full_w * full_h))

    views = [
        # (ox, oy, cam_pos, target, light_dir)
        (0, 0, (-4.4, 2.3, 5.4), (0.0, 1.25, 0.1), v_norm((-0.5, 0.8, 0.6))),      # Front-Right 3/4 (matches photo 2!)
        (vw, 0, (-4.6, 2.4, -5.6), (0.0, 1.35, -0.3), v_norm((-0.5, 0.8, -0.6))),  # Rear-Right 3/4 (matches photo 1!)
        (0, vh, (-7.2, 1.5, 0.0), (0.0, 1.35, 0.0), v_norm((-0.4, 0.9, 0.3))),     # Side profile
        (vw, vh, (0.01, 7.6, -0.6), (0.0, 1.2, 0.0), v_norm((0.3, 1.0, 0.3))),     # Top-down overview
    ]

    for ox, oy, cam, target, ldir in views:
        fwd = v_norm(v_sub(target, cam))
        right = v_norm(v_cross(fwd, (0.0, 1.0, 0.0)))
        up = v_cross(right, fwd)
        fov = 42.0 * math.pi / 180.0
        f = (vh * 0.5) / math.tan(fov * 0.5)
        zbuf = [1e9] * (vw * vh)

        # Ground gradient backdrop
        for py in range(vh):
            bg = (195, 202, 210) if py > vh * 0.58 else (225, 235, 246)
            row = ((oy + py) * full_w + ox) * 3
            for px in range(vw):
                img[row + px * 3 : row + px * 3 + 3] = bytes(bg)

        for p0, p1, p2, n, col, uv0, uv1, uv2, is_tex in tris:
            # Backface cull (camera view dir)
            mid = ((p0[0] + p1[0] + p2[0]) / 3, (p0[1] + p1[1] + p2[1]) / 3, (p0[2] + p1[2] + p2[2]) / 3)
            if v_dot(n, v_sub(cam, mid)) <= 0.0:
                continue
            pts2 = []
            depths = []
            ok = True
            for p in (p0, p1, p2):
                d = v_sub(p, cam)
                cz = v_dot(d, fwd)
                if cz <= 0.2:
                    ok = False
                    break
                cx = v_dot(d, right)
                cy = v_dot(d, up)
                sx = vw * 0.5 + (cx / cz) * f
                sy = vh * 0.5 - (cy / cz) * f
                pts2.append((sx, sy))
                depths.append(cz)
            if not ok:
                continue
            x0, y0 = pts2[0]
            x1, y1 = pts2[1]
            x2, y2 = pts2[2]
            denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
            if abs(denom) < 1e-5:
                continue
            minx = max(0, int(math.floor(min(x0, x1, x2))))
            maxx = min(vw - 1, int(math.ceil(max(x0, x1, x2))))
            miny = max(0, int(math.floor(min(y0, y1, y2))))
            maxy = min(vh - 1, int(math.ceil(max(y0, y1, y2))))
            shade = 0.38 + 0.62 * max(0.0, v_dot(n, ldir))
            rc = min(255, int(col[0] * shade * 255))
            gc = min(255, int(col[1] * shade * 255))
            bc = min(255, int(col[2] * shade * 255))

            for py in range(miny, maxy + 1):
                pyf = py + 0.5
                for px in range(minx, maxx + 1):
                    pxf = px + 0.5
                    w0 = ((y1 - y2) * (pxf - x2) + (x2 - x1) * (pyf - y2)) / denom
                    w1 = ((y2 - y0) * (pxf - x2) + (x0 - x2) * (pyf - y2)) / denom
                    w2 = 1.0 - w0 - w1
                    if w0 >= -1e-4 and w1 >= -1e-4 and w2 >= -1e-4:
                        z = w0 * depths[0] + w1 * depths[1] + w2 * depths[2]
                        zi = py * vw + px
                        if z < zbuf[zi]:
                            zbuf[zi] = z
                            idx3 = ((oy + py) * full_w + (ox + px)) * 3
                            if is_tex:
                                u = max(0.0, min(1.0, w0 * uv0[0] + w1 * uv1[0] + w2 * uv2[0]))
                                v = max(0.0, min(1.0, w0 * uv0[1] + w1 * uv1[1] + w2 * uv2[1]))
                                tw, th, tbpp, tdata = tex
                                tx_i = min(tw - 1, int(u * tw))
                                ty_i = min(th - 1, int(v * th))
                                ti = (ty_i * tw + tx_i) * tbpp
                                img[idx3] = min(255, int(tdata[ti] * (0.65 + 0.35 * shade)))
                                img[idx3 + 1] = min(255, int(tdata[ti + 1] * (0.65 + 0.35 * shade)))
                                img[idx3 + 2] = min(255, int(tdata[ti + 2] * (0.65 + 0.35 * shade)))
                            else:
                                img[idx3] = rc
                                img[idx3 + 1] = gc
                                img[idx3 + 2] = bc

    write_png(PREVIEW_PATH, full_w, full_h, img)


def main():
    banner_bytes = TEX_PATH.read_bytes() if TEX_PATH.exists() else None
    print(f"Banner texture loaded: {TEX_PATH.exists()} ({len(banner_bytes) if banner_bytes else 0} bytes)")

    chassis = build_chassis_mesh()
    wheel_f = build_wheel_mesh(dually=False)
    wheel_r = build_wheel_mesh(dually=True)

    # 1. Separate Godot VehicleBody3D / VehicleWheel3D GLBs
    export_glb(MODELS_DIR / "ford_transit_chassis.glb", [{"name": "FordTransitChassis", "mesh": chassis}], banner_bytes)
    export_glb(MODELS_DIR / "wheel_front.glb", [{"name": "WheelFront", "mesh": wheel_f}])
    export_glb(MODELS_DIR / "wheel_rear.glb", [{"name": "WheelRear", "mesh": wheel_r}])

    # 2. Complete combined GLB (body + 4 named wheel nodes at exact hub positions)
    complete_nodes = [
        {"name": "FordTransitBody", "mesh": chassis, "translation": (0.0, 0.0, 0.0)},
        {"name": "Wheel_FL", "mesh": wheel_f, "translation": (FRONT_X, WHEEL_RADIUS, FRONT_Z)},
        {"name": "Wheel_FR", "mesh": wheel_f, "translation": (-FRONT_X, WHEEL_RADIUS, FRONT_Z)},
        {"name": "Wheel_RL", "mesh": wheel_r, "translation": (REAR_X, WHEEL_RADIUS, REAR_Z)},
        {"name": "Wheel_RR", "mesh": wheel_r, "translation": (-REAR_X, WHEEL_RADIUS, REAR_Z)},
    ]
    export_glb(MODELS_DIR / "ford_transit_complete.glb", complete_nodes, banner_bytes)

    # 3. Render 4-angle preview for visual inspection
    render_preview(complete_nodes, banner_bytes)

    for p in (
        MODELS_DIR / "ford_transit_complete.glb",
        MODELS_DIR / "ford_transit_chassis.glb",
        MODELS_DIR / "wheel_front.glb",
        MODELS_DIR / "wheel_rear.glb",
        PREVIEW_PATH,
    ):
        print(f"Wrote {p.name}: {p.stat().st_size} bytes")


if __name__ == "__main__":
    main()
