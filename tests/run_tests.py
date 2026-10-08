#!/usr/bin/env python3
"""Headless smoke tests for CaelestiaUI (needs PySide6; no Quickshell required).

    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software python3 tests/run_tests.py
"""
import json
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QMetaObject, Q_ARG, Q_RETURN_ARG, QUrl, qInstallMessageHandler, QtMsgType
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

ROOT = Path(__file__).resolve().parent.parent
messages = []


def handler(mode, ctx, msg):
    messages.append((mode, msg))


qInstallMessageHandler(handler)

app = QGuiApplication(sys.argv)
view = QQuickView()
view.engine().addImportPath(str(ROOT / "qml"))
view.setSource(QUrl.fromLocalFile(str(ROOT / "tests" / "Smoke.qml")))
failures = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


check(view.status() == QQuickView.Status.Ready, f"Smoke.qml loads ({view.errors()})")
view.show()
app.processEvents()
root = view.rootObject()


def pixel(x, y):
    app.processEvents()
    img = view.grabWindow()
    c = img.pixelColor(x, y)
    return c.name()


def swatch_colour():
    # swatch is the 40x40 rect at (8, 8)
    return pixel(28, 28)


# Default (dark) palette from the shell: primary #ffb0ca
check(swatch_colour() == "#ffb0ca", f"default primary rendered (got {swatch_colour()})")

# Apply a light scheme and verify live update
scheme = {"name": "test", "flavour": "x", "mode": "light",
          "colours": {"primary": "123456", "surface": "fefefe", "term0": "000000", "bogus": "ffffff"}}
ret = QMetaObject.invokeMethod(root, "apply", Q_RETURN_ARG(bool), Q_ARG(str, json.dumps(scheme)))
check(ret is True, "applyScheme accepts valid scheme")
check(swatch_colour() == "#123456", f"primary updates live (got {swatch_colour()})")
check(pixel(400, 500) == "#fefefe", f"surface updates live (got {pixel(400, 500)})")

ret = QMetaObject.invokeMethod(root, "apply", Q_RETURN_ARG(bool), Q_ARG(str, "{not json"))
check(ret is False, "applyScheme rejects invalid JSON")
ret = QMetaObject.invokeMethod(root, "apply", Q_RETURN_ARG(bool), Q_ARG(str, "{}"))
check(ret is False, "applyScheme rejects missing colours")
check(swatch_colour() == "#123456", "failed apply leaves palette untouched")

# No warnings other than the expected 'Quickshell unavailable' notice
bad = [m for mode, m in messages
       if mode in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg, QtMsgType.QtFatalMsg)
       and "scheme watching unavailable" not in m
       and "invalid scheme JSON" not in m]
for m in bad:
    print("  warning:", m)
check(not bad, "no unexpected QML warnings")

print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
