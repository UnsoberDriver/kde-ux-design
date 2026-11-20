#!/usr/bin/env bash
# =============================================================================
#  AltGr + ; bascule le Bluetooth
#  KDE Plasma 6 / Wayland (Bazzite, etc.) — aucun root nécessaire
# =============================================================================
#
#  RÉSULTAT
#    AltGr + ; allume / éteint immédiatement le Bluetooth, avec notification.
#
#  POURQUOI UN DÉMON ET PAS UN SIMPLE RACCOURCI KDE
#    Sur un clavier français, AltGr+; produit « • » (ou « × » / « · » selon
#    la variante), et XKB consomme AltGr : KWin voit donc une touche sans
#    modificateur. Le démon enregistre les symboles réels auprès de
#    KGlobalAccel, ce qui fonctionne sous Wayland sans accès brut au clavier.
#
#  FICHIERS MODIFIÉS
#    ~/.local/bin/bluetooth-toggle.py
#    ~/.config/systemd/user/bluetooth-toggle.service
#
#  À CÔTÉ DE CE SCRIPT
#    config/bluetooth-shortcut/  -> copies de référence (script + service)
#
#  UTILISATION
#    chmod +x installer-bluetooth-altgr-semicolon.sh
#    ./installer-bluetooth-altgr-semicolon.sh              # applique / répare
#    ./installer-bluetooth-altgr-semicolon.sh --uninstall  # retire
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/config/bluetooth-shortcut"
BIN="$HOME/.local/bin/bluetooth-toggle.py"
UNIT="$HOME/.config/systemd/user/bluetooth-toggle.service"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mErreur :\033[0m %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation du raccourci Bluetooth"
    systemctl --user disable --now bluetooth-toggle.service >/dev/null 2>&1 || true
    python3 - <<'PY' >/dev/null 2>&1 || true
import dbus
b = dbus.SessionBus()
i = b.get_object("org.kde.kglobalaccel", "/kglobalaccel")
i.unregister("com.nico.bluetooth", "toggle", dbus_interface="org.kde.KGlobalAccel")
PY
    rm -f "$BIN" "$UNIT"
    systemctl --user daemon-reload || true
    msg "Terminé (service et raccourci retirés)."
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || err "À lancer en tant qu'utilisateur normal, pas root."
[ -f "$SRC/bluetooth-toggle.py" ] || err "Fichier manquant : $SRC/bluetooth-toggle.py"
[ -f "$SRC/bluetooth-toggle.service" ] || err "Fichier manquant : $SRC/bluetooth-toggle.service"
command -v python3 >/dev/null || err "python3 introuvable."
python3 -c 'import dbus, gi' 2>/dev/null || err "Il faut python3-dbus et python3-gobject (présents sur Bazzite)."
python3 -c 'import dbus; dbus.SessionBus(); dbus.SystemBus()' 2>/dev/null || err "Bus D-Bus session/système introuvables."

# ----------------------------------------------------------------------------
#  1. Installation des fichiers
# ----------------------------------------------------------------------------
msg "1/3  Installation des fichiers utilisateur"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 "$SRC/bluetooth-toggle.py" "$BIN"
install -m 644 "$SRC/bluetooth-toggle.service" "$UNIT"

# ----------------------------------------------------------------------------
#  2. Activation du service
# ----------------------------------------------------------------------------
msg "2/3  Enregistrement du raccourci auprès de KGlobalAccel"
systemctl --user daemon-reload
systemctl --user enable bluetooth-toggle.service
systemctl --user restart bluetooth-toggle.service

# ----------------------------------------------------------------------------
#  3. Vérification
# ----------------------------------------------------------------------------
msg "3/3  Vérification"
if ! systemctl --user is-active --quiet bluetooth-toggle.service; then
    err "Le service ne démarre pas : journalctl --user -u bluetooth-toggle.service"
fi

python3 - <<'PY'
import dbus
b = dbus.SessionBus()
i = b.get_object("org.kde.kglobalaccel", "/kglobalaccel")
a = ["com.nico.bluetooth", "toggle", "Bluetooth", "Basculer le Bluetooth"]
keys = [hex(int(k)) for k in i.shortcut(a, dbus_interface="org.kde.KGlobalAccel")]
print("  Raccourci enregistré :", ", ".join(keys))
print("  Appuie sur AltGr + ; : une notification doit apparaître.")
PY

msg "Terminé."
