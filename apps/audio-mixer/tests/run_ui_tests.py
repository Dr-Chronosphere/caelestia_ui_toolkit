#!/usr/bin/env python3
"""Headless UI test for MixerView with a mock service (PySide6, no Quickshell/PipeWire)."""
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QMetaObject, Q_RETURN_ARG, Q_ARG, Qt, QUrl, QPoint, QtMsgType, qInstallMessageHandler
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
view.resize(480, 1100)
view.show()
app.processEvents()
root = view.rootObject()
failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


check(view.status() == QQuickView.Status.Ready, f"Harness loads ({[e.toString() for e in view.errors()]})")


def call(name, *args):
    ret = QMetaObject.invokeMethod(root, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
    return ret


def click(text):
    p = call("center", text)
    if p is None:
        return False
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(int(p.x()), int(p.y())))
    app.processEvents()
    return True


def log():
    return call("logText")


for label in ["Built-in Audio Analog Stereo", "WH-1000XM5", "HDMI / DisplayPort", "Firefox", "mpv"]:
    check(call("center", label) is not None, f"shows '{label}'")

# clicking a device row sets it as the default output
check(click("WH-1000XM5"), "found row")
check("default:bluez.xm5" in log(), f"click row -> setDefault ({log()})")

# routing chip for an app: Firefox is on speakers, so click the HDMI chip under it
# (the first 'HDMI / DisplayPort' text is the sink row; chips come later)
check(click("Play on 0 selected"), "combine button present")
check("combine" not in log(), "combine disabled with <2 members")

QTest.qWait(1200)
img = view.grabWindow()
img.save(str(Path(os.environ.get("MIXER_SHOT", "/tmp/mixer.png"))))

bad = [m for mode, m in msgs if mode in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg)
       and "scheme watching unavailable" not in m]
for m in bad:
    print("  warning:", m)
check(not bad, "no unexpected QML warnings")
print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
