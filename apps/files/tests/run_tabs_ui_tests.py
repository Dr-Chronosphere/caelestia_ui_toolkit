#!/usr/bin/env python3
"""Headless UI test for explorer tabs and window merging (PySide6 only)."""
import json
import os
import sys
import tempfile
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

tmp = Path(tempfile.mkdtemp(prefix="tabstest-"))
home = tmp / "home"
for d in ["Projects/sub", "Documents", "Desktop"]:
    (home / d).mkdir(parents=True)

app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(str(REPO / "qml"))
view.setInitialProperties({"home": str(home)})
view.setSource(QUrl.fromLocalFile(str(HERE / "TabsHarness.qml")))
view.resize(1000, 400)
view.show()
QTest.qWait(500)

failures = []


def check(cond, name):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


check(view.status() == QQuickView.Status.Ready, f"harness loads ({[e.toString() for e in view.errors()]})")
root = view.rootObject()


def ask(name, *args):
    r = QMetaObject.invokeMethod(root, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
    return r.toVariant() if hasattr(r, "toVariant") else r


def state():
    return json.loads(str(ask("json")))


def wait(ms=120):
    QTest.qWait(ms)


s = state()
check([w["id"] for w in s["windows"]] == ["1", "2"], "two windows")
t1 = s["windows"][0]["tabs"][0]
t2 = s["windows"][1]["tabs"][0]
check(json.loads(str(ask("chips", "1"))) == ["Home"] and json.loads(str(ask("chips", "2"))) == ["Projects"], "tab labels follow the folder")
check(ask("viewPath", "1", t1) == str(home), "tab view starts at its saved path")

# new tab opens after the active one and becomes active
ask("addTab", "1", str(home / "Documents"))
wait()
s = state()
w1 = s["windows"][0]
check(len(w1["tabs"]) == 2 and w1["active"] == w1["tabs"][1], "new tab is added and activated")
check(json.loads(str(ask("chips", "1"))) == ["Home", "Documents"], "two chips")
t1b = w1["tabs"][1]
check(ask("viewPath", "1", t1b) == str(home / "Documents"), "new tab shows its folder")

# navigating inside a tab is remembered in the saved state (so the tab can move)
ask("viewDo", "1", t1b, str(home / "Desktop"))
wait()
check(state()["states"][t1b]["path"] == str(home / "Desktop"), "navigation updates the tab's saved state")
check(state()["states"][t1b]["back"] == [str(home / "Documents")], "including its history")
check(ask("activeLabel", "1") == "Desktop", "window title follows the active tab")

# merge window 2 into window 1: tabs appended, the moved tab keeps its place
ask("setPreview", "1")
wait(300)
check(ask("previewOpacity", "1") == 1, "drop preview is shown on the target")
ask("mergeWindows", "2", "1")
ask("setPreview", "")
wait(300)
s = state()
check([w["id"] for w in s["windows"]] == ["1"], "source window is gone")
w1 = s["windows"][0]
check(w1["tabs"] == [t1, t1b, t2] and w1["active"] == t2, "its tab was appended and activated")
check(ask("viewPath", "1", t2) == str(home / "Projects"), "moved tab opens at the folder it was on")
check(json.loads(str(ask("chips", "1"))) == ["Home", "Desktop", "Projects"], "three chips after the merge")

# closing tabs
ask("closeTab", "1", t2)
wait()
w1 = state()["windows"][0]
check(w1["tabs"] == [t1, t1b] and w1["active"] == t1b, "closing the active tab activates its neighbour")
check(t2 not in state()["states"], "and drops its saved state")

bad = [m for mode, m in msgs if mode in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg) and "scheme watching unavailable" not in m]
for m in bad:
    print("  warning:", m)
check(not bad, "no unexpected QML warnings")
print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
