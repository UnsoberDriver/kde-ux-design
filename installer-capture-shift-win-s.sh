#!/usr/bin/env bash
# =============================================================================
#  Capture d'écran « Shift + Win + S » façon Windows
#  Testé sur Bazzite / KDE Plasma 6.8 / Wayland
# =============================================================================
#
#  RÉSULTAT
#    Shift + Win + S  ->  tu dessines une zone  ->  tu relâches  ->  terminé.
#    - aucune fenêtre, aucun bouton « Copier » à cliquer
#    - image copiée dans le presse-papier (Ctrl+V immédiat)
#    - fichier enregistré dans ~/Images/Captures d'écran/
#    - petite notification
#    - Échap annule (rien n'est créé)
#
#  ARCHITECTURE (3 briques)
#    1. ~/.local/bin/capture-region.sh
#         spectacle -r -b (capture de zone en arrière-plan) puis wl-copy
#    2. ~/.config/systemd/user/capture-region.service   (Type=oneshot)
#         lance le script proprement, indépendamment du shell
#    3. ~/.local/share/kwin/scripts/capture-region-silence/  (script kWin)
#         possède le raccourci Meta+Shift+S et démarre le service
#
#  RÉGLAGES SPECTACLE INDISPENSABLES (~/.config/spectaclerc)
#    useReleaseToCapture=true   -> termine dès le relâchement de la souris
#                                  (SANS ça, il faut cliquer sur « Copier »)
#    clipboardGroup=1           -> copie l'image automatiquement
#    autoSaveImage=true         -> enregistre le fichier automatiquement
#
#  POURQUOI LE SERVICE SYSTEMD + SCRIPT KWIN
#    - Spectacle est mono-instance et son interface graphique réapparaît si on
#      le lance normalement : le mode -b (arrière-plan) évite toute fenêtre.
#    - Un simple raccourci « commande » de KDE n'est pris en compte qu'à la
#      reconnexion de session ; un script kWin, lui, s'active à chaud.
#    - Spectacle se réattribue Shift+Win+S pour « Lancer Spectacle » à chaque
#      démarrage : le script libère ce raccourci (avant et après chaque capture)
#      et la config le réserve à la touche Impr. écran.
#
#  UTILISATION
#    chmod +x installer-capture-shift-win-s.sh
#    ./installer-capture-shift-win-s.sh              # installe / répare
#    ./installer-capture-shift-win-s.sh --uninstall  # désinstalle
# =============================================================================

set -euo pipefail

ID_SCRIPT="capture-region-silence"
BIN="$HOME/.local/bin/capture-region.sh"
SERVICE="$HOME/.config/systemd/user/capture-region.service"
KWIN_DIR="$HOME/.local/share/kwin/scripts/$ID_SCRIPT"
SHOT_DIR="$HOME/Images/Captures d'écran"
COMBINAISON="Meta+Shift+S"

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
    msg "Désinstallation"
    systemctl --user disable --now capture-region.service 2>/dev/null || true
    rm -f "$SERVICE" "$BIN"
    systemctl --user daemon-reload
    kwriteconfig6 --file kwinrc --group Plugins --key "${ID_SCRIPT}Enabled" false
    rm -rf "$KWIN_DIR"
    kwriteconfig6 --file kglobalshortcutsrc --group kwin --key CaptureRegionSilence --delete
    kwriteconfig6 --file kglobalshortcutsrc --group services --group org.kde.spectacle.desktop --key _launch --delete
    kwriteconfig6 --file spectaclerc --group General --key useReleaseToCapture false
    busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure 2>/dev/null || true
    msg "Terminé (Spectacle garde ses réglages de copie/enregistrement auto)"
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }
for cmd in spectacle wl-copy busctl notify-send kwriteconfig6 systemctl; do
    command -v "$cmd" >/dev/null || { echo "Commande manquante : $cmd"; exit 1; }
done

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$SHOT_DIR"

# ----------------------------------------------------------------------------
#  1. Le script de capture
# ----------------------------------------------------------------------------
msg "1/4  Script de capture : $BIN"
cat >"$BIN" <<'SCRIPT'
#!/usr/bin/env bash
# Capture silencieuse d'une région de l'écran (comportement « Shift+Win+S ») :
#  - sélection de la zone, aucune fenêtre ensuite
#  - enregistre l'image dans ~/Images/Captures d'écran
#  - copie l'image dans le presse-papier (Ctrl+V direct)
#  - notification discrète
# Échap annule : rien n'est enregistré.

set -uo pipefail

dir="$HOME/Images/Captures d'écran"
mkdir -p "$dir"
file="$dir/Capture d'écran_$(date +%Y%m%d_%H%M%S).png"

# Spectacle se réattribue « Shift+Win+S » pour son lancement : on libère le
# raccourci pour qu'il reste dédié à la capture silencieuse.
liberer_raccourci() {
    busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel \
        unregister ss "org.kde.spectacle.desktop" "_launch" >/dev/null 2>&1 || true
}
liberer_raccourci

# Évite deux captures simultanées
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/capture-region.lock"
flock -n 9 || exit 0

# -b = arrière-plan (aucune interface après la sélection)
# -n = pas de notification de Spectacle (on gère la nôtre)
# -o = fichier de sortie imposé
spectacle -r -b -n -o "$file" >/dev/null 2>&1
liberer_raccourci

# Capture annulée (Échap) : aucun fichier
[ -s "$file" ] || exit 0

# wl-copy reste vivant pour servir le presse-papier : il ne doit surtout pas
# hériter du descripteur du verrou, sinon il le garderait indéfiniment et
# toutes les captures suivantes seraient ignorées (flock -n échoue).
exec 9>&-

wl-copy --type image/png <"$file"

notify-send -a Spectacle -i image-x-generic \
    "Capture d'écran copiée" "$(basename "$file")" 2>/dev/null || true
SCRIPT
chmod +x "$BIN"

# ----------------------------------------------------------------------------
#  2. Service systemd utilisateur
# ----------------------------------------------------------------------------
msg "2/4  Service systemd : $SERVICE"
cat >"$SERVICE" <<EOF
[Unit]
Description=Capture d'écran d'une région (copie + enregistrement)
PartOf=graphical-session.target

[Service]
Type=oneshot
# Indispensable : wl-copy doit rester vivant après la fin du service pour
# fournir le presse-papier. Avec le KillMode par défaut (control-group),
# systemd tue wl-copy et le presse-papier est perdu.
KillMode=process
ExecStart=$BIN
EOF
systemctl --user daemon-reload

# ----------------------------------------------------------------------------
#  3. Script kWin (raccourci global)
# ----------------------------------------------------------------------------
msg "3/4  Script kWin : $KWIN_DIR"
mkdir -p "$KWIN_DIR/contents/code"
cat >"$KWIN_DIR/metadata.json" <<EOF
{
    "KPlugin": {
        "Id": "$ID_SCRIPT",
        "Name": "Capture d'écran silencieuse",
        "Description": "Capture une région, la copie dans le presse-papier et l'enregistre",
        "Icon": "spectacle",
        "License": "GPL-2.0+",
        "Version": "1.0",
        "EnabledByDefault": false
    },
    "KPackageStructure": "KWin/Script",
    "X-Plasma-API": "javascript",
    "X-Plasma-MainScript": "code/main.js"
}
EOF
cat >"$KWIN_DIR/contents/code/main.js" <<EOF
// Capture d'écran d'une région, silencieuse (aucune fenêtre Spectacle).
// Le raccourci démarre un service systemd utilisateur qui exécute le script.

registerShortcut(
    "CaptureRegionSilence",
    "Capture d'écran d'une région (copie + enregistrement)",
    "$COMBINAISON",
    function () {
        callDBus(
            "org.freedesktop.systemd1",
            "/org/freedesktop/systemd1",
            "org.freedesktop.systemd1.Manager",
            "StartUnit",
            "capture-region.service",
            "replace"
        );
    }
);
EOF

kwriteconfig6 --file kwinrc --group Plugins --key "${ID_SCRIPT}Enabled" true
# Mémorise le raccourci (survit aux mises à jour, modifiable dans Paramètres système)
kwriteconfig6 --file kglobalshortcutsrc --group kwin --key CaptureRegionSilence \
    "$COMBINAISON,none,Capture d'écran d'une région (copie + enregistrement)"

# ----------------------------------------------------------------------------
#  4. Réglages Spectacle + libération du raccourci
# ----------------------------------------------------------------------------
msg "4/4  Réglages Spectacle"
# useReleaseToCapture : LA clé du comportement « je relâche et c'est fini »
kwriteconfig6 --file spectaclerc --group General --key useReleaseToCapture true
kwriteconfig6 --file spectaclerc --group General --key clipboardGroup 1        # 1 = copier l'image
kwriteconfig6 --file spectaclerc --group General --key autoSaveImage true
kwriteconfig6 --file spectaclerc --group GuiConfig --key quitAfterSaveCopyExport true
kwriteconfig6 --file spectaclerc --group ImageSave --key imageSaveLocation \
    "file://$SHOT_DIR/"

# Shift+Win+S ne doit plus lancer Spectacle : on réserve sa touche de lancement
# à « Impr. écran », dès la prochaine session.
kwriteconfig6 --file kglobalshortcutsrc --group services --group org.kde.spectacle.desktop \
    --key _launch "Print,Print,Lancer Spectacle"

# Application à chaud
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
sleep 1
busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel \
    unregister ss "org.kde.spectacle.desktop" "_launch" >/dev/null 2>&1 || true

msg "Installation terminée"
cat <<'FIN'

Teste : Shift + Win + S -> dessine une zone -> relâche la souris.
  - plus aucune fenêtre ni bouton « Copier »
  - Ctrl + V dans n'importe quelle application
  - fichier dans ~/Images/Captures d'écran/

Si le raccourci ne réagit pas immédiatement :
  Paramètres système -> Raccourcis -> kWin -> « Capture d'écran d'une région »
Ou déconnecte/reconnecte la session une fois.

Désinstallation : ./installer-capture-shift-win-s.sh --uninstall
FIN
