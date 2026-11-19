#!/usr/bin/env python3
"""Fond d'écran noir automatique et immédiat sur batterie.

Écoute le signal D-Bus de UPower (OnBattery) : aucune attenuation, pas de
sondage. Le fond actif est sauvegardé à chaque débranchement, puis restauré
au retour du secteur : c'est toujours le dernier fond utilisé qui revient.
Réglages : ~/.config/battery-wallpaper.conf
"""
import json
import os
import sys
from pathlib import Path

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import Gio, GLib

CONFIG = Path.home() / ".config/battery-wallpaper.conf"
STATE = Path.home() / ".local/state/battery-wallpaper"
ORIGINAL = STATE / "original.json"
APPLIED = STATE / "static-applied"
AC_ONLINE = Path(os.environ.get("BATTERY_WALLPAPER_AC", "/sys/class/power_supply/AC0/online"))

OBJ = dbus.SessionBus().get_object("org.kde.plasmashell", "/PlasmaShell")
IFACE = dbus.Interface(OBJ, "org.kde.PlasmaShell")


def plain(value):
    if isinstance(value, dbus.String):
        return str(value)
    if isinstance(value, dbus.Boolean):
        return bool(value)
    if isinstance(value, (dbus.Int16, dbus.Int32, dbus.Int64, dbus.Byte, dbus.UInt16, dbus.UInt32, dbus.UInt64)):
        return int(value)
    if isinstance(value, dbus.Double):
        return float(value)
    if isinstance(value, dbus.Struct):
        # KDE renvoie parfois la couleur sous forme de struct ARGB.
        parts = [plain(x) for x in value]
        if len(parts) == 1 and isinstance(parts[0], int):
            return "#%06x" % (parts[0] & 0xFFFFFF)
        return tuple(parts)
    if isinstance(value, dbus.Array):
        return [plain(x) for x in value]
    if isinstance(value, dbus.Dictionary):
        return {str(k): plain(x) for k, x in value.items()}
    return value


def get_wallpaper():
    cfg = plain(IFACE.wallpaper(0))
    return cfg.get("wallpaperPlugin", ""), cfg


def set_wallpaper(plugin, cfg):
    real = {}
    for key, value in cfg.items():
        if key.endswith("Default"):
            continue
        # dbus-python ne devine pas le signature d'une liste vide : on la type.
        if isinstance(value, list) and not value:
            value = dbus.Array([], signature="s")
        real[key] = value
    IFACE.setWallpaper(plugin, real, 0)


def load_config():
    conf = {"mode": "black", "image": "/usr/share/wallpapers/convergence.jxl", "color": "#000000"}
    if CONFIG.exists():
        for line in CONFIG.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                conf[key.strip()] = value.strip()
    return conf


def static_spec():
    conf = load_config()
    if conf.get("mode", "black") == "black":
        return "org.kde.color", {"Color": conf.get("color", "#000000")}
    return "org.kde.image", {
        "Image": conf.get("image", "/usr/share/wallpapers/convergence.jxl"),
        "FillMode": 2,
    }


def is_static(plugin, cfg):
    # Le marqueur APPLIED est la source de vérité : on ne compare que le
    # plugin. La couleur peut être renvoyée en '#000000' OU en struct ARGB,
    # et comparer les deux est fragile.
    return plugin == static_spec()[0]


def on_battery_file():
    try:
        return AC_ONLINE.read_text().strip() == "0"
    except OSError:
        return False


def on_battery_dbus():
    bus = dbus.SystemBus()
    obj = bus.get_object("org.freedesktop.UPower", "/org/freedesktop/UPower")
    return bool(obj.Get("org.freedesktop.UPower", "OnBattery", dbus_interface="org.freedesktop.DBus.Properties"))


def save_original(plugin, cfg):
    ORIGINAL.write_text(json.dumps({"plugin": plugin, "config": cfg}, indent=2))


def apply_static():
    plugin, cfg = static_spec()
    set_wallpaper(plugin, cfg)
    APPLIED.write_text(plugin)


def restore_original():
    if ORIGINAL.exists():
        data = json.loads(ORIGINAL.read_text())
        set_wallpaper(data["plugin"], data["config"])


def apply_state(on_bat):
    STATE.mkdir(parents=True, exist_ok=True)
    plugin, cfg = get_wallpaper()
    if on_bat:
        # On capture le fond actif à chaque débranchement : si l'utilisateur
        # a changé de fond sur secteur, c'est ce dernier qui sera restauré.
        if not is_static(plugin, cfg):
            save_original(plugin, cfg)
        if not APPLIED.exists() or not is_static(plugin, cfg):
            apply_static()
            print("batterie : fond noir appliqué", flush=True)
    elif APPLIED.exists():
        if ORIGINAL.exists() and is_static(plugin, cfg):
            restore_original()
            print("secteur : dernier fond restauré", flush=True)
        APPLIED.unlink(missing_ok=True)


def sync():
    apply_state(on_battery_file())


def watch():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    def on_change(interface, changed, invalidated, path=None):
        if "OnBattery" in changed:
            apply_state(bool(changed["OnBattery"]))

    bus.add_signal_receiver(
        on_change,
        signal_name="PropertiesChanged",
        dbus_interface="org.freedesktop.DBus.Properties",
        bus_name="org.freedesktop.UPower",
        path="/org/freedesktop/UPower",
        arg0="org.freedesktop.UPower",
    )

    # Les tests peuvent surcharger le chemin AC : on surveille alors ce
    # fichier en plus du signal UPower.
    monitor = None
    test_path = os.environ.get("BATTERY_WALLPAPER_AC")
    if test_path:
        gfile = Gio.File.new_for_path(test_path)
        monitor = gfile.monitor_file(Gio.FileMonitorFlags.NONE, None)
        monitor.connect("changed", lambda *args: apply_state(on_battery_file()))

    apply_state(on_battery_file() if test_path else on_battery_dbus())
    print("en écoute des changements d'alimentation (UPower)...", flush=True)
    GLib.MainLoop().run()


def status():
    plugin, cfg = get_wallpaper()
    print("alimentation :", "batterie" if on_battery_file() else "secteur")
    print("fond actuel  :", plugin, "|", cfg.get("WallpaperSource", cfg.get("Image", cfg.get("Color", ""))))
    print("statique     :", "oui" if is_static(plugin, cfg) else "non")
    print("sauvegarde   :", ORIGINAL if ORIGINAL.exists() else "aucune")


COMMANDS = {
    "sync": sync,
    "watch": watch,
    "status": status,
    "force-static": lambda: (STATE.mkdir(parents=True, exist_ok=True), apply_static()),
    "force-restore": restore_original,
}

if __name__ == "__main__":
    COMMANDS[sys.argv[1] if len(sys.argv) > 1 else "sync"]()
