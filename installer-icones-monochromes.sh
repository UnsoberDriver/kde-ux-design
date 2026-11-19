#!/usr/bin/env bash
# =============================================================================
#  Icônes d'applications en monochrome (blanc) pour thème sombre
#  Bazzite / KDE Plasma 6 (Wayland)
# =============================================================================
#
#  RÉSULTAT
#    - Icônes d'applications (logos) en monochrome blanc, adaptées aux thèmes
#      sombres, pour les applications système, Flatpak et quelques applis
#      courantes (Chromium, Dolphin, OpenCode, etc.).
#    - Crée des surcharges de lanceurs (.desktop) dans ~/.local/share/applications
#      et installe les icônes dans ~/.local/share/icons (compatible systèmes
#      immuables comme Bazzite).
#
#  FICHIERS (utilisateur)
#    ~/.local/share/icons/custom-black/*-mono.svg
#    ~/.local/share/icons/hicolor/scalable/apps/*-mono.svg
#    ~/.local/share/applications/<app>.desktop (surcharges pour applis détectées)
#    ~/.local/share/applications/opencode.desktop (créé si opencode est installé)
#
#  À CÔTÉ DE CE SCRIPT
#    config/icones-monochromes/*.svg -> icônes monochromes de référence
#
#  UTILISATION
#    chmod +x installer-icones-monochromes.sh
#    ./installer-icones-monochromes.sh              # applique / répare
#    ./installer-icones-monochromes.sh --uninstall  # supprime surcharges/icônes
#
#  NOTE
#    - Les icônes épinglées dans la barre des tâches peuvent garder l'ancien
#      rendu en cache : détache/réépingle l'appli depuis le menu des applications.
#    - Après installation, redémarre les applications (et si besoin la session
#      Plasma) pour voir les changements partout.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config/icones-monochromes"
ICON_DST="$HOME/.local/share/icons/custom-black"
HICOLOR_DST="$HOME/.local/share/icons/hicolor/scalable/apps"
APPS_DST="$HOME/.local/share/applications"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# basename.desktop -> icon-key-mono (sans .svg)
declare -A MAP=(
  [steam.desktop]=steam-mono
  [bazzite-steam-bpm.desktop]=steam-mono
  [com.discordapp.Discord.desktop]=discord-mono
  [org.mozilla.firefox.desktop]=firefox-mono
  [org.chromium.Chromium.desktop]=chromium-mono
  [org.kde.dolphin.desktop]=dolphin-mono
  [org.kde.konsole.desktop]=konsole-mono
  [systemsettings.desktop]=systemsettings-mono
  [kdesystemsettings.desktop]=systemsettings-mono
  [org.kde.kate.desktop]=kate-mono
  [org.kde.ark.desktop]=ark-mono
  [org.kde.spectacle.desktop]=spectacle-mono
  [org.kde.gwenview.desktop]=gwenview-mono
  [org.kde.okular.desktop]=okular-mono
  [org.kde.haruna.desktop]=haruna-mono
  [org.kde.kcalc.desktop]=kcalc-mono
  [org.kde.filelight.desktop]=filelight-mono
  [org.kde.kfind.desktop]=kfind-mono
  [org.kde.kinfocenter.desktop]=kinfocenter-mono
  [org.kde.kdeconnect.app.desktop]=kdeconnect-mono
  [org.kde.kdeconnect.nonplasma.desktop]=kdeconnect-mono
  [org.kde.kdeconnect.sms.desktop]=kdeconnect-mono
  [org.kde.krdc.desktop]=krdc-mono
  [org.kde.krfb.desktop]=krfb-mono
  [org.kde.kwalletmanager.desktop]=kwallet-mono
  [org.kde.kjournaldbrowser.desktop]=journal-mono
  [org.kde.kmenuedit.desktop]=kmenuedit-mono
  [org.kde.khelpcenter.desktop]=help-mono
  [org.kde.plasma-systemmonitor.desktop]=sysmon-mono
  [org.kde.kdebugsettings.desktop]=debug-mono
  [org.kde.plasma.emojier.desktop]=emojier-mono
  [org.gnome.DiskUtility.desktop]=disk-mono
  [btrfs-assistant.desktop]=btrfs-mono
  [firewall-config.desktop]=firewall-mono
  [nvidia-settings.desktop]=nvidia-mono
  [net.lutris.Lutris.desktop]=lutris-mono
  [io.github.kolunmi.Bazaar.desktop]=bazaar-mono
  [com.github.tchx84.Flatseal.desktop]=flatseal-mono
  [io.github.flattool.Warehouse.desktop]=warehouse-mono
  [it.mijorus.gearlever.desktop]=gearlever-mono
  [com.github.Matoking.protontricks.desktop]=protontricks-mono
  [com.vysp3r.ProtonPlus.desktop]=protonplus-mono
  [org.gimp.GIMP.desktop]=gimp-mono
  [org.darktable.Darktable.desktop]=darktable-mono
  [org.openrgb.OpenRGB.desktop]=openrgb-mono
  [org.gnome.Firmware.desktop]=firmware-mono
  [com.visualstudio.code.desktop]=vscode-mono
  [waydroid-container-restart.desktop]=waydroid-mono
  [Waydroid.desktop]=waydroid-mono
  [webapp-manager.desktop]=webapp-mono
  [bazzite-documentation.desktop]=docs-mono
  [discourse.desktop]=discourse-mono
  [io.github.rfrench3.bazzite-updater.desktop]=updater-mono
  [io.github.ublue_os.yafti_gtk.desktop]=yafti-mono
  [com.gerbilsoft.rom-properties.rp-config.desktop]=rom-mono
  [input-remapper-gtk.desktop]=input-mono
  [cardwire-gui.desktop]=cardwire-mono
  [bbrew.desktop]=bbrew-mono
  [io.github.DenysMb.Kontainer.desktop]=kontainer-mono
  [com.spotify.Client.desktop]=spotify-mono
  [btop.desktop]=btop-mono
  [nvtop.desktop]=nvtop-mono
  [yad-icon-browser.desktop]=yad-mono
)

find_source_desktop() {
  local base="$1"
  if [ -f "$APPS_DST/$base" ]; then echo "$APPS_DST/$base"; return 0; fi
  for d in /usr/share/applications /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do
    if [ -f "$d/$base" ]; then echo "$d/$base"; return 0; fi
  done
  return 1
}

is_app_desktop() {
  local f="$1"
  grep -q '^\[Desktop Entry\]' "$f" 2>/dev/null || return 1
  grep -q '^Type=Application' "$f" 2>/dev/null || return 1
  grep -qi '^NoDisplay=true' "$f" 2>/dev/null && return 1
  grep -qi '^Hidden=true' "$f" 2>/dev/null && return 1
  return 0
}

set_desktop_icon() {
  local src="$1" dst="$2" icon="$3"
  mkdir -p "$(dirname "$dst")"
  awk -v icon="$icon" '
    BEGIN{in_de=0; done=0}
    /^\[Desktop Entry\]/{in_de=1; print; next}
    in_de && /^\[/{
      if(!done){print "Icon=" icon; done=1}
      in_de=0
      print; next
    }
    in_de && /^Icon=/{
      print "Icon=" icon; done=1; next
    }
    {print}
    END{ if(in_de && !done) print "Icon=" icon }
  ' "$src" > "$dst"
}

uninstall() {
  msg "Désinstallation des icônes monochromes et surcharges"
  local removed=0
  # remove desktop overrides we created (identified by Icon pointing to our icons)
  if [ -d "$APPS_DST" ]; then
    while IFS= read -r -d '' f; do
      if grep -q "$ICON_DST" "$f" 2>/dev/null || grep -q "opencode-mono" "$f" 2>/dev/null; then
        rm -f "$f"
        printf '  retiré: %s\n' "$f"
        removed=$((removed+1))
      fi
    done < <(find "$APPS_DST" -maxdepth 1 -type f -name '*.desktop' -print0 2>/dev/null)
  fi
  # remove icons we installed
  if [ -d "$CONFIG_DIR" ]; then
    for svg in "$CONFIG_DIR"/*.svg; do
      [ -f "$svg" ] || continue
      local b; b="$(basename "$svg")"
      rm -f "$ICON_DST/$b" "$HICOLOR_DST/$b" 2>/dev/null || true
    done
  fi
  # refresh caches best-effort
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || kbuildsycoca6 >/dev/null 2>&1 || true
  msg "Terminé ($removed lanceur(s) retiré(s))"
  echo "Note : détache/réépingle les icônes de la barre des tâches si nécessaire."
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
  exit 0
fi

[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }
[ -d "$CONFIG_DIR" ] || { echo "Dossier d'icônes introuvable : $CONFIG_DIR"; exit 1; }

msg "1/4  Installation des icônes monochromes"
mkdir -p "$ICON_DST" "$HICOLOR_DST" "$APPS_DST"
icon_count=0
for svg in "$CONFIG_DIR"/*.svg; do
  [ -f "$svg" ] || continue
  b="$(basename "$svg")"
  cp -f "$svg" "$ICON_DST/$b"
  cp -f "$svg" "$HICOLOR_DST/$b"
  icon_count=$((icon_count+1))
done
# ensure hicolor theme index for cache
if [ ! -f "$HOME/.local/share/icons/hicolor/index.theme" ] && [ -f /usr/share/icons/hicolor/index.theme ]; then
  cp /usr/share/icons/hicolor/index.theme "$HOME/.local/share/icons/hicolor/index.theme"
fi
echo "  $icon_count icône(s) installée(s)"

msg "2/4  Surcharges de lanceurs (.desktop) pour les applications détectées"
applied=0
for base in "${!MAP[@]}"; do
  key="${MAP[$base]}"
  icon="$ICON_DST/${key}.svg"
  [ -f "$icon" ] || continue
  src="$(find_source_desktop "$base" || true)"
  [ -n "$src" ] || continue
  is_app_desktop "$src" || continue
  set_desktop_icon "$src" "$APPS_DST/$base" "$icon"
  printf '  ok: %s\n' "$base"
  applied=$((applied+1))
done

msg "3/4  OpenCode (si installé)"
if command -v opencode >/dev/null 2>&1 && [ -f "$ICON_DST/opencode-mono.svg" ]; then
  op_exec="$(command -v opencode)"
  cat > "$APPS_DST/opencode.desktop" <<EOF
[Desktop Entry]
Name=OpenCode
Comment=AI coding agent
Exec=${op_exec}
Icon=$ICON_DST/opencode-mono.svg
Terminal=true
Type=Application
Categories=Development;Utility;
StartupNotify=false
EOF
  echo "  ok: opencode.desktop ($op_exec)"
  applied=$((applied+1))
else
  echo "  opencode non trouvé (ignoré)"
fi

msg "4/4  Mise à jour des caches d'icônes"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
kbuildsycoca6 --noincremental >/dev/null 2>&1 || kbuildsycoca6 >/dev/null 2>&1 || true
if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell >/dev/null 2>&1 || true
fi

msg "Installation terminée ($applied lanceur(s) configuré(s))"
cat <<'FIN'

  - Redémarre les applications pour voir les nouvelles icônes.
  - Barre des tâches : si une icône épinglée ne change pas, détache-la puis
    réépingle-la depuis le menu des applications (cache du panneau).
  - Si besoin, déconnecte/reconnecte ta session Plasma.

  Désinstallation : ./installer-icones-monochromes.sh --uninstall
FIN
