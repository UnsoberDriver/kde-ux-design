#!/usr/bin/env bash
# =============================================================================
#  Num Lock activé à chaque démarrage de Plasma
#  KDE Plasma 6 / Wayland (Bazzite, etc.)
# =============================================================================
#
#  RÉSULTAT
#    - le pavé numérique (Num Lock) est activé automatiquement à chaque
#      démarrage de session Plasma
#
#  FICHIERS MODIFIÉS (aucun root nécessaire)
#    ~/.config/kcminputrc  -> section [Keyboard], clé NumLock=0 (activer)
#
#  À CÔTÉ DE CE SCRIPT
#    config/kcminputrc     -> copie de référence de la config appliquée
#    (réécrite à chaque exécution du script)
#
#  VALEURS DE LA CLÉ NumLock (kcminputrc)
#    0 = activer au démarrage
#    1 = désactiver au démarrage
#    2 = laisser l'état précédent (défaut KDE)
#
#  UTILISATION
#    chmod +x installer-numlock-toujours-actif.sh
#    ./installer-numlock-toujours-actif.sh              # applique / répare
#    ./installer-numlock-toujours-actif.sh --uninstall  # revient au défaut KDE
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SNAPSHOT_DIR="$SCRIPT_DIR/config"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation : retour au comportement KDE par défaut"
    kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock --delete
    msg "Terminé (Num Lock ne sera plus forcé à l'activation au démarrage)"
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }
command -v kwriteconfig6 >/dev/null || { echo "Commande manquante : kwriteconfig6"; exit 1; }

# ----------------------------------------------------------------------------
#  1. Configuration
# ----------------------------------------------------------------------------
msg "1/2  Activation du Num Lock au démarrage"
kwriteconfig6 --file kcminputrc --group Keyboard --key NumLock 0

# ----------------------------------------------------------------------------
#  2. Copie de référence
# ----------------------------------------------------------------------------
msg "2/2  Copie de référence"
mkdir -p "$CONFIG_SNAPSHOT_DIR"
if [ -f "$HOME/.config/kcminputrc" ]; then
    cp -a "$HOME/.config/kcminputrc" "$CONFIG_SNAPSHOT_DIR/kcminputrc"
fi

valeur="$(kreadconfig6 --file kcminputrc --group Keyboard --key NumLock 2>/dev/null || echo '?')"

msg "Installation terminée"
cat <<FIN

  NumLock (kcminputrc) : $valeur  (0 = activer au démarrage)

  Vérifier :
    kreadconfig6 --file kcminputrc --group Keyboard --key NumLock

  Le réglage sera appliqué au prochain démarrage de la session Plasma.
  (Paramètres système → Clavier → « Verrouillage numérique au démarrage de Plasma »)

  Désinstallation : ./installer-numlock-toujours-actif.sh --uninstall
FIN
