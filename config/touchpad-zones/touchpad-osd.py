#!/usr/bin/env python3
"""Overlay volume/luminosite en bas au milieu de l'ecran.

Pilote via FIFO : ecrire "vol 65", "bri 40" ou "mute" (une ligne par message).
Position exacte forcee par une regle KWin (titre "touchpad-osd").
"""

import os
import sys

from PySide6.QtCore import Qt, QTimer, QSocketNotifier, QLockFile
from PySide6.QtWidgets import QApplication, QWidget, QLabel, QProgressBar, QHBoxLayout

UID = os.getuid()
FIFO = f"/run/user/{UID}/touchpad-osd.fifo"
LOCK = f"/run/user/{UID}/touchpad-osd.lock"
WIDTH, HEIGHT = 400, 76
HIDE_MS = 1400


class Osd(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("touchpad-osd")
        self.setWindowFlags(Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.setFixedSize(WIDTH, HEIGHT)
        # Position de secours, si la regle KWin n'est pas (encore) active.
        g = QApplication.primaryScreen().availableGeometry()
        self.move(g.x() + (g.width() - WIDTH) // 2,
                  g.y() + g.height() - HEIGHT - 24)
        self.setStyleSheet(
            "QWidget { background: rgba(24, 24, 37, 232); border-radius: 18px; }"
            "QLabel { background: transparent; color: white; font-size: 15px; }"
            "QProgressBar { background: rgba(255,255,255,40); border: none; "
            "border-radius: 7px; height: 14px; text-align: center; }"
            "QProgressBar::chunk { background: #89b4fa; border-radius: 7px; }"
        )
        layout = QHBoxLayout(self)
        layout.setContentsMargins(20, 0, 20, 0)
        layout.setSpacing(12)
        self.kind_label = QLabel("Volume")
        self.kind_label.setFixedWidth(92)
        self.bar = QProgressBar()
        self.bar.setRange(0, 100)
        self.bar.setTextVisible(False)
        self.pct_label = QLabel("0%")
        self.pct_label.setFixedWidth(56)
        self.pct_label.setAlignment(Qt.AlignRight)
        layout.addWidget(self.kind_label)
        layout.addWidget(self.bar, 1)
        layout.addWidget(self.pct_label)
        self.hide_timer = QTimer(self)
        self.hide_timer.setSingleShot(True)
        self.hide_timer.timeout.connect(self.hide)

    def show_level(self, kind, value=None, muted=False):
        if kind == "bri":
            self.kind_label.setText("Luminosité")
            self.bar.setValue(value)
            self.pct_label.setText(f"{value}%")
        elif muted:
            self.kind_label.setText("Volume")
            self.bar.setValue(0)
            self.pct_label.setText("Muet")
        else:
            self.kind_label.setText("Volume")
            self.bar.setValue(value)
            self.pct_label.setText(f"{value}%")
        self.show()
        self.raise_()
        self.hide_timer.start(HIDE_MS)


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("touchpad-osd")
    lock = QLockFile(LOCK)
    if not lock.tryLock(100):
        print("un overlay tourne deja", flush=True)
        return 0
    try:
        os.mkfifo(FIFO, 0o600)
    except FileExistsError:
        pass
    osd = Osd()
    fd = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
    # ouvrir aussi en ecriture pour ne jamais recevoir EOF
    wfd = os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)

    def on_data():
        try:
            data = os.read(fd, 4096).decode(errors="ignore")
        except OSError:
            return
        for line in data.splitlines():
            parts = line.strip().split()
            if not parts:
                continue
            if parts[0] == "mute":
                osd.show_level("vol", muted=True)
            elif parts[0] in ("vol", "bri") and len(parts) == 2:
                try:
                    osd.show_level(parts[0], max(0, min(100, int(parts[1]))))
                except ValueError:
                    pass

    notifier = QSocketNotifier(fd, QSocketNotifier.Read)
    notifier.activated.connect(lambda: on_data())
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
