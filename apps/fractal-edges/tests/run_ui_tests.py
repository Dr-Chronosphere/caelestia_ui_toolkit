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

bad = [m for mode, m in msgs if mode in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg)
       and "scheme watching unavailable" not in m]
for m in bad:
    print("  warning:", m)
check(not bad, "no unexpected QML warnings")
print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
