#!/usr/bin/env python3
"""Headless UI test for the file manager against a temp directory tree (PySide6 only)."""
import os
import sys
import tempfile
import time
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import (QMetaObject, Q_ARG, Q_RETURN_ARG, Qt, QUrl, QPoint, QtMsgType,
                            qInstallMessageHandler)
from PySide6.QtGui import QGuiApplication, QImage, QColor
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
msgs = []
qInstallMessageHandler(lambda mode, ctx, msg: msgs.append((mode, msg)))

# --- fixture ---------------------------------------------------------------------
tmp = Path(tempfile.mkdtemp(prefix="filestest-"))
home = tmp / "home"
for d in ["Desktop", "Projects/sub", "Documents"]:
    (home / d).mkdir(parents=True)
(home / "Desktop/a.txt").write_text("a")
(home / "Projects/roadmap.pdf").write_bytes(b"%PDF" + b"0" * 2000)
(home / "Projects/notes.txt").write_text("n")
img = QImage(64, 64, QImage.Format_RGB32)
img.fill(QColor("#cc3366"))
img.save(str(home / "Projects/shot.png"))
(home / "readme.md").write_text("hi")
(home / ".hidden").write_text("x")

app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(str(REPO / "qml"))
view.setInitialProperties({"home": str(home)})
view.setSource(QUrl.fromLocalFile(str(HERE / "Harness.qml")))
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.resize(960, 640)
view.show()
failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


def settle(ms=400):
    QTest.qWait(ms)


check(view.status() == QQuickView.Status.Ready, f"Harness loads ({[e.toString() for e in view.errors()]})")
settle(800)
harness = view.rootObject()


def ask(name, *args):
    return QMetaObject.invokeMethod(harness, name, Q_RETURN_ARG("QVariant"),
                                    *[Q_ARG("QVariant", a) for a in args])


def prop(name):
    v = ask("get", name)
    return v.toVariant() if hasattr(v, "toVariant") else v


def setp(name, value):
    ask("set", name, value)
    settle()


def invoke(name, *args):
    args = list(args) + [None] * (2 - len(args))
    ask("call", name, *args)
    settle()


def center(text):
    return ask("center", text)


def click(text, double=False):
    p = center(text)
    if p is None:
        return False
    pt = QPoint(int(p.x()), int(p.y()))
    (QTest.mouseDClick if double else QTest.mouseClick)(view, Qt.LeftButton, Qt.NoModifier, pt)
    settle()
    return True


check(prop("path") == str(home), "starts at home")
check(prop("count") == 4, f"home lists 4 visible entries (got {prop('count')})")
places = str(ask("placeLabels")).split(",")
check(places == ["Home", "Desktop", "Documents"], f"places = existing standard dirs ({places})")

# open a folder with a double click on its tile, then check contents
check(click("Projects", double=True), "found 'Projects' tile")
check(prop("path") == str(home / "Projects"), f"double-click opens folder ({prop('path')})")
check(prop("count") == 4, f"Projects lists 4 entries ({prop('count')})")
check(prop("folderName") == "Projects", "folder name")

# search filter
ask("setSearch", "notes")
settle()
check(prop("count") == 1, f"search 'notes' -> 1 ({prop('count')})")
ask("setSearch", "")
settle()
check(prop("count") == 4, f"clearing search restores entries ({prop('count')})")

# back / forward / up
invoke("goBack")
check(prop("path") == str(home), "back returns home")
invoke("goForward")
check(prop("path") == str(home / "Projects"), "forward returns to Projects")
invoke("goUp")
check(prop("path") == str(home), "up returns home")
check(ask("backLength") >= 1, "history recorded")

# opening a file emits openRequested
invoke("go", str(home / "Projects"))
check(click("notes.txt", double=True), "found notes.txt tile")
check(harness.property("opened") == str(home / "Projects/notes.txt"), f"file open delegated ({harness.property('opened')})")

# sidebar navigation
check(click("Desktop"), "sidebar 'Desktop'")
check(prop("path") == str(home / "Desktop"), f"sidebar navigates ({prop('path')})")

# hidden files + sort + view mode
invoke("go", str(home))
setp("showHidden", True)
check(prop("count") == 5, f"showHidden reveals dotfile ({prop('count')})")
setp("showHidden", False)
invoke("cycleSort")
check(prop("sortLabel") == "Modified", f"cycleSort -> Modified ({prop('sortLabel')})")

# screenshots
shot = os.environ.get("FILES_SHOT")
invoke("go", str(home / "Projects"))
setp("selectedIndex", 0)
settle(900)
if shot:
    view.grabWindow().save(shot + "-grid.png")
setp("viewMode", "list")
settle(900)
if shot:
    view.grabWindow().save(shot + "-list.png")

bad = [m for mode, m in msgs if mode in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg)
       and "scheme watching unavailable" not in m]
for m in bad:
    print("  warning:", m)
check(not bad, "no unexpected QML warnings")
print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
