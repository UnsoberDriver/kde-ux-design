#!/usr/bin/env bash
# =============================================================================
#  Veille, extinction d'écran et verrouillage : JAMAIS
#  ASUS V16 V3607VM — Bazzite / KDE Plasma 6.7 / Wayland
# =============================================================================
#
#  RÉSULTAT
#    - aucune veille automatique par inactivité (secteur/batterie/faible)
#    - aucune veille à la fermeture du capot
#    - l'écran ne s'éteint pas et ne s'assombrit pas automatiquement
#    - aucun verrouillage automatique (inactivité ou reprise de veille)
#    - la veille manuelle (systemctl suspend) et le verrouillage manuel
#      (Meta+L) restent disponibles
#
#  FICHIERS MODIFIÉS (aucun root nécessaire)
#    ~/.config/powerdevilrc      -> profils AC / Battery / LowBattery
#    ~/.config/kscreenlockerrc   -> verrouillage automatique
#
#  À CÔTÉ DE CE SCRIPT
#    config/powerdevilrc         -> copie de référence de la config appliquée
#    config/kscreenlockerrc      -> copie de référence de la config appliquée
#    (ces deux copies sont réécrites à chaque exécution du script)
#
#  IMPORTANT
#    Plasma 6.7 utilise des groupes imbriqués, par ex.
#      [AC][SuspendAndShutdown]  et  [AC][Display]
#    Un simple reparseConfiguration ne recharge pas l'action du capot :
#    le script redémarre plasma-powerdevil pour appliquer à chaud.
#    Les réglages persistent après redémarrage (fichiers ~/.config).
#
#  UTILISATION
#    chmod +x installer-veille-jamais.sh
#    ./installer-veille-jamais.sh              # applique / répare
#    ./installer-veille-jamais.sh --uninstall  # remet les défauts KDE
# =============================================================================

set -euo pipefail

PROFILS=(AC Battery LowBattery)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SNAPSHOT_DIR="$SCRIPT_DIR/config"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation : retour aux réglages KDE par défaut"

    for p in "${PROFILS[@]}"; do
        for key in AutoSuspendAction AutoSuspendIdleTimeoutSec LidAction; do
            kwriteconfig6 --file powerdevilrc --group "$p" \
                --group SuspendAndShutdown --key "$key" --delete
        done
        for key in LockBeforeTurnOffDisplay TurnOffDisplayWhenIdle \
                   TurnOffDisplayIdleTimeoutSec TurnOffDisplayIdleTimeoutWhenLockedSec \
                   DimDisplayWhenIdle DimDisplayIdleTimeoutSec; do
            kwriteconfig6 --file powerdevilrc --group "$p" \
                --group Display --key "$key" --delete
        done
    done

    for key in Autolock Timeout LockOnResume; do
        kwriteconfig6 --file kscreenlockerrc --group Daemon --key "$key" --delete
    done

    systemctl --user restart plasma-powerdevil.service 2>/dev/null || true
    busctl --user call org.kde.screensaver /ScreenSaver \
        org.kde.screensaver configure 2>/dev/null || true

    msg "Terminé (veille et verrouillage automatiques réactivés)"
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }
for cmd in kwriteconfig6 busctl systemctl; do
    command -v "$cmd" >/dev/null || { echo "Commande manquante : $cmd"; exit 1; }
done

# ----------------------------------------------------------------------------
#  1. Alimentation : ni veille, ni extinction/assombrissement de l'écran
# ----------------------------------------------------------------------------
msg "1/3  Profils d'alimentation (secteur, batterie, batterie faible)"
for p in "${PROFILS[@]}"; do
    # Veille : inactivité + capot
    kwriteconfig6 --file powerdevilrc --group "$p" --group SuspendAndShutdown \
        --key AutoSuspendAction 0
    kwriteconfig6 --file powerdevilrc --group "$p" --group SuspendAndShutdown \
        --key AutoSuspendIdleTimeoutSec 0
    kwriteconfig6 --file powerdevilrc --group "$p" --group SuspendAndShutdown \
        --key LidAction 0

    # Écran : pas d'extinction, pas de baisse de luminosité
    kwriteconfig6 --file powerdevilrc --group "$p" --group Display \
        --key TurnOffDisplayWhenIdle false
    kwriteconfig6 --file powerdevilrc --group "$p" --group Display \
        --key TurnOffDisplayIdleTimeoutSec -- -1
    kwriteconfig6 --file powerdevilrc --group "$p" --group Display \
        --key TurnOffDisplayIdleTimeoutWhenLockedSec -- -1
    kwriteconfig6 --file powerdevilrc --group "$p" --group Display \
        --key DimDisplayWhenIdle false
    kwriteconfig6 --file powerdevilrc --group "$p" --group Display \
        --key DimDisplayIdleTimeoutSec -- -1
    kwriteconfig6 --file powerdevilrc --group "$p" --group Display \
        --key LockBeforeTurnOffDisplay false
done

# ----------------------------------------------------------------------------
#  2. Verrouillage automatique désactivé
# ----------------------------------------------------------------------------
msg "2/3  Verrouillage automatique"
kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
kwriteconfig6 --file kscreenlockerrc --group Daemon --key Timeout 0
kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false

# ----------------------------------------------------------------------------
#  3. Application immédiate + vérifications
# ----------------------------------------------------------------------------
msg "3/3  Application immédiate"
systemctl --user restart plasma-powerdevil.service
busctl --user call org.kde.screensaver /ScreenSaver \
    org.kde.screensaver configure 2>/dev/null || true
sleep 1

# Copie de référence des fichiers réellement appliqués, à côté de l'installateur.
mkdir -p "$CONFIG_SNAPSHOT_DIR"
cp -a "$HOME/.config/powerdevilrc" "$CONFIG_SNAPSHOT_DIR/powerdevilrc"
cp -a "$HOME/.config/kscreenlockerrc" "$CONFIG_SNAPSHOT_DIR/kscreenlockerrc"

lid_raw="$(busctl --user call org.kde.Solid.PowerManagement \
    /org/kde/Solid/PowerManagement/Actions/HandleButtonEvents \
    org.kde.Solid.PowerManagement.Actions.HandleButtonEvents lidAction 2>/dev/null || echo 'i ?')"
lid_action="${lid_raw##* }"

msg "Installation terminée"
cat <<FIN

  Capot (action effective) : $lid_action  (0 = ne rien faire)
  Profils configurés       : ${PROFILS[*]}

  Vérifier les fichiers :
    kreadconfig6 --file powerdevilrc --group Battery --group SuspendAndShutdown --key LidAction
    kreadconfig6 --file powerdevilrc --group Battery --group Display --key TurnOffDisplayWhenIdle

  Test : ferme le capot ou laisse le PC inactif. Il doit rester allumé,
  sans extinction d'écran ni verrouillage. Meta+L verrouille toujours.

  Désinstallation : ./installer-veille-jamais.sh --uninstall
FIN

if [ "$lid_action" != "0" ]; then
    echo
    echo "ATTENTION : l'action du capot n'est pas 0. Déconnecte/reconnecte"
    echo "la session puis relance ce script."
    exit 1
fi
