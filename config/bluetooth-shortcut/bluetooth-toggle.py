#!/usr/bin/env python3
"""Raccourci global AltGr+; -> allume/éteint le Bluetooth (KDE/Wayland).

Passe par KGlobalAccel (le système de raccourcis globaux de KDE), donc
fonctionne sous Wayland sans accès brut aux périphériques d'entrée.

Détail important : sur un clavier français, AltGr+; ne produit pas le
caractère « ; » mais le symbole de niveau 3 de la touche <AB08> :
« • » (fr basic), « × » (fr oss/nodeadkeys) ou « · » (fr oss_latin9).
XKB consomme AltGr pour produire ce symbole, donc KWin voit généralement
la touche SANS modificateur. On enregistre les deux formes (avec et sans
GroupSwitchModifier) pour couvrir toutes les variantes.
"""
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

COMP = "com.nico.bluetooth"
ACTION = "toggle"
GROUP = 0x40000000  # Qt::GroupSwitchModifier
KEYS = [
    0x2022,          # •  U+2022 BULLET      (fr par défaut)
    0x00D7,          # ×  multiplication     (fr oss / nodeadkeys)
    0x00B7,          # ·  point médian       (fr oss_latin9)
    GROUP | 0x2022,
    GROUP | 0x00D7,
    GROUP | 0x00B7,
]
ACTION_ID = [COMP, ACTION, "Bluetooth", "Basculer le Bluetooth"]
EMPTY_KEYS = dbus.Array([], signature="(ai)")

_last = 0.0


def find_adapter(sbus):
    """Renvoie le chemin D-Bus du premier adaptateur Bluetooth trouvé."""
    try:
        root = sbus.get_object("org.bluez", "/")
        om = dbus.Interface(root, "org.freedesktop.DBus.ObjectManager")
        for path, interfaces in om.GetManagedObjects().items():
            if "org.bluez.Adapter1" in interfaces:
                return str(path)
    except dbus.DBusException:
        pass
    return "/org/bluez/hci0"  # repli raisonnable


def toggle(*_args):
    global _last
    now = time.time()
    if now - _last < 0.4:  # évite les doubles déclenchements
        return
    _last = now

    try:
        sbus = dbus.SystemBus()
        path = find_adapter(sbus)
        obj = sbus.get_object("org.bluez", path)
        props = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
        state = bool(props.Get("org.bluez.Adapter1", "Powered"))
        new = not state
        props.Set("org.bluez.Adapter1", "Powered", dbus.Boolean(new))
        msg = "Bluetooth activé" if new else "Bluetooth désactivé"
    except Exception as exc:  # noqa: BLE001 - on veut toujours prévenir
        msg = f"Erreur Bluetooth : {exc}"

    print(msg, flush=True)
    try:
        import subprocess

        subprocess.run(["notify-send", "-a", "Bluetooth", msg], check=False, timeout=3)
    except Exception:
        pass


def register_shortcut(bus):
    kga = bus.get_object("org.kde.kglobalaccel", "/kglobalaccel")
    kga.doRegister(ACTION_ID, dbus_interface="org.kde.KGlobalAccel")

    # Infos KGlobalShortcutInfo : (uniqueName, friendlyName, componentUnique,
    # componentFriendly, ...). KGlobalAccel attend l'actionId dans l'ordre
    # [componentUnique, actionUnique, componentFriendly, actionFriendly].
    for key in KEYS:
        for info in kga.getGlobalShortcutsByKey(key, dbus_interface="org.kde.KGlobalAccel"):
            uid, ufriendly, cid, cfriendly = (str(info[i]) for i in range(4))
            if cid == COMP and uid == ACTION:
                continue
            kga.setForeignShortcutKeys(
                [cid, uid, cfriendly, ufriendly],
                EMPTY_KEYS,
                dbus_interface="org.kde.KGlobalAccel",
            )

    keys = dbus.Array(KEYS, signature="i")
    result = kga.setShortcut(
        ACTION_ID, keys, dbus.UInt32(6), dbus_interface="org.kde.KGlobalAccel"
    )  # 2 = SetPresent, 4 = NoAutoloading (on ignore l'ancien réglage sauvegardé)
    return kga, result


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    kga, result = register_shortcut(bus)
    print(f"Raccourci enregistré : {result}", flush=True)

    path = str(kga.getComponent(COMP, dbus_interface="org.kde.KGlobalAccel"))
    bus.add_signal_receiver(
        toggle,
        signal_name="globalShortcutPressed",
        dbus_interface="org.kde.kglobalaccel.Component",
        path=path,
        bus_name="org.kde.kglobalaccel",
    )
    print(f"Écoute de {path} (AltGr+;)", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
