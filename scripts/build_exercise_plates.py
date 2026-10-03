# scripts/build_exercise_plates.py
"""Crop the vendored workout-guide SVGs into app plate assets.

Run once after vendoring; the OUTPUT is committed, the vendored source is not.
Reads demo_slug + demo_pair from the exercise library and emits
assets/exercise_plates/<slug>-1.svg (always) and -3.svg (pairs only).

VALIDATED against the real catalogue 2026-08-29 (upstream
aac599224bb9780305239607ef98540b7e0ce389): 292 files for 153 slugs, 0 errors,
6.64 MB raw / 2.83 MB deflated, no paired viewBox drift.

WHY the bbox comes from PATH DATA and not a raster: upstream ships SVG only --
all 906 frames in its manifest are format "svg" -- and no rasterizer is
installed here. Pure stdlib, no native Cairo dependency, reproducible in CI.

WHY THE FULL COMMAND SET IS IMPLEMENTED rather than hard-failed: an earlier
draft raised on A/S/T on the theory they were rare. Measured against the 292
files we actually ship, EVERY ONE uses them -- 's' alone appears 20,917 times --
so that version could not have processed a single file.

  C/Q/S/T are EXACT. A bezier lies inside the convex hull of its control points,
  so collecting on-curve AND control points yields a superset of the true ink
  bbox: loose at worst, never clipping. S and T reconstruct the implied control
  point by reflection, which is arithmetic, not approximation.

  A (arc) is converted from SVG endpoint parameterisation to centre
  parameterisation (W3C implementation notes F.6.5) and sampled across its real
  sweep. Bounding an arc by its chord box expanded by (rx, ry) was tried and is
  WORTHLESS in practice -- a nearly-straight arc is encoded with an enormous
  radius, which blew bench-press up to 59637x59602 on a 512 canvas and put 199
  of 292 files outside the artboard. Do not re-propose it.

  GROUND TRUTH: against the rasters used for the founder review, bench-press
  frame 1 gives (30.0, 38.0, 419.3, 482.9) vs the raster's (30, 38, 420, 482) --
  worst-edge slack 0.9 units on a 512 canvas -- and frame 3 gives 0.5.

WHY a PAIR is cropped to the UNION and a SINGLE to its own bounds: cropping each
frame of a pair separately makes the body change size between START and END
(bench press is 390x444 then 431x397). But a HOLD renders frame 1 alone, so
unioning it with an unrendered frame 3 pollutes the viewBox -- for Wall Sit,
frame 3 is the athlete standing up, and the union would shrink the seated pose
to a fraction of the plate. demo_pair tells them apart.

WHY no stroke: at matched display size a stroke closes the interior gaps --
median gap 17 -> 13 units at width 4, 6% closed outright. The crop is the fix.
Over all 292 shipping files the cropped viewBox is a median 47% of the canvas
area, so the figure renders about 1.45x larger in the same box.
"""
import io, os, re, json, math, sys

ARC_SAMPLES = 24
PAD = 10
CANVAS = 512
EXPECTED_VIEWBOX = "0 0 512 512"
SRC = sys.argv[1] if len(sys.argv) > 1 else "vendor/workout-guide/packages/workout-guide/assets"
OUT = "assets/exercise_plates"

NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?")
CMD = re.compile(r"([MmZzLlHhVvCcSsQqTtAa])")
NON_PATH = re.compile(r"<(circle|rect|ellipse|polygon|polyline|use|image|text)\b")


def _arc_points(x1, y1, rx, ry, phi_deg, fa, fs, x2, y2):
    """W3C F.6.5 endpoint -> centre parameterisation, then sample the sweep."""
    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2):
        return [(x2, y2)]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(phi_deg % 360.0)
    cp, sp = math.cos(phi), math.sin(phi)

    dx2, dy2 = (x1 - x2) / 2.0, (y1 - y2) / 2.0
    x1p = cp * dx2 + sp * dy2
    y1p = -sp * dx2 + cp * dy2

    # F.6.6 -- scale the radii up if they cannot span the chord
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx *= s
        ry *= s

    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    co = 0.0 if den == 0 else math.sqrt(max(0.0, num / den))
    if fa == fs:
        co = -co
    cxp = co * rx * y1p / ry
    cyp = -co * ry * x1p / rx

    cx = cp * cxp - sp * cyp + (x1 + x2) / 2.0
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2.0

    def ang(ux, uy, vx, vy):
        d = math.hypot(ux, uy) * math.hypot(vx, vy)
        if d == 0:
            return 0.0
        c = max(-1.0, min(1.0, (ux * vx + uy * vy) / d))
        a = math.acos(c)
        return -a if (ux * vy - uy * vx) < 0 else a

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    th1 = ang(1.0, 0.0, ux, uy)
    dth = ang(ux, uy, vx, vy)
    if not fs and dth > 0:
        dth -= 2 * math.pi
    elif fs and dth < 0:
        dth += 2 * math.pi

    out = []
    for i in range(ARC_SAMPLES + 1):
        th = th1 + dth * (i / float(ARC_SAMPLES))
        ct, st = math.cos(th), math.sin(th)
        out.append((cx + rx * ct * cp - ry * st * sp,
                    cy + rx * ct * sp + ry * st * cp))
    return out


def path_points(d, where):
    """Every on-curve point, every control point, and sampled arc points."""
    toks = [t for t in CMD.split(d) if t.strip()]
    pts = []
    cx = cy = sx = sy = 0.0
    pc2 = None   # previous cubic control-2, for S reflection
    pq = None    # previous quadratic control, for T reflection
    cmd = None
    i = 0
    while i < len(toks):
        t = toks[i]
        if CMD.fullmatch(t):
            cmd = t
            i += 1
            if cmd in "Zz":
                cx, cy = sx, sy
                pc2 = pq = None
            continue
        nums = [float(x) for x in NUM.findall(t)]
        j = 0
        c = cmd
        while j < len(nums):
            rel = c.islower()
            C = c.upper()
            if C == "M":
                x, y = nums[j:j + 2]; j += 2
                cx, cy = (cx + x, cy + y) if rel else (x, y)
                sx, sy = cx, cy
                pts.append((cx, cy)); pc2 = pq = None
                c = "l" if rel else "L"          # implicit lineto after moveto
            elif C == "L":
                x, y = nums[j:j + 2]; j += 2
                cx, cy = (cx + x, cy + y) if rel else (x, y)
                pts.append((cx, cy)); pc2 = pq = None
            elif C == "H":
                x = nums[j]; j += 1
                cx = cx + x if rel else x
                pts.append((cx, cy)); pc2 = pq = None
            elif C == "V":
                y = nums[j]; j += 1
                cy = cy + y if rel else y
                pts.append((cx, cy)); pc2 = pq = None
            elif C == "C":
                a = nums[j:j + 6]; j += 6
                p = [(cx + a[k], cy + a[k + 1]) if rel else (a[k], a[k + 1])
                     for k in (0, 2, 4)]
                pts.extend(p); pc2 = p[1]; cx, cy = p[2]; pq = None
            elif C == "S":
                a = nums[j:j + 4]; j += 4
                # implied control 1 = reflection of the previous cubic's control
                # 2 about the current point; the current point itself when the
                # previous command was not C/S.
                r = (2 * cx - pc2[0], 2 * cy - pc2[1]) if pc2 else (cx, cy)
                p2 = (cx + a[0], cy + a[1]) if rel else (a[0], a[1])
                e = (cx + a[2], cy + a[3]) if rel else (a[2], a[3])
                pts.extend([r, p2, e]); pc2 = p2; cx, cy = e; pq = None
            elif C == "Q":
                a = nums[j:j + 4]; j += 4
                p = [(cx + a[k], cy + a[k + 1]) if rel else (a[k], a[k + 1])
                     for k in (0, 2)]
                pts.extend(p); pq = p[0]; cx, cy = p[1]; pc2 = None
            elif C == "T":
                a = nums[j:j + 2]; j += 2
                r = (2 * cx - pq[0], 2 * cy - pq[1]) if pq else (cx, cy)
                e = (cx + a[0], cy + a[1]) if rel else (a[0], a[1])
                pts.extend([r, e]); pq = r; cx, cy = e; pc2 = None
            elif C == "A":
                a = nums[j:j + 7]; j += 7
                ex, ey = (cx + a[5], cy + a[6]) if rel else (a[5], a[6])
                pts.extend(_arc_points(cx, cy, a[0], a[1], a[2],
                                       a[3] != 0, a[4] != 0, ex, ey))
                cx, cy = ex, ey; pc2 = pq = None
            else:
                raise ValueError("%s: unhandled command %r" % (where, c))
        i += 1
    return pts


def ink_bbox(p):
    """Ink bounds, with the structural guards. Anything the parser cannot see
    HARD-FAILS rather than silently cropping through the drawing."""
    t = io.open(p, encoding="utf-8").read()

    vb = re.search(r'viewBox="([^"]*)"', t)
    if not vb:
        raise ValueError("%s: no viewBox" % p)
    if " ".join(vb.group(1).split()) != EXPECTED_VIEWBOX:
        raise ValueError("%s: viewBox is %r, expected %r -- union() clamps to "
                         "CANVAS=%d and would truncate this frame"
                         % (p, vb.group(1), EXPECTED_VIEWBOX, CANVAS))
    if re.search(r"\stransform=", t):
        raise ValueError("%s: has a transform=; the bbox would be computed in "
                         "the wrong coordinate space" % p)
    m = NON_PATH.search(t)
    if m:
        raise ValueError("%s: contains <%s>, whose geometry the path parser "
                         "cannot see; the crop would cut through it silently"
                         % (p, m.group(1)))

    pts = []
    for d in re.findall(r'\sd="([^"]+)"', t):
        pts += path_points(d, p)
    if not pts:
        raise ValueError("no path data: %s" % p)
    xs = [q[0] for q in pts]
    ys = [q[1] for q in pts]
    return min(xs), min(ys), max(xs), max(ys)


def union(boxes):
    x0 = max(0, min(b[0] for b in boxes) - PAD)
    y0 = max(0, min(b[1] for b in boxes) - PAD)
    x1 = min(CANVAS, max(b[2] for b in boxes) + PAD)
    y1 = min(CANVAS, max(b[3] for b in boxes) + PAD)
    return round(x0), round(y0), round(x1 - x0), round(y1 - y0)


def crop_svg(text, view_box, where):
    t = re.sub(r"<\?xml[^>]*\?>", "", text)
    # [^"]* not \d+ -- "512.0" or "512px" would survive a digits-only strip and
    # then fail the assets test with no repair step.
    t = re.sub(r'\swidth="[^"]*"', "", t, count=1)
    t = re.sub(r'\sheight="[^"]*"', "", t, count=1)
    t, n = re.subn(r'viewBox="[^"]*"', 'viewBox="%d %d %d %d"' % view_box, t, count=1)
    if n != 1:
        raise ValueError("%s: no viewBox to rewrite" % where)
    for lit in ('fill="#fff"', 'fill="#FFF"', 'fill="#ffffff"', 'fill="#FFFFFF"',
                'fill="white"', 'fill="WHITE"'):
        t = t.replace(lit, 'fill="currentColor"')
    if 'fill="currentColor"' not in t:
        raise ValueError("%s: no white fill found to convert (a style= or an "
                         "inherited fill is not handled)" % where)
    return t.strip()


def main():
    lib = json.load(io.open("assets/data/exercise_library.json", encoding="utf-8"))
    # 165 exercises share 153 slugs -- dedupe, carrying the shape with each.
    slugs = {}
    for e in lib:
        s = e.get("demo_slug")
        if not s:
            continue
        pair = bool(e.get("demo_pair"))
        if s in slugs and slugs[s] != pair:
            raise SystemExit("slug %s is claimed as both pair and single" % s)
        slugs[s] = pair
    if not slugs:
        raise SystemExit("no demo_slug in the library -- run Task 1 first")
    if not os.path.isdir(SRC):
        raise SystemExit("upstream assets not found at %s\n"
                         "clone it (Task 2 Step 3) or pass the root as argv[1]" % SRC)

    os.makedirs(OUT, exist_ok=True)
    written = set()
    for slug, pair in sorted(slugs.items()):
        frames = ["1", "3"] if pair else ["1"]
        srcs = [os.path.join(SRC, slug, "frame-%s.svg" % f) for f in frames]
        for f in srcs:
            if not os.path.exists(f):
                raise SystemExit("missing upstream frame: %s" % f)
        vb = union([ink_bbox(f) for f in srcs])
        for src, f in zip(srcs, frames):
            name = "%s-%s.svg" % (slug, f)
            io.open(os.path.join(OUT, name), "w", encoding="utf-8").write(
                crop_svg(io.open(src, encoding="utf-8").read(), vb, name))
            written.add(name)

    # A renamed slug leaves an orphan the 292-file test would catch later; say
    # so HERE, where the fix is obvious.
    stale = {f for f in os.listdir(OUT) if f.endswith(".svg")} - written
    if stale:
        raise SystemExit("stale SVGs from an earlier run: %s\n"
                         "delete them -- the asset test counts files"
                         % sorted(stale)[:5])

    print("wrote %d files for %d slugs (%d pair, %d single)"
          % (len(written), len(slugs),
             sum(1 for v in slugs.values() if v),
             sum(1 for v in slugs.values() if not v)))


if __name__ == "__main__":
    main()
