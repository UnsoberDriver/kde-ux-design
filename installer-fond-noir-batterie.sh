#!/usr/bin/env bash
# =============================================================================
#  Fond d'écran noir automatique sur batterie
#  KDE Plasma 6 / Wayland (Bazzite, etc.)
# =============================================================================
#
#  RÉSULTAT
#    - sur batterie : fond d'écran noir pur (#000000), immédiatement
#    - sur secteur  : le fond d'écran d'origine est restauré automatiquement
#
#  FICHIERS MODIFIÉS (aucun root nécessaire)
#    ~/.local/bin/battery-wallpaper.py           -> démon de bascule
#    ~/.config/battery-wallpaper.conf            -> réglages (noir / image)
#    ~/.config/systemd/user/battery-wallpaper.service
#    ~/.local/state/battery-wallpaper/           -> sauvegarde du dernier fond utilisé
#
#  À CÔTÉ DE CE SCRIPT
#    config/battery-wallpaper/  -> copies de référence (script, conf, service)
#
#  COMMENT ÇA MARCHE
#    Le démon écoute le signal D-Bus de UPower (OnBattery) : aucune attenuation,
#    aucun sondage. Le fond actif est sauvegardé à chaque débranchement puis
#    restauré au retour du secteur : c'est toujours le dernier fond utilisé
#    qui revient.
#
#  UTILISATION
#    chmod +x installer-fond-noir-batterie.sh
#    ./installer-fond-noir-batterie.sh              # applique / répare
#    ./installer-fond-noir-batterie.sh --uninstall  # retire et restaure le fond
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/config/battery-wallpaper"
BIN="$HOME/.local/bin/battery-wallpaper.py"
CONF="$HOME/.config/battery-wallpaper.conf"
UNIT="$HOME/.config/systemd/user/battery-wallpaper.service"
OLD_TIMER="$HOME/.config/systemd/user/battery-wallpaper.timer"
STATE="$HOME/.local/state/battery-wallpaper"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mErreur :\033[0m %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation : restauration du fond d'écran d'origine"
    if [ -f "$BIN" ]; then
        python3 "$BIN" force-restore >/dev/null 2>&1 || true
    fi
    systemctl --user disable --now battery-wallpaper.service >/dev/null 2>&1 || true
    systemctl --user disable --now battery-wallpaper.timer >/dev/null 2>&1 || true
    rm -f "$BIN" "$CONF" "$UNIT" "$OLD_TIMER"
    rm -rf "$STATE"
    systemctl --user daemon-reload || true
    msg "Terminé (le fond d'écran d'origine est restauré, le service est retiré)"
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || err "À lancer en tant qu'utilisateur normal, pas root."
[ -f "$SRC/battery-wallpaper.py" ] || err "Fichier manquant : $SRC/battery-wallpaper.py"
command -v python3 >/dev/null || err "python3 introuvable."
python3 -c 'import dbus, gi' 2>/dev/null || err "Il faut python3-dbus et python3-gobject (présents sur Bazzite)."
python3 -c 'import dbus; dbus.SessionBus()' 2>/dev/null || err "Session bus D-Bus introuvable (à lancer dans une session graphique)."
[ -d /sys/class/power_supply ] || err "/sys/class/power_supply introuvable."

# ----------------------------------------------------------------------------
#  1. Installation des fichiers
# ----------------------------------------------------------------------------
msg "1/3  Installation des fichiers utilisateur"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 "$SRC/battery-wallpaper.py" "$BIN"
install -m 644 "$SRC/battery-wallpaper.service" "$UNIT"
if [ -f "$CONF" ]; then
    msg "Configuration existante conservée : $CONF"
else
    install -m 644 "$SRC/battery-wallpaper.conf" "$CONF"
fi

# Ancienne version à base de timer (30 s de délai) : on la retire.
systemctl --user disable --now battery-wallpaper.timer >/dev/null 2>&1 || true
rm -f "$OLD_TIMER"

# ----------------------------------------------------------------------------
#  2. Activation du service
# ----------------------------------------------------------------------------
msg "2/3  Activation du service D-Bus UPower"
systemctl --user daemon-reload
systemctl --user enable battery-wallpaper.service
systemctl --user restart battery-wallpaper.service

# ----------------------------------------------------------------------------
#  3. Vérification
# ----------------------------------------------------------------------------
msg "3/3  Vérification"
if systemctl --user is-active --quiet battery-wallpaper.service; then
    echo "  Service actif. État actuel :"
    python3 "$BIN" status || true
else
    err "Le service ne démarre pas : journalctl --user -u battery-wallpaper.service"
fi

msg "Terminé. Débranche le chargeur : le noir apparaît instantanément."
