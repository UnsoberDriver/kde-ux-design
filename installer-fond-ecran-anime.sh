#!/usr/bin/env bash
# =============================================================================
#  Fond d'écran animé (Wallpaper Engine for KDE - catsout)
#  KDE Plasma 6 (Wayland)
# =============================================================================
#
#  RÉSULTAT
#    - Applique la configuration du fond d'écran animé (plugin
#      com.github.catsout.wallpaperEngineKde) dans l'applet de bureau Plasma.
#
#  FICHIERS
#    ~/.config/plasma-org.kde.plasma.desktop-appletsrc  (section wallpaper)
#
#  À CÔTÉ DE CE SCRIPT
#    config/fond-ecran-anime/wallpaper-engine.json     -> config de référence
#
#  UTILISATION
#    chmod +x installer-fond-ecran-anime.sh
#    ./installer-fond-ecran-anime.sh              # applique / répare
#    ./installer-fond-ecran-anime.sh --uninstall  # retire la config du plugin
#
#  PRÉREQUIS / NOTES
#    - Nécessite le plugin Plasma "Wallpaper Engine for KDE"
#      (com.github.catsout.wallpaperEngineKde).
#    - Nécessite Steam / Wallpaper Engine Workshop avec le fond téléchargé.
#    - Les chemins/ID du workshop sont spécifiques à cette machine ; édite
#      config/fond-ecran-anime/wallpaper-engine.json si besoin avant d'appliquer.
#    - Le script met à jour la config Plasma ; un redémarrage de plasmashell
#      (ou une déconnexion/reconnexion) peut être nécessaire.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_JSON="$SCRIPT_DIR/config/fond-ecran-anime/wallpaper-engine.json"
APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
PLUGIN="com.github.catsout.wallpaperEngineKde"

msg() { printf '\n\033[1;34m==>\\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

read_json() {
  python3 - "$CONFIG_JSON" <<'PYTHON'
import json, sys
p=sys.argv[1]
with open(p, encoding='utf-8') as f:
    d=json.load(f)
cfg=d.get('config',{})
for k in ['FilterStr','PerOptChanged','SteamLibraryPath[$e]','WallpaperSource[$e]','WallpaperWorkShopId']:
    print(f"{k}\t{cfg.get(k,'')}")
PYTHON
}

uninstall() {
  msg "Désinstallation de la configuration fond d'écran animé"
  [ -f "$APPLETSRC" ] || { echo "Fichier absent: $APPLETSRC"; exit 0; }
  python3 - "$APPLETSRC" "$PLUGIN" <<'PYTHON'
import sys, re
path, plugin = sys.argv[1], sys.argv[2]
text=open(path,encoding='utf-8',errors='ignore').read()
# remove sections containing [Wallpaper][plugin][General]
parts=re.split(r'(?=^\[)', text, flags=re.M)
out=[]
for part in parts:
    if not part.strip():
        continue
    m=re.match(r'^\[([^\]]+)\]', part)
    if m and f'[Wallpaper][{plugin}][General]' in m.group(1):
        continue
    out.append(part)
open(path,'w',encoding='utf-8').write(''.join(out))
print('ok')
PYTHON
  echo "  section wallpaper $PLUGIN retirée (si présente)"
  msg "Terminé. Redémarre plasmashell ou reconnecte la session si nécessaire."
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
  exit 0
fi

[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }
[ -f "$CONFIG_JSON" ] || { echo "Config introuvable: $CONFIG_JSON"; exit 1; }
[ -f "$APPLETSRC" ] || { echo "Config Plasma introuvable: $APPLETSRC"; exit 1; }

if [ ! -d "$HOME/.local/share/plasma/wallpapers/$PLUGIN" ] && [ ! -d "/usr/share/plasma/wallpapers/$PLUGIN" ]; then
  warn "Plugin $PLUGIN non trouvé dans les dossiers Plasma wallpaper. L'application de la config peut ne pas avoir d'effet."
fi

msg "Application de la configuration du fond d'écran animé"
# read values
declare -A KV
while IFS=$'\t' read -r k v; do
  [ -n "$k" ] || continue
  KV["$k"]="$v"
done < <(read_json)

python3 - "$APPLETSRC" "$PLUGIN" "${KV[FilterStr]:-}" "${KV[PerOptChanged]:-true}" "${KV[SteamLibraryPath[\$e]]:-}" "${KV[WallpaperSource[\$e]]:-}" "${KV[WallpaperWorkShopId]:-}" <<'PYTHON'
import sys, re
path, plugin, filter_str, peropt, steam, source, wsid = sys.argv[1:8]
text=open(path,encoding='utf-8',errors='ignore').read()
lines=text.splitlines()
target_re=re.compile(r'^\[(.*)\]$')
section_key=f'[Wallpaper][{plugin}][General]'

# find containment sections that have wallpaperplugin or are desktop containment 1
# We'll update any section whose header contains the wallpaper plugin general key; if none, insert into [Containments][1]
out=[]
i=0
found=False
while i < len(lines):
    line=lines[i]
    m=target_re.match(line.strip())
    if m and section_key in m.group(1):
        found=True
        out.append(line)
        i+=1
        # replace keys in this section until next section
        seen=set()
        while i < len(lines) and not target_re.match(lines[i].strip()):
            if '=' in lines[i]:
                k=lines[i].split('=',1)[0].strip()
                if k in ('FilterStr','PerOptChanged','SteamLibraryPath[$e]','WallpaperSource[$e]','WallpaperWorkShopId'):
                    if k not in seen:
                        val={'FilterStr':filter_str,'PerOptChanged':peropt,'SteamLibraryPath[$e]':steam,'WallpaperSource[$e]':source,'WallpaperWorkShopId':wsid}[k]
                        out.append(f'{k}={val}')
                        seen.add(k)
                    i+=1
                    continue
            out.append(lines[i]); i+=1
        for k in ['FilterStr','PerOptChanged','SteamLibraryPath[$e]','WallpaperSource[$e]','WallpaperWorkShopId']:
            if k not in seen:
                val={'FilterStr':filter_str,'PerOptChanged':peropt,'SteamLibraryPath[$e]':steam,'WallpaperSource[$e]':source,'WallpaperWorkShopId':wsid}[k]
                out.append(f'{k}={val}')
        continue
    out.append(line); i+=1

if not found:
    # insert after [Containments][1] block or append
    ins=['','[Containments][1][Wallpaper]['+plugin+'][General]',
         f'FilterStr={filter_str}', f'PerOptChanged={peropt}',
         f'SteamLibraryPath[$e]={steam}', f'WallpaperSource[$e]={source}',
         f'WallpaperWorkShopId={wsid}']
    # try to place near first containment
    placed=False
    new=[]
    for idx,l in enumerate(out):
        new.append(l)
        if not placed and l.strip()=='[Containments][1]':
            # find end of containment 1 simple section? easier append later; but better insert before [Containments][2]
            pass
    # insert before [Containments][2] if exists
    out2=[]
    for l in out:
        if not placed and l.strip().startswith('[Containments][2]'):
            out2.extend(ins)
            placed=True
        out2.append(l)
    if not placed:
        out2.extend(ins)
    out=out2

open(path,'w',encoding='utf-8').write('\n'.join(out)+'\n')
print('ok')
PYTHON

msg "Terminé"
echo "  Redémarre plasmashell si nécessaire: kquitapp6 plasmashell && kstart plasmashell"
