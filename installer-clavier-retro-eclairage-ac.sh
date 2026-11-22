#!/usr/bin/env bash
# =============================================================================
#  Rétroéclairage clavier : max sur secteur, min sur batterie
#  ASUS V16 V3607VM — Bazzite / KDE Plasma 6 / Wayland
# =============================================================================
#
#  RÉSULTAT
#    - PC branché (secteur)   -> rétroéclairage clavier au niveau MAX
#    - PC débranché (batterie) -> rétroéclairage clavier au niveau MIN (0)
#
#  POURQUOI UN MINUTEUR (contournement bug noyau ASUS)
#    Sur l'ASUS V16 V3607VM, la LECTURE du niveau de rétroéclairage est cassée :
#      cat /sys/class/leds/asus::kbd_backlight/brightness -> toujours 0
#    L'ÉCRITURE fonctionne. Comme l'état réel est illisible, on réécrit le
#    niveau voulu régulièrement (toutes les 5 s) en fonction de l'état secteur.
#
#  FICHIERS (utilisateur, aucun root)
#    ~/.local/bin/kbd-backlight-ac.sh
#    ~/.config/systemd/user/kbd-backlight-ac.service
#    ~/.config/systemd/user/kbd-backlight-ac.timer
#
#  UTILISATION
#    chmod +x installer-clavier-retro-eclairage-ac.sh
#    ./installer-clavier-retro-eclairage-ac.sh              # installe / répare
#    ./installer-clavier-retro-eclairage-ac.sh --uninstall  # désinstalle
#
#  NOTE
#    - Désactive le minuteur kbd-backlight-keep.timer s'il est actif, car il
#      forcerait un niveau fixe et entrerait en conflit avec cette config.
#    - Correctif définitif : mise à jour noyau (quirk asus-wmi kbd_led_no_readback).
# =============================================================================

set -euo pipefail

BIN="$HOME/.local/bin/kbd-backlight-ac.sh"
SERVICE="$HOME/.config/systemd/user/kbd-backlight-ac.service"
TIMER="$HOME/.config/systemd/user/kbd-backlight-ac.timer"

msg() { printf '\n\033[1;34m==>\\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation"
    systemctl --user disable --now kbd-backlight-ac.timer 2>/dev/null || true
    rm -f "$SERVICE" "$TIMER" "$BIN"
    systemctl --user daemon-reload
    msg "Terminé (le rétroéclairage n'est plus ajusté automatiquement selon le secteur)"
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }

LED="$(ls -d /sys/class/leds/*kbd_backlight 2>/dev/null | head -1 || true)"
if [ -z "$LED" ]; then
    echo "Aucun rétroéclairage de clavier détecté (/sys/class/leds/*kbd_backlight)."
    echo "Ce correctif vise les portables ASUS (asus-wmi)."
    exit 1
fi
if [ ! -w "$LED/brightness" ]; then
    echo "Le fichier $LED/brightness n'est pas accessible en écriture."
    exit 1
fi

MAX="$(cat "$LED/max_brightness" 2>/dev/null || echo 3)"
AC_ONLINE=""
for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    type="$(cat "$d/type" 2>/dev/null || true)"
    if [ "$type" = "Mains" ] && [ -r "$d/online" ]; then
        AC_ONLINE="$d/online"
        break
    fi
done
if [ -z "$AC_ONLINE" ]; then
    warn "Aucune alimentation secteur (Mains/online) détectée; le script utilisera max par défaut."
fi

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"

# ----------------------------------------------------------------------------
#  1. Script d'application du niveau selon l'état secteur
# ----------------------------------------------------------------------------
msg "1/3  Script : $BIN"
cat >"$BIN" <<'SCRIPT'
#!/usr/bin/env bash
# Ajuste le rétroéclairage clavier selon l'alimentation :
#   secteur (AC online=1) -> MAX
#   batterie             -> MIN (0)
# La lecture brightness est cassée sur certains ASUS (toujours 0), donc on
# réécrit systématiquement la valeur voulue.
set -u

LED="$(ls -d /sys/class/leds/*kbd_backlight 2>/dev/null | head -1 || true)"
[ -n "$LED" ] || exit 0
[ -w "$LED/brightness" ] || exit 0

MAX="$(cat "$LED/max_brightness" 2>/dev/null || echo 3)"
AC_LEVEL="$MAX"
BAT_LEVEL="0"

on_ac=0
for d in /sys/class/power_supply/*; do
    [ -r "$d/type" ] || continue
    [ "$(cat "$d/type" 2>/dev/null || true)" = "Mains" ] || continue
    [ -r "$d/online" ] || continue
    if [ "$(cat "$d/online" 2>/dev/null || echo 0)" = "1" ]; then
        on_ac=1
        break
    fi
done

if [ "$on_ac" = "1" ]; then
    level="$AC_LEVEL"
else
    level="$BAT_LEVEL"
fi

[ "$level" -le "$MAX" ] 2>/dev/null || level="$MAX"
[ "$level" -ge 0 ] 2>/dev/null || level=0

printf '%s\n' "$level" >"$LED/brightness" 2>/dev/null || exit 0
SCRIPT
chmod +x "$BIN"

# ----------------------------------------------------------------------------
#  2. Service + minuteur systemd utilisateur
# ----------------------------------------------------------------------------
msg "2/3  Service + minuteur systemd (toutes les 5 s)"
cat >"$SERVICE" <<EOF
[Unit]
Description=Ajuste le rétroéclairage clavier selon secteur/batterie
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$BIN
EOF

cat >"$TIMER" <<'EOF'
[Unit]
Description=Vérifie régulièrement l'alimentation pour le rétroéclairage clavier

[Timer]
OnStartupSec=2s
OnUnitActiveSec=5s
AccuracySec=1s
Unit=kbd-backlight-ac.service

[Install]
WantedBy=timers.target
EOF

# ----------------------------------------------------------------------------
#  3. Activation immédiate
# ----------------------------------------------------------------------------
msg "3/3  Activation immédiate"
# Évite conflit avec l'ancien minuteur à niveau fixe
if systemctl --user is-enabled --quiet kbd-backlight-keep.timer 2>/dev/null \
   || systemctl --user is-active --quiet kbd-backlight-keep.timer 2>/dev/null; then
    warn "Désactivation de kbd-backlight-keep.timer (conflit avec le mode secteur/batterie)"
    systemctl --user disable --now kbd-backlight-keep.timer 2>/dev/null || true
fi

systemctl --user daemon-reload
systemctl --user enable --now kbd-backlight-ac.timer
systemctl --user start kbd-backlight-ac.service

state="batterie"
if [ -n "$AC_ONLINE" ] && [ "$(cat "$AC_ONLINE" 2>/dev/null || echo 0)" = "1" ]; then
    state="secteur"
fi

msg "Installation terminée"
echo
echo "  État actuel    : $state"
echo "  Sur secteur    : niveau $MAX / $MAX"
echo "  Sur batterie   : niveau 0 / $MAX"
echo "  Minuteur       : $(systemctl --user is-active kbd-backlight-ac.timer)"
echo
echo "Le niveau est réécrit toutes les 5 s (contournement du bug de lecture ASUS)."
echo "Désinstallation : ./installer-clavier-retro-eclairage-ac.sh --uninstall"
