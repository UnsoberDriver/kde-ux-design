#!/usr/bin/env bash
# =============================================================================
#  Zones du pavé tactile : bord gauche = volume, bord droit = luminosité
#  ASUS V16 V3607VM — Bazzite / KDE Plasma 6 / Wayland
# =============================================================================
#
#  RÉSULTAT
#    - 1 doigt posé au BORD GAUCHE puis glissé haut/bas : volume +/- (5 %)
#    - 1 doigt posé au BORD DROIT puis glissé haut/bas  : luminosité +/- (5 %)
#    - tap 3 doigts : Alt+F4 (ferme la fenêtre active)
#    - tap 3 doigts + clic physique : écran de déconnexion
#    - tap 4 doigts : Entrée
#    - un OSD discret (volume / luminosité) s'affiche en bas au milieu
#
#  IMPORTANT
#    Le moniteur est PASSIF : il observe /dev/input/event* sans intercepter les
#    événements. Le curseur, le clic et le scroll à 2 doigts continuent donc de
#    fonctionner normalement. Seules les bandes de 5 % aux bords (à la pose du
#    doigt) sont détournées.
#
#  ARCHITECTURE (5 briques)
#    1. ~/.local/bin/touchpad-zones.py   (démon, lit le pavé via python-evdev)
#    2. ~/.local/bin/touchpad-osd.py     (overlay Qt, piloté par un FIFO)
#    3. ~/.config/systemd/user/touchpad-zones.service + touchpad-osd.service
#    4. /etc/udev/rules.d/99-touchpad-volume.rules    (accès au pavé)
#       /etc/udev/rules.d/99-backlight-nico.rules    (accès à la luminosité)
#       -> nécessitent root, mais sont ignorées si elles sont déjà en place
#    5. règle KWin (kwinrulesrc) qui place l'OSD en bas au milieu
#
#  DÉPENDANCES
#    python3-evdev, python3-pyside6, wpctl (PipeWire), KDE Plasma 6 Wayland
#    (sur Bazzite ces paquets sont présents par défaut)
#
#  UTILISATION
#    chmod +x installer-touchpad-zones.sh
#    ./installer-touchpad-zones.sh            # installe / répare
#    ./installer-touchpad-zones.sh --debug    # journal détaillé du démon
#    ./installer-touchpad-zones.sh --uninstall
#
#  RÉGLAGE DES ZONES
#    Dans ~/.local/bin/touchpad-zones.py :
#      LEFT_FRACTION_1F / RIGHT_FRACTION_1F  largeur des bandes (5 %)
#      STEP_PX_1F                            sensibilité (160 px par cran)
#    X_MAX (4645) est la plage du ASCP1201:00 093A:3017 ; à ajuster si le
#    pavé tactile d'une autre machine a une autre résolution.
# =============================================================================

set -euo pipefail

BIN_ZONES="$HOME/.local/bin/touchpad-zones.py"
BIN_OSD="$HOME/.local/bin/touchpad-osd.py"
SERVICE_ZONES="$HOME/.config/systemd/user/touchpad-zones.service"
SERVICE_OSD="$HOME/.config/systemd/user/touchpad-osd.service"
UDEV_TOUCHPAD="/etc/udev/rules.d/99-touchpad-volume.rules"
UDEV_BACKLIGHT="/etc/udev/rules.d/99-backlight-nico.rules"
KWIN_TITLE="touchpad-osd"
OSD_W=400
OSD_H=76
OSD_MARGIN=24
DEBUG=0

msg() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }

# ----------------------------------------------------------------------------
#  Arguments
# ----------------------------------------------------------------------------
ACTION="install"
for arg in "$@"; do
    case "$arg" in
        --uninstall) ACTION="uninstall" ;;
        --debug) DEBUG=1 ;;
        -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
        *) echo "Option inconnue : $arg"; exit 1 ;;
    esac
done

# ----------------------------------------------------------------------------
#  Aides KConfig
# ----------------------------------------------------------------------------
kread() { kreadconfig6 --file kwinrulesrc --group "$1" --key "$2" 2>/dev/null || true; }

kwin_rule_find() {
    local i t
    for i in $(seq 1 50); do
        t="$(kread "$i" title)"
        if [ "$t" = "$KWIN_TITLE" ]; then printf '%s' "$i"; return 0; fi
    done
    return 1
}

kwin_rule_free_id() {
    local i
    for i in $(seq 1 50); do
        if [ -z "$(kreadconfig6 --file kwinrulesrc --group "$i" --list 2>/dev/null || true)" ]; then
            printf '%s' "$i"; return 0
        fi
    done
    printf '50'
}

kwin_rule_remove() {
    local rid="$1" order kept=""
    for key in Description title titlematch position positionrule size sizerule; do
        kwriteconfig6 --file kwinrulesrc --group "$rid" --key "$key" --delete 2>/dev/null || true
    done
    # KWin 6.8 tient la liste des règles dans [General] Order=…
    order="$(kread General Order)"
    local i
    for i in ${order//,/ }; do
        if [ "$i" = "$rid" ]; then continue; fi
        kept="${kept:+$kept,}$i"
    done
    kwriteconfig6 --file kwinrulesrc --group General --key Order "$kept"
}

# ----------------------------------------------------------------------------
#  Désinstallation
# ----------------------------------------------------------------------------
if [ "$ACTION" = "uninstall" ]; then
    msg "Désinstallation"
    systemctl --user disable --now touchpad-zones.service touchpad-osd.service 2>/dev/null || true
    rm -f "$SERVICE_ZONES" "$SERVICE_OSD" "$BIN_ZONES" "$BIN_OSD"
    rm -f "${XDG_RUNTIME_DIR:-/tmp}/touchpad-osd.fifo" "${XDG_RUNTIME_DIR:-/tmp}/touchpad-osd.lock"
    systemctl --user daemon-reload

    if rid="$(kwin_rule_find)"; then
        kwin_rule_remove "$rid"
        busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
        msg "Règle KWin de l'OSD supprimée"
    fi

    if [ -f "$UDEV_TOUCHPAD" ] || [ -f "$UDEV_BACKLIGHT" ]; then
        if sudo -n true 2>/dev/null; then
            sudo rm -f "$UDEV_TOUCHPAD" "$UDEV_BACKLIGHT"
            sudo udevadm control --reload-rules 2>/dev/null || true
            msg "Règles udev supprimées"
        else
            warn "Règles udev laissées en place (root requis). Pour les retirer :"
            echo "     sudo rm -f $UDEV_TOUCHPAD $UDEV_BACKLIGHT"
            echo "     sudo udevadm control --reload-rules"
        fi
    fi
    msg "Terminé"
    exit 0
fi

# ----------------------------------------------------------------------------
#  Vérifications
# ----------------------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || { echo "À lancer en tant qu'utilisateur normal, pas root."; exit 1; }
for cmd in python3 wpctl systemctl kwriteconfig6 kreadconfig6; do
    command -v "$cmd" >/dev/null || { echo "Commande manquante : $cmd"; exit 1; }
done
python3 -c 'import evdev' 2>/dev/null || {
    echo "Le module Python « evdev » est absent : installe python3-evdev."
    exit 1
}
OSD_OK=1
python3 -c 'import PySide6' 2>/dev/null || {
    OSD_OK=0
    warn "PySide6 absent : l'OSD ne sera pas installé (le reste fonctionne)."
}

# Nom exact du pavé tactile (nœud « Touchpad », pas le nœud « Mouse »)
TOUCHPAD_NAME="$(awk '
    /^N: Name=/ { gsub(/^N: Name="/, ""); gsub(/"$/, ""); name=$0 }
    /^H: Handlers=/ { if (name ~ /[Tt]ouchpad/ && name !~ /[Mm]ouse/) { print name; exit } }
' /proc/bus/input/devices)"
[ -n "$TOUCHPAD_NAME" ] || warn "Pavé tactile non identifié : règle udev ignorée."

BACKLIGHT_DIR="$(ls -d /sys/class/backlight/* 2>/dev/null | head -1 || true)"
[ -n "$BACKLIGHT_DIR" ] || { echo "Aucun rétroéclairage d'écran détecté."; exit 1; }
BACKLIGHT_KERNEL="$(basename "$BACKLIGHT_DIR")"

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"

# ----------------------------------------------------------------------------
#  1. Démon des zones
# ----------------------------------------------------------------------------
msg "1/5  Démon : $BIN_ZONES"
cat >"$BIN_ZONES" <<'PY'
#!/usr/bin/env python3
"""Zones tactiles : 1 doigt bord gauche -> volume, 1 doigt bord droit -> luminosite.
(Bazzite KDE / Wayland).

Moniteur passif : il observe /dev/input/event* sans intercepter les evenements.
Le curseur, le clic et le scroll 2 doigts continuent donc de fonctionner
normalement, en plus des bandes de bord.
"""

import glob
import os
import subprocess
import time

from evdev import InputDevice, ecodes

DEBUG = os.environ.get("TOUCHPAD_VOL_DEBUG") == "1"

TOUCHPAD_NAMES = ("ASCP1201", "Touchpad")
X_MAX = 4645  # plage ABS_X du ASCP1201:00 093A:3017 (0-4645)

# 1 doigt : bandes aux bords (le curseur bouge aussi -> zones limitees)
LEFT_FRACTION_1F = 0.05
RIGHT_FRACTION_1F = 0.05
# 2 doigts : zone gauche plus large (scroll classique)
LEFT_FRACTION_2F = 0.28
LEFT_X_MAX_1F = int(X_MAX * LEFT_FRACTION_1F)
RIGHT_X_MIN_1F = int(X_MAX * (1 - RIGHT_FRACTION_1F))
LEFT_X_MAX_2F = int(X_MAX * LEFT_FRACTION_2F)

STEP_PX_1F = 160  # cumul vertical (px) par cran a 1 doigt
STEP_PX_2F = 220  # ... a 2 doigts
VOLUME_STEP = "5%"
BRIGHT_STEP_PCT = 5  # cran de luminosite en % du max
BRIGHT_MIN_PCT = 5  # plancher pour eviter l'ecran noir
MIN_INTERVAL = 0.06  # delai mini entre 2 actions
VERTICAL_RATIO_1F = 2.0  # 1 doigt : |dy| doit depasser |dx| * ratio
VERTICAL_RATIO_2F = 1.2  # 2 doigts : idem (souple)
NOISE_GATE = 8  # ignore les micro-mouvements par frame
DEBUG_INTERVAL = 0.2  # delai mini entre 2 lignes de log en mode debug

# taps multi-doigts : 3 doigts -> Alt+F4, 4 doigts -> Entree
TAP_ACTIONS = {3: "altf4", 4: "enter"}
TAP_MAX_N = max(TAP_ACTIONS)
TAP_SIMULT_S = 0.12  # ecart maxi de pose entre les 3 doigts (simultaneite)
TAP_MAX_S = 0.35  # duree maxi du tap (pose -> relache complet)
TAP_MAX_MOVE = 150  # mouvement maxi du centroide pendant le tap (unites)
TAP_COOLDOWN = 1.0  # delai mini entre 2 Alt+F4

ABS_MT_SLOT = ecodes.ABS_MT_SLOT
ABS_MT_TRACKING_ID = ecodes.ABS_MT_TRACKING_ID
ABS_MT_POSITION_X = ecodes.ABS_MT_POSITION_X
ABS_MT_POSITION_Y = ecodes.ABS_MT_POSITION_Y

FIFO_PATH = f"/run/user/{os.getuid()}/touchpad-osd.fifo"


def osd_send(line):
    try:
        fd = os.open(FIFO_PATH, os.O_WRONLY | os.O_NONBLOCK)
        try:
            os.write(fd, (line + "\n").encode())
        finally:
            os.close(fd)
    except OSError:
        pass  # pas de lecteur (overlay eteint) : ignore


BACKLIGHT_DIR = (glob.glob("/sys/class/backlight/*")
                 or ["/sys/class/backlight/intel_backlight"])[0]
BACKLIGHT_BRIGHTNESS = BACKLIGHT_DIR + "/brightness"
BACKLIGHT_MAX = BACKLIGHT_DIR + "/max_brightness"


def find_touchpad():
    candidates = []
    for path in sorted(glob.glob("/dev/input/event*")):
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        if any(n in dev.name for n in TOUCHPAD_NAMES):
            candidates.append(dev)
    # prefere le noeud "Touchpad" au noeud "Mouse" du meme materiel
    for dev in candidates:
        if "Touchpad" in dev.name:
            for other in candidates:
                if other is not dev:
                    try:
                        other.close()
                    except OSError:
                        pass
            return dev
    return candidates[0] if candidates else None


def send_alt_f4(ui):
    """Emule Alt+F4 via le clavier virtuel uinput."""
    if ui is None:
        return False
    try:
        ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTALT, 1)
        ui.write(ecodes.EV_KEY, ecodes.KEY_F4, 1)
        ui.syn()
        time.sleep(0.05)
        ui.write(ecodes.EV_KEY, ecodes.KEY_F4, 0)
        ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTALT, 0)
        ui.syn()
        print("tap 3 doigts -> Alt+F4", flush=True)
        return True
    except OSError as e:
        print(f"envoi Alt+F4 impossible ({e})", flush=True)
        return False


def send_enter(ui):
    """Emule Entree via le clavier virtuel uinput."""
    if ui is None:
        return False
    try:
        ui.write(ecodes.EV_KEY, ecodes.KEY_ENTER, 1)
        ui.syn()
        time.sleep(0.03)
        ui.write(ecodes.EV_KEY, ecodes.KEY_ENTER, 0)
        ui.syn()
        print("tap 4 doigts -> Entree", flush=True)
        return True
    except OSError as e:
        print(f"envoi Entree impossible ({e})", flush=True)
        return False


def show_logout_dialog():
    """Affiche l'ecran de deconnexion (veille/redemarrer/eteindre/...)."""
    try:
        # busctl (qdbus n'existe plus dans Plasma 6)
        subprocess.run(["busctl", "--user", "call", "org.kde.kglobalaccel",
                        "/component/ksmserver",
                        "org.kde.kglobalaccel.Component", "invokeShortcut",
                        "s", "Log Out"],
                       check=False, capture_output=True, timeout=2)
        print("bureau actif -> ecran de deconnexion", flush=True)
        return True
    except (OSError, subprocess.SubprocessError) as e:
        print(f"ecran de deconnexion impossible ({e})", flush=True)
        return False


def open_uinput():
    try:
        from evdev import UInput
        ui = UInput({ecodes.EV_KEY: [ecodes.KEY_LEFTALT, ecodes.KEY_F4,
                                     ecodes.KEY_ENTER]},
                    name="touchpad-zones-keys")
        print("clavier virtuel uinput OK", flush=True)
        return ui
    except (OSError, ImportError) as e:
        print(f"uinput indisponible ({e}), Alt+F4 desactive", flush=True)
        return None


def set_volume(up: bool):
    arg = VOLUME_STEP + ("+" if up else "-")
    try:
        if up:
            subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"],
                           check=False, capture_output=True, timeout=2)
        subprocess.run(["wpctl", "set-volume", "-l", "1.0",
                        "@DEFAULT_AUDIO_SINK@", arg],
                       check=False, capture_output=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return
    show_volume_osd()


def get_volume_state():
    """Retourne (pourcent, muet) ou None."""
    try:
        out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                             check=False, capture_output=True,
                             timeout=2, text=True).stdout.strip()
        # "Volume: 0.55" ou "Volume: 0.55 [MUTED]"
        parts = out.split()
        pct = int(round(float(parts[1]) * 100))
        return pct, "MUTED" in out
    except (OSError, subprocess.SubprocessError, IndexError, ValueError):
        return None


def show_volume_osd():
    """Envoie le niveau a l'overlay bas milieu."""
    state = get_volume_state()
    if state is None:
        return
    pct, muted = state
    osd_send("mute" if muted else f"vol {pct}")


def read_backlight():
    """Retourne (actuel, max) ou None."""
    try:
        with open(BACKLIGHT_BRIGHTNESS) as f:
            cur = int(f.read().strip())
        with open(BACKLIGHT_MAX) as f:
            mx = int(f.read().strip())
        return cur, mx
    except (OSError, ValueError):
        return None


def show_brightness_osd(cur, mx):
    pct = int(round(cur * 100 / mx)) if mx else 0
    osd_send(f"bri {pct}")


def set_brightness(up: bool):
    vals = read_backlight()
    if vals is None:
        return
    cur, mx = vals
    step = max(1, mx * BRIGHT_STEP_PCT // 100)
    minimum = max(1, mx * BRIGHT_MIN_PCT // 100)
    new = min(mx, max(minimum, cur + step if up else cur - step))
    if new != cur:
        try:
            with open(BACKLIGHT_BRIGHTNESS, "w") as f:
                f.write(str(new))
        except OSError:
            return
    show_brightness_osd(new, mx)


def monitor(dev, ui):
    slots = {}
    slot = 0
    acc = 0.0
    last_action = 0.0
    last_debug = 0.0
    button_down = False  # clic physique du pave enfonce
    tap = None  # candidat tap multi-doigts
    last_tap_fire = 0.0
    for ev in dev.read_loop():
        if ev.type == ecodes.EV_KEY and ev.code == ecodes.BTN_LEFT:
            button_down = ev.value == 1
            if DEBUG:
                print(f"debug bouton clic={'enfonce' if button_down else 'relache'}",
                      flush=True)
        if ev.type == ecodes.EV_ABS:
            if ev.code == ABS_MT_SLOT:
                slot = ev.value
            elif ev.code == ABS_MT_TRACKING_ID:
                st = slots.setdefault(slot, {})
                st["active"] = ev.value != -1
                if ev.value == -1:
                    for k in ("x", "y", "px", "py", "sx", "sy", "t_land"):
                        st.pop(k, None)
                else:
                    st["fresh"] = True  # pose initiale a enregistrer
                    st["t_land"] = time.monotonic()
            elif ev.code == ABS_MT_POSITION_X:
                st = slots.setdefault(slot, {})
                st["x"] = ev.value
                if st.get("fresh") and "y" in st:
                    st["sx"], st["sy"] = st["x"], st["y"]
                    st.pop("fresh", None)
            elif ev.code == ABS_MT_POSITION_Y:
                st = slots.setdefault(slot, {})
                st["y"] = ev.value
                if st.get("fresh") and "x" in st:
                    st["sx"], st["sy"] = st["x"], st["y"]
                    st.pop("fresh", None)
        elif ev.type == ecodes.EV_SYN and ev.code == ecodes.SYN_REPORT:
            fingers = [s for s in slots.values()
                       if s.get("active") and "x" in s and "y" in s]
            n = len(fingers)
            now = time.monotonic()
            # --- taps multi-doigts (3=Alt+F4, 4=Entree) ---
            # appui physique (clic) a 3 doigts -> ecran de deconnexion
            if n in TAP_ACTIONS and tap is None and now - last_tap_fire >= TAP_COOLDOWN:
                if n == 3:
                    # les 3 doigts doivent atterrir en meme temps
                    lands = [f.get("t_land", now) for f in fingers]
                    if max(lands) - min(lands) > TAP_SIMULT_S:
                        tap = {"rejected": True}
                        if DEBUG:
                            print(f"debug tap 3 doigts non simultane "
                                  f"({max(lands)-min(lands):.2f}s), ignore",
                                  flush=True)
                    else:
                        tap = {"action": TAP_ACTIONS[n], "t0": now, "moved": 0.0, "n_prev": n,
                               "clicked": button_down,
                               "cx": sum(f["x"] for f in fingers) / n,
                               "cy": sum(f["y"] for f in fingers) / n}
                        if DEBUG:
                            print(f"debug candidat tap {n} doigts", flush=True)
                else:
                    tap = {"action": TAP_ACTIONS[n], "t0": now, "moved": 0.0, "n_prev": n,
                           "clicked": button_down,
                           "cx": sum(f["x"] for f in fingers) / n,
                           "cy": sum(f["y"] for f in fingers) / n}
                    if DEBUG:
                        print(f"debug candidat tap {n} doigts", flush=True)
            elif tap is not None:
                if tap.get("rejected"):
                    # pose echelonnee : attendre le relache complet sans rien faire
                    if n == 0 or n > TAP_MAX_N:
                        tap = None
                else:
                    if button_down:
                        tap["clicked"] = True
                    if n > TAP_MAX_N:
                        tap = None  # trop de doigts : annule
                    elif n == 0:
                        if now - tap["t0"] <= TAP_MAX_S and tap["moved"] <= TAP_MAX_MOVE:
                            if DEBUG and tap["action"] == "altf4":
                                print(f"debug tap feu: duree={now-tap['t0']:.2f}s "
                                      f"mouvement={tap['moved']:.0f} "
                                      f"clic={tap.get('clicked', False)}", flush=True)
                            if tap["action"] == "altf4":
                                if tap["clicked"]:
                                    ok = show_logout_dialog()
                                else:
                                    ok = send_alt_f4(ui)
                            else:
                                ok = send_enter(ui)
                            if ok:
                                last_tap_fire = now
                        tap = None
                    else:
                        if now - tap["t0"] > TAP_MAX_S:
                            tap = None  # trop lent : ce n'est pas un tap
                        elif n == tap["n_prev"]:
                            cx = sum(f["x"] for f in fingers) / n
                            cy = sum(f["y"] for f in fingers) / n
                            tap["moved"] += abs(cx - tap["cx"]) + abs(cy - tap["cy"])
                            tap["cx"], tap["cy"] = cx, cy
                            if tap["moved"] > TAP_MAX_MOVE:
                                tap = None  # swipe, pas un tap
                        else:
                            # doigts en cours de pose/relache : maj ref sans accumuler
                            tap["n_prev"] = n
                            if n:
                                tap["cx"] = sum(f["x"] for f in fingers) / n
                                tap["cy"] = sum(f["y"] for f in fingers) / n
            kind = None  # "vol" ou "bri"
            step = ratio = 0
            if len(fingers) == 1:
                # seule la position de POSE compte, pas la position courante :
                # partir du milieu et glisser vers le bord ne fait rien
                sx = fingers[0].get("sx")
                if sx is not None and sx <= LEFT_X_MAX_1F:
                    kind, step, ratio = "vol", STEP_PX_1F, VERTICAL_RATIO_1F
                elif sx is not None and sx >= RIGHT_X_MIN_1F:
                    kind, step, ratio = "bri", STEP_PX_1F, VERTICAL_RATIO_1F
            # note: le scroll 2 doigts reste un scroll normal (pas de volume)
            if DEBUG and fingers:
                now = time.monotonic()
                if now - last_debug >= DEBUG_INTERVAL:
                    last_debug = now
                    xs = [f["x"] for f in fingers]
                    sxs = [f.get("sx", "-") for f in fingers]
                    print(f"debug n={len(fingers)} xs={xs} sxs={sxs} "
                          f"mode={kind} acc={acc:.0f}", flush=True)
            if kind:
                if all("px" in f and "py" in f for f in fingers):
                    n = len(fingers)
                    cx = sum(f["x"] for f in fingers) / n
                    cy = sum(f["y"] for f in fingers) / n
                    pcx = sum(f["px"] for f in fingers) / n
                    pcy = sum(f["py"] for f in fingers) / n
                    dx, dy = cx - pcx, cy - pcy
                    if abs(dy) > abs(dx) * ratio and abs(dy) > NOISE_GATE:
                        acc += dy
                        acc = max(-step * 2, min(step * 2, acc))
                        now = time.monotonic()
                        while acc <= -step and now - last_action >= MIN_INTERVAL:
                            if kind == "vol":
                                set_volume(True)
                            else:
                                set_brightness(True)
                            acc += step
                            last_action = now
                            now = time.monotonic()
                        while acc >= step and now - last_action >= MIN_INTERVAL:
                                if kind == "vol":
                                    set_volume(False)
                                else:
                                    set_brightness(False)
                                acc -= step
                                last_action = now
                                now = time.monotonic()
                for f in fingers:
                    f["px"], f["py"] = f["x"], f["y"]
            else:
                acc = 0.0
                for s in slots.values():
                    if "x" in s and "y" in s:
                        s["px"], s["py"] = s["x"], s["y"]


def main():
    ui = open_uinput()
    while True:
        dev = find_touchpad()
        if dev is None:
            print("touchpad introuvable, nouvel essai dans 3s", flush=True)
            time.sleep(3)
            continue
        print(f"surveillance de {dev.name} ({dev.path}), "
              f"gauche 1 doigt volume x<={LEFT_X_MAX_1F} (pose initiale), "
              f"droite 1 doigt lum x>={RIGHT_X_MIN_1F} (pose initiale), "
              f"tap 3 doigts=Alt+F4 (clic=deconnexion), tap 4 doigts=Entree",
              flush=True)
        try:
            monitor(dev, ui)
        except OSError as e:
            print(f"peripherique perdu ({e}), reconnexion...", flush=True)
            time.sleep(2)


if __name__ == "__main__":
    main()
PY
chmod +x "$BIN_ZONES"

# ----------------------------------------------------------------------------
#  2. Overlay (OSD)
# ----------------------------------------------------------------------------
if [ "$OSD_OK" = "1" ]; then
    msg "2/5  Overlay : $BIN_OSD"
    cat >"$BIN_OSD" <<'PY'
#!/usr/bin/env python3
"""Overlay volume/luminosite en bas au milieu de l'ecran.

Pilote via FIFO : ecrire "vol 65", "bri 40" ou "mute" (une ligne par message).
Position exacte forcee par une regle KWin (titre "touchpad-osd").
"""

import os
import sys

from PySide6.QtCore import Qt, QTimer, QSocketNotifier, QLockFile
from PySide6.QtWidgets import QApplication, QWidget, QLabel, QProgressBar, QHBoxLayout

UID = os.getuid()
FIFO = f"/run/user/{UID}/touchpad-osd.fifo"
LOCK = f"/run/user/{UID}/touchpad-osd.lock"
WIDTH, HEIGHT = 400, 76
HIDE_MS = 1400


class Osd(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("touchpad-osd")
        self.setWindowFlags(Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.setFixedSize(WIDTH, HEIGHT)
        # Position de secours, si la regle KWin n'est pas (encore) active.
        g = QApplication.primaryScreen().availableGeometry()
        self.move(g.x() + (g.width() - WIDTH) // 2,
                  g.y() + g.height() - HEIGHT - 24)
        self.setStyleSheet(
            "QWidget { background: rgba(24, 24, 37, 232); border-radius: 18px; }"
            "QLabel { background: transparent; color: white; font-size: 15px; }"
            "QProgressBar { background: rgba(255,255,255,40); border: none; "
            "border-radius: 7px; height: 14px; text-align: center; }"
            "QProgressBar::chunk { background: #89b4fa; border-radius: 7px; }"
        )
        layout = QHBoxLayout(self)
        layout.setContentsMargins(20, 0, 20, 0)
        layout.setSpacing(12)
        self.kind_label = QLabel("Volume")
        self.kind_label.setFixedWidth(92)
        self.bar = QProgressBar()
        self.bar.setRange(0, 100)
        self.bar.setTextVisible(False)
        self.pct_label = QLabel("0%")
        self.pct_label.setFixedWidth(56)
        self.pct_label.setAlignment(Qt.AlignRight)
        layout.addWidget(self.kind_label)
        layout.addWidget(self.bar, 1)
        layout.addWidget(self.pct_label)
        self.hide_timer = QTimer(self)
        self.hide_timer.setSingleShot(True)
        self.hide_timer.timeout.connect(self.hide)

    def show_level(self, kind, value=None, muted=False):
        if kind == "bri":
            self.kind_label.setText("Luminosité")
            self.bar.setValue(value)
            self.pct_label.setText(f"{value}%")
        elif muted:
            self.kind_label.setText("Volume")
            self.bar.setValue(0)
            self.pct_label.setText("Muet")
        else:
            self.kind_label.setText("Volume")
            self.bar.setValue(value)
            self.pct_label.setText(f"{value}%")
        self.show()
        self.raise_()
        self.hide_timer.start(HIDE_MS)


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("touchpad-osd")
    lock = QLockFile(LOCK)
    if not lock.tryLock(100):
        print("un overlay tourne deja", flush=True)
        return 0
    try:
        os.mkfifo(FIFO, 0o600)
    except FileExistsError:
        pass
    osd = Osd()
    fd = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
    # ouvrir aussi en ecriture pour ne jamais recevoir EOF
    wfd = os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)

    def on_data():
        try:
            data = os.read(fd, 4096).decode(errors="ignore")
        except OSError:
            return
        for line in data.splitlines():
            parts = line.strip().split()
            if not parts:
                continue
            if parts[0] == "mute":
                osd.show_level("vol", muted=True)
            elif parts[0] in ("vol", "bri") and len(parts) == 2:
                try:
                    osd.show_level(parts[0], max(0, min(100, int(parts[1]))))
                except ValueError:
                    pass

    notifier = QSocketNotifier(fd, QSocketNotifier.Read)
    notifier.activated.connect(lambda: on_data())
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
PY
    chmod +x "$BIN_OSD"
else
    msg "2/5  Overlay ignoré (PySide6 absent)"
fi

# ----------------------------------------------------------------------------
#  3. Services systemd utilisateur
# ----------------------------------------------------------------------------
msg "3/5  Services systemd utilisateur"
if [ "$DEBUG" = "1" ]; then DEBUG_ENV=1; else DEBUG_ENV=0; fi

cat >"$SERVICE_ZONES" <<EOF
[Unit]
Description=Touchpad zones volume/luminosite
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/touchpad-zones.py
Environment=TOUCHPAD_VOL_DEBUG=$DEBUG_ENV
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

if [ "$OSD_OK" = "1" ]; then
    cat >"$SERVICE_OSD" <<'EOF'
[Unit]
Description=Touchpad OSD overlay bas milieu
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/touchpad-osd.py
Restart=always
RestartSec=1

[Install]
WantedBy=default.target
EOF
else
    rm -f "$SERVICE_OSD"
fi

# ----------------------------------------------------------------------------
#  4. Règles udev (accès utilisateur au pavé et à la luminosité)
# ----------------------------------------------------------------------------
msg "4/5  Règles udev"
TOUCHPAD_RULE=""
if [ -n "$TOUCHPAD_NAME" ]; then
    TOUCHPAD_RULE='ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="'"$TOUCHPAD_NAME"'", OWNER="'"$USER"'", GROUP="'"$USER"'"'
fi
BACKLIGHT_RULE='ACTION=="add|change", SUBSYSTEM=="backlight", KERNEL=="'"$BACKLIGHT_KERNEL"'", RUN+="/usr/bin/chown '"$USER:$USER"' /sys/class/backlight/'"$BACKLIGHT_KERNEL"'/brightness"'

udev_install() {
    local file="$1" content="$2" label="$3"
    if [ -z "$content" ]; then return; fi
    if [ -f "$file" ] && [ "$(cat "$file")" = "$content" ]; then
        echo "  déjà en place : $file"
        return
    fi
    echo "  à installer : $file"
    if sudo -n true 2>/dev/null; then
        printf '%s\n' "$content" | sudo tee "$file" >/dev/null
        sudo udevadm control --reload-rules >/dev/null 2>&1 || true
        sudo udevadm trigger --subsystem-match="$label" >/dev/null 2>&1 || true
    else
        warn "root requis. Dans un terminal :"
        printf '     %s\n' "echo '$content' | sudo tee $file"
    fi
}

udev_install "$UDEV_BACKLIGHT" "$BACKLIGHT_RULE" "backlight"
udev_install "$UDEV_TOUCHPAD" "$TOUCHPAD_RULE" "input"

# Sans les règles (déjà actives), autorise l'accès immédiatement si possible.
if [ ! -w "$BACKLIGHT_DIR/brightness" ]; then
    warn "Luminosité non accessible en écriture ; applique la règle udev puis rebranche/redémarre."
fi

# ----------------------------------------------------------------------------
#  5. Règle KWin (position de l'OSD) + activation
# ----------------------------------------------------------------------------
msg "5/5  Règle KWin et activation"
if [ "$OSD_OK" = "1" ]; then
    if RID="$(kwin_rule_find)"; then
        echo "  règle existante : n°$RID"
    else
        RID="$(kwin_rule_free_id)"
        echo "  création de la règle n°$RID"
    fi

    # Position bas-centre calculée pour l'écran courant.
    read -r SW SH < <(python3 - <<'PY' 2>/dev/null || echo "1920 1080"
import sys
from PySide6.QtWidgets import QApplication
app = QApplication(sys.argv)
g = app.primaryScreen().geometry()
print(g.width(), g.height())
PY
)
    [ -n "${SW:-}" ] && [ -n "${SH:-}" ] || { SW=1920; SH=1080; }
    POS_X=$(( (SW - OSD_W) / 2 ))
    POS_Y=$(( SH - OSD_H - OSD_MARGIN ))
    [ "$POS_X" -ge 0 ] || POS_X=0
    [ "$POS_Y" -ge 0 ] || POS_Y=0

    kwriteconfig6 --file kwinrulesrc --group "$RID" --key Description "Touchpad OSD bas milieu"
    kwriteconfig6 --file kwinrulesrc --group "$RID" --key title "$KWIN_TITLE"
    kwriteconfig6 --file kwinrulesrc --group "$RID" --key titlematch 2
    kwriteconfig6 --file kwinrulesrc --group "$RID" --key position "$POS_X,$POS_Y"
    kwriteconfig6 --file kwinrulesrc --group "$RID" --key positionrule 3
    kwriteconfig6 --file kwinrulesrc --group "$RID" --key size "$OSD_W,$OSD_H"
    kwriteconfig6 --file kwinrulesrc --group "$RID" --key sizerule 3

    ORDER="$(kread General Order)"
    case ",$ORDER," in
        *",$RID,"*) ;;
        *)
            ORDER="${ORDER:+$ORDER,}$RID"
            kwriteconfig6 --file kwinrulesrc --group General --key Order "$ORDER"
            ;;
    esac
    echo "  OSD positionné en $POS_X,$POS_Y (écran ${SW}x${SH})"
fi

systemctl --user daemon-reload
systemctl --user enable touchpad-zones.service >/dev/null 2>&1
systemctl --user restart touchpad-zones.service
if [ "$OSD_OK" = "1" ]; then
    systemctl --user enable touchpad-osd.service >/dev/null 2>&1
    systemctl --user restart touchpad-osd.service
fi
busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true

sleep 1
msg "Installation terminée"
echo
echo "  Démon zones : $(systemctl --user is-active touchpad-zones.service)"
if [ "$OSD_OK" = "1" ]; then
    echo "  Overlay OSD : $(systemctl --user is-active touchpad-osd.service)"
else
    echo "  Overlay OSD : non installé (PySide6 absent)"
fi
echo
echo "  Bord GAUCHE du pavé, 1 doigt posé puis glissé haut/bas : volume"
echo "  Bord DROIT  du pavé, 1 doigt posé puis glissé haut/bas : luminosité"
echo "  Le curseur, le clic et le scroll 2 doigts restent normaux."
echo
echo "  Journal : journalctl --user -u touchpad-zones.service -f"
echo "  Désinstallation : ./installer-touchpad-zones.sh --uninstall"
