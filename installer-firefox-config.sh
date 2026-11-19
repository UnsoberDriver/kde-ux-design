#!/usr/bin/env bash
# =============================================================================
#  Configuration Firefox (Flatpak) - personnalisation utilisateur
#  Bazzite / KDE Plasma (Wayland)
# =============================================================================
#
#  RÉSULTAT
#    - Barre personnelle (favoris) en icônes seules (masque les libellés,
#      masque le bouton d'import, ajuste l'espacement) via userChrome.css
#    - Activation du chargement de chrome/userChrome.css via user.js
#    - (Optionnel) Surcharge Flatpak pour l'intégration Plasma navigateur
#
#  FICHIERS (profil Firefox Flatpak)
#    ~/.var/app/org.mozilla.firefox/config/mozilla/firefox/<profil>/user.js
#    ~/.var/app/org.mozilla.firefox/config/mozilla/firefox/<profil>/chrome/userChrome.css
#    ~/.local/share/flatpak/overrides/org.mozilla.firefox
#
#  À CÔTÉ DE CE SCRIPT
#    config/firefox/user.js
#    config/firefox/chrome/userChrome.css
#    config/firefox/flatpak-override.org.mozilla.firefox
#    config/firefox/org.mozilla.firefox.desktop   (référence du lanceur surchargé)
#
#  UTILISATION
#    chmod +x installer-firefox-config.sh
#    ./installer-firefox-config.sh              # applique / répare
#    ./installer-firefox-config.sh --uninstall  # retire cette personnalisation
#
#  NOTE
#    - Redémarre Firefox pour prendre en compte les changements (user.js/userChrome).
#    - L'icône monochrome du lanceur Firefox est gérée par
#      installer-icones-monochromes.sh.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config/firefox"
FF_BASE="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
OVERRIDE_DST="$HOME/.local/share/flatpak/overrides/org.mozilla.firefox"

msg() { printf '\n\033[1;34m==>\\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

find_profile() {
  local ini="$FF_BASE/profiles.ini"
  local path=""
  if [ -f "$ini" ]; then
    # Prefer Install* Default, else Profile* with Default=1
    path="$(awk '
      /^\[Install/ {in_install=1; def=""}
      /^\[Profile/ {if(def!=""){print def; exit} in_install=0; in_prof=1; isrel=1; p=""; d=0}
      /^\[/ && $0 !~ /^\[Profile/ && $0 !~ /^\[Install/ {in_prof=0}
      in_install && /^Default=/ {sub(/^Default=/,""); def=$0}
      in_prof && /^IsRelative=/ {sub(/^IsRelative=/,""); if($0=="0") isrel=0}
      in_prof && /^Path=/ {sub(/^Path=/,""); p=$0}
      in_prof && /^Default=1/ {d=1}
      in_prof && d==1 && p!="" { if(isrel==1) print p; else print p; exit }
      END { if(def!="") print def }
    ' "$ini" | head -n1)"
  fi
  if [ -n "$path" ]; then
    if [ -d "$FF_BASE/$path" ]; then
      echo "$FF_BASE/$path"; return 0
    elif [ -d "$path" ]; then
      echo "$path"; return 0
    fi
  fi
  # fallback: first default-release profile
  local cand
  cand="$(find "$FF_BASE" -maxdepth 1 -type d -name '*.default-release' 2>/dev/null | head -n1 || true)"
  [ -n "$cand" ] && { echo "$cand"; return 0; }
  return 1
}

same_file() {
  [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"
}

uninstall() {
  msg "Désinstallation de la configuration Firefox personnalisée"
  local profile
  if profile="$(find_profile 2>/dev/null)"; then
    if same_file "$CONFIG_DIR/user.js" "$profile/user.js"; then
      rm -f "$profile/user.js"
      echo "  retiré: $profile/user.js"
    else
      warn "user.js conservé (différent de la config de référence): $profile/user.js"
    fi
    if same_file "$CONFIG_DIR/chrome/userChrome.css" "$profile/chrome/userChrome.css"; then
      rm -f "$profile/chrome/userChrome.css"
      rmdir "$profile/chrome" 2>/dev/null || true
      echo "  retiré: $profile/chrome/userChrome.css"
    else
      warn "userChrome.css conservé (différent/absent): $profile/chrome/userChrome.css"
    fi
  else
    warn "Profil Firefox introuvable, fichiers du profil non modifiés"
  fi
  if same_file "$CONFIG_DIR/flatpak-override.org.mozilla.firefox" "$OVERRIDE_DST"; then
    rm -f "$OVERRIDE_DST"
    echo "  retiré: $OVERRIDE_DST"
  else
    warn "Surcharge Flatpak conservée (différente/absente): $OVERRIDE_DST"
  fi
  msg "Terminé (redémarre Firefox si nécessaire)"
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
  exit 0
fi

[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }
[ -d "$CONFIG_DIR" ] || { echo "Dossier de config introuvable : $CONFIG_DIR"; exit 1; }
[ -d "$FF_BASE" ] || { echo "Firefox (Flatpak) introuvable: $FF_BASE"; exit 1; }

PROFILE="$(find_profile || true)"
[ -n "$PROFILE" ] || { echo "Profil Firefox introuvable dans $FF_BASE"; exit 1; }

msg "1/3  Configuration du profil Firefox: $PROFILE"
mkdir -p "$PROFILE/chrome"
install -m 0644 "$CONFIG_DIR/user.js" "$PROFILE/user.js"
install -m 0644 "$CONFIG_DIR/chrome/userChrome.css" "$PROFILE/chrome/userChrome.css"
echo "  installé: user.js"
echo "  installé: chrome/userChrome.css"

msg "2/3  Surcharge Flatpak (intégration Plasma navigateur)"
mkdir -p "$(dirname "$OVERRIDE_DST")"
install -m 0644 "$CONFIG_DIR/flatpak-override.org.mozilla.firefox" "$OVERRIDE_DST"
echo "  installé: $OVERRIDE_DST"

msg "3/3  Terminé"
cat <<'FIN'

  - Redémarre Firefox pour appliquer user.js et userChrome.css.
  - La barre personnelle affichera les favoris en icônes seules.
  - L'icône monochrome du lanceur est gérée par installer-icones-monochromes.sh.

  Désinstallation : ./installer-firefox-config.sh --uninstall
FIN
