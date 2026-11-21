#!/usr/bin/env bash
# =============================================================================
#  Barre des tâches épurée : trait blanc sous les applications ouvertes
#  KDE Plasma 6 / Wayland (Bazzite, Steam Deck…) — aucun root nécessaire
# =============================================================================
#
#  RÉSULTAT
#    - plus de widget CPU dans le panneau
#    - plus de bouton « réduire toutes les fenêtres »
#    - les applications épinglées restent intactes (Steam, Discord, Firefox,
#      Konsole, Spotify…) — aucune n'est retirée ni réordonnée
#    - une application ouverte est signalée par un trait blanc sous son icône
#    - aucun changement de couleur de fond : actif, inactif, minimisé,
#      attention et survol ont exactement le même fond transparent
#
#  POURQUOI UN THÈME LOCAL
#    Le gestionnaire de tâches dessine son fond et son indicateur avec les
#    éléments SVG de « widgets/tasks ». Le QML change de préfixe selon l'état
#    (normal / focus / minimized / attention / hover), ce qui colore tout le
#    bouton. Le thème local rend ces éléments transparents et ne garde que le
#    bord inférieur en blanc opaque. Le thème système n'est jamais modifié.
#
#  FICHIERS MODIFIÉS
#    ~/.local/share/plasma/desktoptheme/VaporWhiteLine/  -> thème local
#    ~/.config/plasmarc                                  -> thème actif
#    ~/.config/plasma-org.kde.plasma.desktop-appletsrc   -> applets du panneau
#    ~/.config/kwinrulesrc                               -> retrait des règles
#                                                           « skiptaskbar » qui
#                                                           masquent les fenêtres
#
#  À CÔTÉ DE CE SCRIPT
#    config/barre-taches/theme/  -> copies de référence du thème
#
#  SAUVEGARDE
#    ~/.local/state/barre-taches-trait-blanc/  -> fichiers d'origine (une fois)
#
#  UTILISATION
#    chmod +x installer-barre-taches-trait-blanc.sh
#    ./installer-barre-taches-trait-blanc.sh              # applique / répare
#    ./installer-barre-taches-trait-blanc.sh --uninstall  # retire et restaure
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/config/barre-taches/theme"
THEME="$HOME/.local/share/plasma/desktoptheme/VaporWhiteLine"
APPLETSRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
KWINRULES="$HOME/.config/kwinrulesrc"
PLASMARC="$HOME/.config/plasmarc"
STATE="$HOME/.local/state/barre-taches-trait-blanc"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mErreur :\033[0m %s\n' "$*" >&2; exit 1; }

restart_plasma() {
    msg "Redémarrage de Plasma"
    pkill -9 -x plasmashell 2>/dev/null || true
    # Le cache KSvg doit être vidé AVANT le redémarrage, sinon l'ancien SVG
    # (bordures colorées) est réutilisé.
    rm -f "$HOME/.cache/ksvg-elements" \
          "$HOME/.cache/plasma_theme_VaporWhiteLine.kcache" \
          "$HOME/.cache/plasma_theme_default.kcache"
    for _ in $(seq 1 10); do
        pgrep -x plasmashell >/dev/null && break
        sleep 1
    done
    pgrep -x plasmashell >/dev/null ||
        systemctl --user start plasma-plasmashell.service >/dev/null 2>&1 || true
}

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation : restauration de la barre d'origine"
    [ -d "$STATE" ] || err "Aucune sauvegarde trouvée dans $STATE"

    for f in plasma-org.kde.plasma.desktop-appletsrc kwinrulesrc plasmarc; do
        [ -f "$STATE/$f" ] || continue
        case "$f" in
            plasma-org.kde.plasma.desktop-appletsrc) cp -a "$STATE/$f" "$APPLETSRC" ;;
            kwinrulesrc)                             cp -a "$STATE/$f" "$KWINRULES" ;;
            plasmarc)                                cp -a "$STATE/$f" "$PLASMARC"  ;;
        esac
    done

    rm -rf "$THEME" "$STATE"
    restart_plasma
    msg "Terminé (configuration d'origine restaurée)."
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || err "À lancer en tant qu'utilisateur normal, pas root."
[ -f "$SRC/widgets/tasks.svgz" ] || err "Fichier manquant : $SRC/widgets/tasks.svgz"
[ -f "$SRC/metadata.desktop" ] || err "Fichier manquant : $SRC/metadata.desktop"
[ -f "$APPLETSRC" ] || err "Fichier introuvable : $APPLETSRC"
command -v kwriteconfig6 >/dev/null || err "kwriteconfig6 introuvable."
command -v python3 >/dev/null || err "python3 introuvable."

# ----------------------------------------------------------------------------
#  1. Sauvegarde (une seule fois)
# ----------------------------------------------------------------------------
msg "1/5  Sauvegarde de la configuration d'origine"
mkdir -p "$STATE"
for f in "$APPLETSRC" "$KWINRULES" "$PLASMARC"; do
    [ -e "$f" ] || continue
    [ -e "$STATE/$(basename "$f")" ] || cp -a "$f" "$STATE/"
done

# ----------------------------------------------------------------------------
#  2. Thème local
# ----------------------------------------------------------------------------
msg "2/5  Installation du thème Vapor White Line"
mkdir -p "$THEME/widgets"
cp -a "$SRC/colors" "$SRC/plasmarc" "$SRC/metadata.desktop" "$THEME/"
cp -a "$SRC/widgets/plasmoidheading.svg" "$SRC/widgets/tasks.svgz" "$THEME/widgets/"
kwriteconfig6 --file plasmarc --group Theme --key name VaporWhiteLine

# ----------------------------------------------------------------------------
#  3. Applets du panneau
# ----------------------------------------------------------------------------
msg "3/5  Retrait du widget CPU et du bouton « réduire tout »"
python3 - "$APPLETSRC" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
blocks = []  # [entete ou None, [lignes]]
for line in p.read_text().splitlines():
    if line.startswith('[') and line.endswith(']'):
        blocks.append([line, []])
    else:
        if not blocks:
            blocks.append([None, []])
        blocks[-1][1].append(line)

# Repère le containment du panneau (en général [Containments][2])
panel_id = None
for head, body in blocks:
    if head and re.fullmatch(r'\[Containments\]\[\d+\]', head):
        if any(x.strip() == 'plugin=org.kde.panel' for x in body):
            panel_id = re.search(r'\[Containments\]\[(\d+)\]', head).group(1)
            break

if not panel_id:
    print('  Panneau introuvable : applets laissés tels quels.')
    sys.exit(0)

targets = {'org.kde.plasma.systemmonitor.cpu', 'org.kde.plasma.minimizeall'}
prefix = f'[Containments][{panel_id}][Applets]['
applet_re = re.compile(r'^\[Containments\]\[' + panel_id + r'\]\[Applets\]\[(\d+)\]')
to_remove = set()

for head, body in blocks:
    m = applet_re.match(head or '')
    if not m:
        continue
    for line in body:
        if line.startswith('plugin=') and line.split('=', 1)[1].strip() in targets:
            to_remove.add(m.group(1))
            break

if not to_remove:
    print('  Déjà épuré (aucun widget CPU ni bouton « réduire tout »).')
    sys.exit(0)

out = []
for head, body in blocks:
    m = applet_re.match(head or '')
    if m and m.group(1) in to_remove:
        continue  # supprime l'applet ET ses sous-sections
    if head == f'[Containments][{panel_id}][General]':
        new_body = []
        for line in body:
            if line.startswith('AppletOrder='):
                ids = [i for i in line.split('=', 1)[1].split(';') if i and i not in to_remove]
                new_body.append('AppletOrder=' + ';'.join(ids))
            else:
                new_body.append(line)
        body = new_body
    if head is not None:
        out.append(head)
    out.extend(body)

p.write_text('\n'.join(out) + '\n')
print('  Applets retirés :', ', '.join(sorted(to_remove)))
PY

# ----------------------------------------------------------------------------
#  4. Règles KWin « skiptaskbar »
# ----------------------------------------------------------------------------
msg "4/5  Nettoyage des règles qui masquent les fenêtres"
python3 - "$KWINRULES" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
if not p.exists():
    print('  Aucun fichier kwinrulesrc.')
    sys.exit(0)

blocks = []
for line in p.read_text().splitlines():
    if line.startswith('[') and line.endswith(']'):
        blocks.append([line, []])
    else:
        if not blocks:
            blocks.append([None, []])
        blocks[-1][1].append(line)

num = re.compile(r'^\[(\d+)\]$')
to_remove = {
    num.match(head).group(1)
    for head, body in blocks
    if head and num.match(head)
    and any(re.match(r'\s*skiptaskbar\s*=\s*true\b', x, re.I) for x in body)
}

if not to_remove:
    print('  Aucune règle skiptaskbar (rien à faire).')
    sys.exit(0)

out = []
for head, body in blocks:
    m = num.match(head or '')
    if m and m.group(1) in to_remove:
        continue
    if head == '[General]':
        new_body = []
        for line in body:
            if line.startswith('Order='):
                ids = [i for i in line.split('=', 1)[1].split(',') if i and i not in to_remove]
                new_body.append('Order=' + ','.join(ids))
            else:
                new_body.append(line)
        body = new_body
    if head is not None:
        out.append(head)
    out.extend(body)

p.write_text('\n'.join(out) + '\n')
print('  Règles retirées :', ', '.join(sorted(to_remove)))
PY

# ----------------------------------------------------------------------------
#  5. Redémarrage et vérification
# ----------------------------------------------------------------------------
restart_plasma

msg "5/5  Vérification"
printf '  Thème Plasma      : %s\n' "$(kreadconfig6 --file plasmarc --group Theme --key name)"
printf '  Applets du panneau: %s\n' "$(grep '^AppletOrder=' "$APPLETSRC" || true)"
printf '  Applications       : %s\n' "$(grep '^launchers=' "$APPLETSRC" | cut -d= -f2- || true)"
printf '  Widget CPU        : %s\n' "$(grep -c 'org.kde.plasma.systemmonitor.cpu' "$APPLETSRC" || true)"
printf '  Bouton réduire tout: %s\n' "$(grep -c 'org.kde.plasma.minimizeall' "$APPLETSRC" || true)"
printf '  Règle skiptaskbar  : %s\n' "$(grep -c -i 'skiptaskbar=true' "$KWINRULES" 2>/dev/null || true)"

msg "Terminé. Ouvre une application : un trait blanc apparaît sous son icône."
