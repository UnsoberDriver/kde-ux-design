#!/usr/bin/env bash
# =============================================================================
#  AltGr + : bascule l'activité Discord « Larping »
#  KDE Plasma 6 / Wayland (Bazzite, etc.) — aucun root nécessaire
# =============================================================================
#
#  RÉSULTAT
#    AltGr + : (touche « : » du clavier azerty) active / désactive l'activité
#    « Larping » sur le profil Discord (« En train de jouer à Larping »).
#
#  POURQUOI UN DÉMON EVDEV ET PAS UN RACCOURCI KDE
#    Sous Wayland, KGlobalAccel ne peut pas écouter AltGr + : de façon fiable
#    (XKB consomme AltGr pour produire « · »). Le démon lit donc directement
#    le périphérique clavier via evdev, indépendamment du focus des fenêtres.
#
#  FICHIERS MODIFIÉS
#    ~/.local/bin/larping
#    ~/.config/systemd/user/larping.service
#
#  À CÔTÉ DE CE SCRIPT
#    config/larping/  -> copies de référence (script + service)
#
#  UTILISATION
#    chmod +x installer-larping-discord.sh
#    ./installer-larping-discord.sh              # applique / répare
#    ./installer-larping-discord.sh --uninstall  # retire
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/config/larping"
BIN="$HOME/.local/bin/larping"
UNIT="$HOME/.config/systemd/user/larping.service"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mErreur :\033[0m %s\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation de l'activité Discord Larping"
    systemctl --user disable --now larping.service >/dev/null 2>&1 || true
    rm -f "$BIN" "$UNIT"
    rm -rf "$HOME/.local/state/larping"
    systemctl --user daemon-reload || true
    msg "Terminé (service, script et état supprimés)."
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || err "À lancer en tant qu'utilisateur normal, pas root."
[ -f "$SRC/larping" ] || err "Fichier manquant : $SRC/larping"
[ -f "$SRC/larping.service" ] || err "Fichier manquant : $SRC/larping.service"
command -v python3 >/dev/null || err "python3 introuvable."

# ----------------------------------------------------------------------------
#  1. Installation des fichiers
# ----------------------------------------------------------------------------
msg "1/3  Installation des fichiers utilisateur"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 "$SRC/larping" "$BIN"
install -m 644 "$SRC/larping.service" "$UNIT"

# ----------------------------------------------------------------------------
#  2. Activation du service
# ----------------------------------------------------------------------------
msg "2/3  Activation du service utilisateur"
systemctl --user daemon-reload
systemctl --user enable larping.service
systemctl --user restart larping.service

# ----------------------------------------------------------------------------
#  3. Vérification
# ----------------------------------------------------------------------------
msg "3/3  Vérification"
if ! systemctl --user is-active --quiet larping.service; then
    err "Le service ne démarre pas : journalctl --user -u larping.service"
fi

journalctl --user -u larping.service -n 3 --no-pager || true

cat <<'EOF'

  Appuie sur AltGr + :  ->  ON  (« En train de jouer à Larping »)
  Réappuie              ->  OFF

  État actuel : ~/.local/bin/larping --status
  Bascule manuelle : ~/.local/bin/larping --toggle
  Journal : journalctl --user -u larping.service -f
EOF

msg "Terminé."
