#!/usr/bin/env python3
"""Headless test of the ported Fractal Map view, driven by upstream's fixture (PySide6 only)."""
import json
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QMetaObject, Q_ARG, Q_RETURN_ARG, Qt, QUrl, QtMsgType, qInstallMessageHandler
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
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.resize(1280, 800)
view.show()
failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


def settle(ms=150):
    QTest.qWait(ms)


check(view.status() == QQuickView.Status.Ready, f"Harness loads ({[e.toString() for e in view.errors()]})")
harness = view.rootObject()
fixture = (HERE / "fixture.json").read_text()


def ask(name, *args):
    r = QMetaObject.invokeMethod(harness, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
    return r.toVariant() if hasattr(r, "toVariant") else r


def call(fn, *args):
    args = list(args) + [None] * (4 - len(args))
    return ask("call", fn, *args)


def prop(name):
    return ask("get", name)


def log():
    return str(ask("logText"))


def reset_log():
    ask("clearLog")


def load(layout="lua:fractal"):
    ask("load", fixture, layout)
    settle(300)


def rects():
    return {r["id"]: r for r in json.loads(ask("rectsJson"))}


def centre(r):
    return r["x"] + r["w"] / 2, r["y"] + r["h"] / 2


LEFT, RIGHT = Qt.LeftButton.value, Qt.RightButton.value


def click(rid, button=1, shift=False):
    x, y = centre(rects()[rid])
    call("pointerPress", x, y, button, shift)
    call("pointerRelease", x, y)
    settle(50)


LEFT, RIGHT = Qt.LeftButton.value, Qt.RightButton.value
KEY = {k: getattr(Qt, "Key_" + k).value for k in ["Home", "Escape", "Return", "Left", "Right", "Up", "Down", "T", "Space", "1", "3", "Minus", "Equal", "Backspace", "A"]}
SHIFT, CTRL, NONE = Qt.ShiftModifier.value, Qt.ControlModifier.value, 0

# ---- layout from upstream fixture ----------------------------------------------------
load()
r = rects()
windows = [k for k, v in r.items() if v["isWindow"]]
check(len(windows) >= 3, f"fixture lays out windows ({sorted(windows)})")
check(prop("isFractal") is True, "layout recognised as fractal")
check(prop("cursorId") == "w2", f"cursor starts on the focused window ({prop('cursorId')})")
map_ok = all(0 <= v["x"] and v["x"] + v["w"] <= 1280 for v in r.values())
check(map_ok, "all tiles inside the map")

# ---- clicks ------------------------------------------------------------------------
reset_log()
click("w1")
check(log() == "zoom w1|dismiss", f"click window -> zoom + dismiss ({log()})")

reset_log()
click("w2", button=2)
check(log().startswith("zoom c0"), f"right-click -> zoom to parent ({log()})")

# ---- selection ---------------------------------------------------------------------
load()
reset_log()
click("w1", shift=True)
click("w2", shift=True)
check(prop("selectedCount") == 2, f"shift-click selects ({prop('selectedCount')})")
check(json.loads(ask("selectionJson")) == ["w1", "w2"], "selection ids")
click("w1")  # plain click while a selection exists toggles
check(prop("selectedCount") == 1, "plain click edits an existing selection")
call("handleKeyCode", KEY["Return"], NONE)
check(log() == "show w2|dismiss", f"Enter shows selection ({log()})")
check(prop("selectedCount") == 0, "selection cleared after show")

# marquee drag over the whole map selects every window
load()
reset_log()
x0, y0 = 1, 1
call("pointerPress", x0, y0, LEFT, False)
call("pointerMove", 600, 400)
call("pointerMove", 1270, 700)
check(prop("dragging") is True, "drag starts marquee")
call("pointerRelease", 1270, 700)
check(prop("selectedCount") == len(windows), f"marquee selects all windows ({prop('selectedCount')} of {len(windows)})")
call("handleKeyCode", KEY["Escape"], NONE)
check(prop("selectedCount") == 0 and "dismiss" not in log(), "Esc clears selection first")
call("handleKeyCode", KEY["Escape"], NONE)
check(log().endswith("dismiss"), "Esc again dismisses")

# ---- keys ------------------------------------------------------------------------
load()
reset_log()
for key, mods in [("Home", NONE), ("3", NONE), ("Left", SHIFT), ("Right", SHIFT), ("Up", SHIFT), ("Down", SHIFT), ("Minus", NONE), ("Equal", NONE), ("Backspace", NONE)]:
    call("handleKeyCode", KEY[key], mods)
check(log() == "zoom-root|frame 3|back|forward|zoom-out|zoom-in|zoom-out|zoom-in|hide w2", f"key bindings ({log()})")
before_cursor, before_log = prop("cursorId"), log()
for d in ("Left", "Right", "Up", "Down"):
    call("handleKeyCode", KEY[d], NONE)
check(log() == before_log, "plain arrows send no command")
check(prop("cursorId") in rects(), "cursor stays on a real tile after arrows")
t = prop("thumbnails")
call("handleKeyCode", KEY["T"], NONE)
check(prop("thumbnails") == (not t), "T toggles thumbnails")
call("handleKeyCode", KEY["A"], CTRL)
check(prop("selectedCount") == len(windows), "Ctrl+A selects all windows")

# ---- not-fractal state ---------------------------------------------------------------
load("dwindle")
check(prop("isFractal") is False, "other layout detected")
reset_log()
settle(200)
view.grabWindow().save(os.environ.get("MAP_SHOT", "/tmp/map") + "-notfractal.png")

load()
settle(300)
if os.environ.get("MAP_SHOT"):
    view.grabWindow().save(os.environ["MAP_SHOT"] + ".png")

bad = [m for mode, m in msgs if mode in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg)
       and "scheme watching unavailable" not in m]
for m in bad:
    print("  warning:", m)
check(not bad, "no unexpected QML warnings")
print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
