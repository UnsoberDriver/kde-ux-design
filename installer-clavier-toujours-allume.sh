#!/usr/bin/env bash
# =============================================================================
#  Rétroéclairage du clavier TOUJOURS allumé
#  ASUS V16 V3607VM — Bazzite / KDE Plasma 6 / Wayland
# =============================================================================
#
#  BUG NOYAU CONNU (spécifique à ce modèle)
#    Sur l'ASUS V16 V3607VM, la LECTURE du niveau de rétroéclairage est cassée :
#      cat /sys/class/leds/asus::kbd_backlight/brightness   -> toujours 0
#    même quand le clavier est physiquement allumé (voir bug Ubuntu #2171178).
#    Conséquence : systemd-backlight sauvegarde 0 à l'extinction et restaure
#    un clavier éteint au démarrage ; KDE/powerdevil ne voit pas le vrai niveau.
#    En revanche l'ÉCRITURE fonctionne (vérifié : le clavier s'allume bien).
#
#  SOLUTION (100 % utilisateur, aucun root)
#    Comme on ne peut pas lire l'état réel, on réécrit le niveau voulu
#    régulièrement. Cela garantit que le clavier reste allumé, y compris
#    après une extinction par un autre programme, une veille, etc.
#
#      1. ~/.local/bin/kbd-backlight-keep.sh
#           écrit le niveau voulu (défaut : 1 sur 3) dans le sysfs
#      2. ~/.config/systemd/user/kbd-backlight-keep.service
#      3. ~/.config/systemd/user/kbd-backlight-keep.timer
#           relance l'écriture toutes les 5 s
#
#  NIVEAU PAR DÉFAUT
#    1 (sur 3). Modifiable :
#      ./installer-clavier-toujours-allume.sh --level 2
#      ./installer-clavier-toujours-allume.sh --level 3
#
#  UTILISATION
#    chmod +x installer-clavier-toujours-allume.sh
#    ./installer-clavier-toujours-allume.sh              # installe / répare
#    ./installer-clavier-toujours-allume.sh --level 3    # niveau max
#    ./installer-clavier-toujours-allume.sh --uninstall  # désinstalle
#
#  NOTE
#    Le service système /etc/systemd/system/kbd-backlight.service (créé le
#    5 octobre) allume déjà le clavier au démarrage, avant la connexion.
#    Il est laissé en place : le minuteur ci-dessous prend le relais après
#    le login et corrige tout ce que le bug noyau peut éteindre ensuite.
#
#    Correctif définitif : une mise à jour du noyau (quirk asus-wmi
#    « kbd_led_no_readback ») rétablira une lecture fiable. D'ici là, cette
#    configuration est le contournement fiable.
# =============================================================================

set -euo pipefail

BIN="$HOME/.local/bin/kbd-backlight-keep.sh"
SERVICE="$HOME/.config/systemd/user/kbd-backlight-keep.service"
TIMER="$HOME/.config/systemd/user/kbd-backlight-keep.timer"
NIVEAU=1

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# ----------------------------------------------------------------------------
#  Arguments
# ----------------------------------------------------------------------------
ACTION="install"
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) ACTION="uninstall" ;;
        --level)
            [ $# -ge 2 ] || { echo "Il manque la valeur après --level (1 à 3)."; exit 1; }
            NIVEAU="$2"; shift ;;
        --level=*) NIVEAU="${1#--level=}" ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) echo "Option inconnue : $1"; exit 1 ;;
    esac
    shift
done

case "$NIVEAU" in
    1|2|3) ;;
    *) echo "--level doit valoir 1, 2 ou 3."; exit 1 ;;
esac

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "$ACTION" = "uninstall" ]; then
    msg "Désinstallation"
    systemctl --user disable --now kbd-backlight-keep.timer 2>/dev/null || true
    rm -f "$SERVICE" "$TIMER" "$BIN"
    systemctl --user daemon-reload
    msg "Terminé (le rétroéclairage n'est plus réécrit périodiquement)"
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
[ "$NIVEAU" -le "$MAX" ] || NIVEAU="$MAX"

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"

# ----------------------------------------------------------------------------
#  1. Script d'écriture du niveau
# ----------------------------------------------------------------------------
msg "1/3  Script : $BIN"
cat >"$BIN" <<'SCRIPT'
#!/usr/bin/env bash
# Réécrit le niveau de rétroéclairage du clavier.
# Appelé par kbd-backlight-keep.timer (toutes les 5 s).
#
# La lecture du niveau est cassée sur ASUS V16 V3607VM (toujours 0), donc on
# ne se fie pas à la valeur lue : on réécrit le niveau voulu.
set -u

NIVEAU_VOULU=__NIVEAU__

led="$(ls -d /sys/class/leds/*kbd_backlight 2>/dev/null | head -1 || true)"
[ -n "$led" ] || exit 0
[ -w "$led/brightness" ] || exit 0

max="$(cat "$led/max_brightness" 2>/dev/null || echo 3)"
[ "$NIVEAU_VOULU" -le "$max" ] 2>/dev/null || NIVEAU_VOULU="$max"

# Écriture directe : c'est elle qui allume réellement le clavier.
printf '%s\n' "$NIVEAU_VOULU" >"$led/brightness" 2>/dev/null || exit 0
SCRIPT
sed -i "s/^NIVEAU_VOULU=.*/NIVEAU_VOULU=$NIVEAU/" "$BIN"
chmod +x "$BIN"

# ----------------------------------------------------------------------------
#  2. Service + minuteur systemd utilisateur
# ----------------------------------------------------------------------------
msg "2/3  Service + minuteur systemd (toutes les 5 s)"
cat >"$SERVICE" <<EOF
[Unit]
Description=Garde le rétroéclairage du clavier allumé
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=$BIN
EOF

cat >"$TIMER" <<'EOF'
[Unit]
Description=Vérifie régulièrement que le rétroéclairage du clavier est allumé

[Timer]
OnStartupSec=2s
OnUnitActiveSec=5s
AccuracySec=1s
Unit=kbd-backlight-keep.service

[Install]
WantedBy=timers.target
EOF

# ----------------------------------------------------------------------------
#  3. Activation immédiate
# ----------------------------------------------------------------------------
msg "3/3  Activation immédiate"
systemctl --user daemon-reload
systemctl --user enable --now kbd-backlight-keep.timer
systemctl --user start kbd-backlight-keep.service

msg "Installation terminée"
echo
echo "  Rétroéclairage : niveau $NIVEAU / $MAX (lecture sysfs cassée : 0 = normal)"
echo "  Minuteur       : $(systemctl --user is-active kbd-backlight-keep.timer)"
echo
echo "Le niveau est réécrit toutes les 5 s : le clavier reste allumé même si"
echo "un programme, une veille ou le bug noyau de lecture l'éteint."
echo
echo "Changer le niveau : relancer avec --level 1|2|3"
echo "Désinstallation   : ./installer-clavier-toujours-allume.sh --uninstall"
