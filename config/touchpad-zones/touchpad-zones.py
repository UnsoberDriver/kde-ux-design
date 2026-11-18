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

# taps multi-doigts : 3 doigts -> fermer app / menu extinction (bureau), 4 doigts -> Entree
TAP_ACTIONS = {3: "close", 4: "enter"}
TAP_MAX_N = max(TAP_ACTIONS)
TAP_SIMULT_S = 0.12  # ecart maxi de pose entre les doigts (simultaneite)
TAP_MAX_S = 0.35  # duree maxi du tap (pose -> relache complet)
TAP_MAX_MOVE = 150  # mouvement maxi du centroide pendant le tap (unites)
TAP_COOLDOWN = 1.0  # delai mini entre 2 actions 3 doigts

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


def do_3finger_action():
    """Action contextuelle 3 doigts via script KWin :
    bureau -> menu extinction, application -> fermer la fenêtre."""
    script = os.path.expanduser("~/.local/bin/touchpad-3tap-action.js")
    try:
        subprocess.run(["busctl", "--user", "call", "org.kde.KWin", "/Scripting",
                        "org.kde.kwin.Scripting", "unloadScript", "s",
                        "touchpad-3tap-action"],
                       check=False, capture_output=True, timeout=2)
        r = subprocess.run(["busctl", "--user", "call", "org.kde.KWin", "/Scripting",
                            "org.kde.kwin.Scripting", "loadScript", "ss",
                            script, "touchpad-3tap-action"],
                           check=False, capture_output=True, text=True, timeout=2)
        out = (r.stdout or "").strip()
        if r.returncode == 0 and out.startswith("i "):
            sid = out.split()[1]
            subprocess.run(["busctl", "--user", "call", "org.kde.KWin",
                            f"/Scripting/Script{sid}", "org.kde.kwin.Script", "run"],
                           check=False, capture_output=True, timeout=2)
            print("tap 3 doigts -> action contextuelle (bureau=menu extinction, app=fermer)",
                  flush=True)
            return True
        print(f"action 3 doigts: chargement du script KWin impossible ({out or r.stderr.strip()})",
              flush=True)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"action 3 doigts impossible ({e})", flush=True)
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





def open_uinput():
    try:
        from evdev import UInput
        ui = UInput({ecodes.EV_KEY: [ecodes.KEY_ENTER]},
                    name="touchpad-zones-keys")
        print("clavier virtuel uinput OK", flush=True)
        return ui
    except (OSError, ImportError) as e:
        print(f"uinput indisponible ({e}), Entree (tap 4 doigts) desactive", flush=True)
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
            # --- taps multi-doigts (3=fermer/menu extinction, 4=Entree) ---
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
                               "cx": sum(f["x"] for f in fingers) / n,
                               "cy": sum(f["y"] for f in fingers) / n}
                        if DEBUG:
                            print(f"debug candidat tap {n} doigts", flush=True)
                else:
                    tap = {"action": TAP_ACTIONS[n], "t0": now, "moved": 0.0, "n_prev": n,
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
                    if n > TAP_MAX_N:
                        tap = None  # trop de doigts : annule
                    elif n == 0:
                        if now - tap["t0"] <= TAP_MAX_S and tap["moved"] <= TAP_MAX_MOVE:
                            if DEBUG and tap["action"] == "close":
                                print(f"debug tap feu: duree={now-tap['t0']:.2f}s "
                                      f"mouvement={tap['moved']:.0f}", flush=True)
                            if tap["action"] == "close":
                                ok = do_3finger_action()
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
              f"tap 3 doigts=fermer app / menu extinction (bureau), tap 4 doigts=Entree",
              flush=True)
        try:
            monitor(dev, ui)
        except OSError as e:
            print(f"peripherique perdu ({e}), reconnexion...", flush=True)
            time.sleep(2)


if __name__ == "__main__":
    main()
