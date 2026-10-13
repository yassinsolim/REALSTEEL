"""Shell shapes and mesh densities for the premium bodies, which are built from smooth superellipsoid shells (see
robotlib.PartBuilder.pod) rather than the free frames' bevelled boxes.
"""

# Shapes, as (top to bottom, around) roundness exponents: a plate with crisp rounded edges, a softer shell, a dome, and an
# ellipsoid.
PLATE = (0.3, 0.33)
SHELL = (0.4, 0.4)
DOME = (0.58, 0.42)
BALL = (1.0, 1.0)

# Mesh density, as (around, top to bottom): big shells, medium ones, small details, thin rims. Smooth shading hides the
# facets, so these stay low enough for a phone to draw a hall full of robots.
BIG = (20, 10)
MID = (16, 8)
FINE = (12, 5)
RIM = (24, 4)
