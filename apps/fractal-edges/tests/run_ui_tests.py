#!/usr/bin/env python3
"""Headless test of an edge handle's drag maths with synthetic pointer events (PySide6 only)."""
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QMetaObject, Q_ARG, Q_RETURN_ARG, Qt, QUrl, QPoint, QtMsgType, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
msgs = []
qInstallMessageHandler(lambda mode, ctx, msg: msgs.append((mode, msg)))

app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(str(REPO / "qml"))
view.setSource(QUrl.fromLocalFile(str(HERE / "Harness.qml")))
view.resize(3000, 500)
view.show()
failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


check(view.status() == QQuickView.Status.Ready, f"Harness loads ({[e.toString() for e in view.errors()]})")
QTest.qWait(200)
root = view.rootObject()


def ask(name, *args):
    r = QMetaObject.invokeMethod(root, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
    return r.toVariant() if hasattr(r, "toVariant") else r


def log():
    return str(ask("logText"))


def drag(dx, dy=0, from_xy=(108, 250), steps=3):
    """Press on the strip, move by (dx, dy) in steps, release."""
    x0, y0 = from_xy
    QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, QPoint(x0, y0))
    for i in range(1, steps + 1):
        QTest.mouseMove(view, QPoint(x0 + dx * i // steps, y0 + dy * i // steps))
        QTest.qWait(10)
    QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, QPoint(x0 + dx, y0 + dy))
    QTest.qWait(30)


# Row seam (drag left/right): 1000 px span, ratio 0.5. +100 px right -> 0.6
ask("clearLog")
drag(100)
parts = log().split("|")
check(parts[0] == "start", f"press starts the drag ({parts[:2]})")
check(parts[-1] == "end 0.600", f"drag +100px of 1000 -> ratio 0.600 ({parts[-1]})")
check(any(p.startswith("move") for p in parts), "moves are reported while dragging")
check(ask("isDragging") is False, "not dragging after release")

# Drag left by 250 px -> 0.25; vertical movement is ignored for a row seam
ask("clearLog")
drag(-250, dy=80)
check(log().split("|")[-1] == "end 0.250", f"-250px -> 0.250, ignoring vertical motion ({log().split('|')[-1]})")

# Clamps: a huge drag cannot collapse a tile
ask("clearLog")
drag(2000, steps=2)
check(log().split("|")[-1] == "end 0.950", f"clamped high ({log().split('|')[-1]})")
ask("clearLog")
drag(-2000, steps=2)
check(log().split("|")[-1] == "end 0.050", f"clamped low ({log().split('|')[-1]})")

# Column seam (drag up/down), different span and starting ratio
ask("setSeam", {"key": "a|b", "a": "a", "b": "b", "axis": "y", "ratio": 0.4, "span": 500, "x": 0, "y": 0, "w": 400, "h": 16})
QTest.qWait(100)
ask("clearLog")
drag(0, dy=50, from_xy=(300, 58))
check(log().split("|")[-1] == "end 0.500", f"column seam: +50px of 500 from 0.4 -> 0.500 ({log().split('|')[-1]})")

# Rubber band: a seam whose engine limits are 0.1..0.9 (span 1000 px). Pulling 900 px right from 0.5
# asks for 1.4; tiles get the clamped 0.9, the guide gets a bounded overshoot beyond it.
limited = {"key": "a|b", "a": "a", "b": "b", "axis": "x", "ratio": 0.5, "span": 1000, "lo": 0.1, "hi": 0.9, "x": 0, "y": 0, "w": 16, "h": 400}
ask("setSeam", limited)
QTest.qWait(100)
ask("clearLog")
drag(900, steps=3)
moves = [p.split() for p in log().split("|") if p.startswith("move")]
ratios = [float(m[1]) for m in moves]
shown = [float(m[2]) for m in moves]
check(ratios[-1] == 0.9, f"tiles stop at the engine limit ({ratios[-1]})")
check(0.9 < shown[-1] <= 0.9 + 0.04 + 1e-6, f"guide overshoots a little, bounded by give ({shown[-1]})")
check(log().split("|")[-1] == "end 0.900", f"release reports the clamped ratio ({log().split('|')[-1]})")
ask("clearLog")
drag(100, steps=2)                                  # 0.5 -> 0.6, inside the limits
m = [p.split() for p in log().split("|") if p.startswith("move")][-1]
check(abs(float(m[1]) - 0.6) < 1e-9 and abs(float(m[2]) - 0.6) < 1e-9, f"inside the limits the guide is exactly the tile ratio ({m})")

# ---- whole-seam handle: floating windows cut what is grabbable and what is drawn -----------------
import json as _json
tall = {"key": "a|b", "a": "a", "b": "b", "axis": "x", "ratio": 0.5, "span": 1000, "lo": 0.1, "hi": 0.9, "x": 0, "y": 0, "w": 16, "h": 400}
ask("setSeam", tall)
ask("setBlockers", [{"x": -10, "y": 150, "w": 50, "h": 100}])      # layout coords; overlaps the seam over y=150..250
QTest.qWait(150)
hit = _json.loads(str(ask("hitJson")))
check([(r["y"], r["h"]) for r in hit] == [(0, 150), (250, 150)], f"input only where nothing floats over the seam ({hit})")
check(all(r["x"] == 0 and r["w"] == 16 for r in hit), "pieces keep the seam's full thickness")

# hover the handle: the bar shows, cut around the floating window (strip sits at window x=100, y=50)
QTest.mouseMove(view, QPoint(108, 80))
QTest.qWait(400)
img = view.grabWindow()
barlike = lambda x, y: img.pixelColor(x, y).green() < 245          # pink bar over white, not plain white
check(barlike(108, 120) and barlike(108, 420), "bar drawn on both sides of the floating window")
check(not barlike(108, 250), "bar cut where the floating window covers the seam (window y = 200..300)")


def band_count():
    g = view.grabWindow()
    return sum(1 for y in range(205, 295) if g.pixelColor(108, y).green() < 245)


# The seam moves out from under the window (as after a drag): the bar must GROW smoothly.
QMetaObject.invokeMethod(root, "setSeam", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", dict(tall, x=100)))
grow = []
for _ in range(10):
    grow.append(band_count())
    QTest.qWait(14)
QTest.qWait(300)
grow.append(band_count())
check(grow[-1] >= 85, f"bar is whole again once clear of the window ({grow[-1]})")
check(all(b >= a for a, b in zip(grow, grow[1:])), f"and grew monotonically ({grow})")
check(any(5 < v < 80 for v in grow), f"through partial states, so it animates and does not pop ({grow})")

# And the reverse: a handle that STARTS cut still grows back when the window leaves.
ask("setSeam", tall)
QTest.qWait(400)
check(band_count() <= 5, "starts cut")
QMetaObject.invokeMethod(root, "setSeam", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", dict(tall, x=100)))
grow2 = []
for _ in range(10):
    grow2.append(band_count())
    QTest.qWait(14)
QTest.qWait(300)
grow2.append(band_count())
check(grow2[-1] >= 85, f"a handle that started cut grows back to full ({grow2[-1]})")
check(any(5 < v < 80 for v in grow2), f"smoothly ({grow2})")
ask("setBlockers", [])
ask("setSeam", tall)
QTest.mouseMove(view, QPoint(2000, 400))

# Moves do not fire without a press
ask("clearLog")
QTest.mouseMove(view, QPoint(300, 58))
QTest.mouseMove(view, QPoint(320, 58))
QTest.qWait(30)
check(log() == "", f"hover alone emits nothing ({log()!r})")

# ---- guide line: render it and check where the pixels are -----------------------------------
gview = QQuickView()
gview.engine().addImportPath(str(REPO / "qml"))
gview.setSource(QUrl.fromLocalFile(str(HERE / "GuideHarness.qml")))
gview.resize(1300, 900)
gview.show()
QTest.qWait(200)
check(gview.status() == QQuickView.Status.Ready, f"GuideHarness loads ({[e.toString() for e in gview.errors()]})")
groot = gview.rootObject()


def gask(name, *args):
    QMetaObject.invokeMethod(groot, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
    QTest.qWait(120)


def gask_ret(name, *args):
    r = QMetaObject.invokeMethod(groot, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
    return r.toVariant() if hasattr(r, "toVariant") else r


def lit(x, y):
    c = gview.grabWindow().pixelColor(x, y)
    return abs(c.red() - 255) < 12 and abs(c.green() - 176) < 16 and abs(c.blue() - 202) < 16   # theme primary #ffb0ca


# Row seam from the real engine fixture: centre x=700 in layout coords, monitor origin x=100.
seam = {"axis": "x", "x": 692, "y": 40, "w": 16, "h": 800, "ratio": 0.5, "span": 1200}
check(not lit(600, 400), "guide hidden with no seam")
gask("show", seam, 0.5)
check(lit(600, 400) and not lit(720, 400), "guide at the seam centre (x=700 - 100 origin)")
gask("show", seam, 0.6)
check(lit(720, 400) and not lit(600, 400), "guide follows the ratio (+0.1 of 1200 px = +120)")
check(lit(720, 60) and lit(720, 830) and not lit(720, 20), "guide spans the seam's height only")
gask("hide")
check(not lit(720, 400), "guide hides again")
vseam = {"axis": "y", "x": 700, "y": 432, "w": 600, "h": 16, "ratio": 0.5, "span": 800}
gask("show", vseam, 0.75)
# column seam at y=432..448 (centre 440), origin y=0, ratio 0.5 -> 0.75 moves it down 0.25*800 = 200 px
check(lit(800, 640) and not lit(800, 440), "column seam: guide moves down 0.25 of 800 px")
check(lit(900, 640) and not lit(300, 640) and not lit(1250, 640), "column seam: guide spans x=600..1200 only (700..1300 minus the 100 origin)")

# Stretch past the limit and spring back (seam limits 0.1..0.9, span 1200, origin x=100)
limseam = dict(seam, lo=0.1, hi=0.9)
gask("show", limseam, 0.5)
t_normal = float(gask_ret("drawnThickness"))
gask("show", limseam, 0.94)                          # 48 px past the limit
check(float(gask_ret("drawnThickness")) > t_normal + 2, "line thickens while stretched past the limit")
check(lit(1126, 400) and lit(1129, 400), "stretched line is drawn at the overshoot position (x=700+0.44*1200-100=1128)")
gask("setSettling", True)
QMetaObject.invokeMethod(groot, "show", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", limseam), Q_ARG("QVariant", 0.9))
QTest.qWait(40)
check(not lit(1080, 400), "after release the line is still on its way back (not yet at the limit)")
QTest.qWait(500)
check(lit(1080, 400) and not lit(1128, 400), "and settles at the limit (x=1080)")
gask("setSettling", False)
gask("hide")

# A floating window over part of the seam: the guide is cut there (layer surfaces would
# otherwise paint over the window).
gask("show", seam, 0.5)
gask("setBlockers", [{"x": 600, "y": 300, "w": 400, "h": 100}])      # layout coords; guide at x=700-100=600
check(lit(600, 200) and lit(600, 600), "guide visible above and below the floating window")
check(not lit(600, 350), "guide cut where the floating window covers it")
gask("setBlockers", [])
check(lit(600, 350), "guide whole again once the window is gone")

# Smooth cuts: sliding the line sideways past a floating window's edge must open/close the cut
# gradually, not pop. Window layout x=650..850, y=300..400; line at layout x=700 (inside) vs 880 (outside).
cut_seam = dict(seam, lo=0.1, hi=0.9)
gask("setBlockers", [{"x": 650, "y": 300, "w": 200, "h": 100}])
gask("show", cut_seam, 0.5)                                  # inside the window's width: cut
band = lambda x: sum(1 for y in range(300, 400) if lit(x, y))
check(band(600) == 0, "line inside the window's width is cut across the whole window")


def sample(x, n=10, ms=14):
    out = []
    for _ in range(n):
        out.append(band(x))
        QTest.qWait(ms)
    return out


QMetaObject.invokeMethod(groot, "show", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", cut_seam), Q_ARG("QVariant", 0.65))   # line now x=880-100=780
opening = sample(780)
check(opening[-1] >= 95, f"cut closes completely once clear of the window (final {opening[-1]})")
check(all(b >= a for a, b in zip(opening, opening[1:])), f"the line grows monotonically, no flicker ({opening})")
check(any(5 < v < 95 for v in opening), f"it passes through partial states, i.e. animates rather than pops ({opening})")

QMetaObject.invokeMethod(groot, "show", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", cut_seam), Q_ARG("QVariant", 0.5))    # back under the window
closing = sample(600)
check(closing[-1] <= 5, f"cut opens up again when the line re-enters the window's width (final {closing[-1]})")
check(all(b <= a for a, b in zip(closing, closing[1:])), f"and shrinks monotonically ({closing})")
check(any(5 < v < 95 for v in closing), f"through partial states ({closing})")
gask("setBlockers", [])
gask("hide")

bad = [m for mode, m in msgs if mode in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg)
       and "scheme watching unavailable" not in m]
for m in bad:
    print("  warning:", m)
check(not bad, "no unexpected QML warnings")
print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
