# Correctifs UX KDE Plasma (Bazzite / Wayland)

Cinq correctifs « qualité de vie » pour **Bazzite / KDE Plasma 6 (Wayland)**, testés sur un
**ASUS V16 (V3607VM)** :

| Correctif | Effet |
|---|---|
| [`installer-capture-shift-win-s.sh`](#1-capture-décran--shift--win--s-façon-windows) | `Shift + Win + S` capture une région, copie et enregistre — **sans aucune fenêtre** |
| [`installer-clavier-toujours-allume.sh`](#2-rétroéclairage-du-clavier-toujours-allumé) | Le rétroéclairage du clavier **reste toujours allumé** |
| [`installer-veille-jamais.sh`](#3-ni-veille-ni-extinction-décran-ni-verrouillage-automatique) | **Jamais** de veille, d'extinction d'écran ni de verrouillage automatique |
| [`installer-touchpad-zones.sh`](#4-zones-du-pavé-tactile--bord-gauche-volume-bord-droit-luminosité) | **Bord gauche = volume**, **bord droit = luminosité** sur le pavé tactile |
| [`installer-numlock-toujours-actif.sh`](#5-pavé-numérique-num-lock-toujours-activé-au-démarrage) | Le **pavé numérique (Num Lock)** est **activé** à chaque démarrage de session |

Tout s'installe **au niveau utilisateur** ; seul l'accès au pavé tactile et à la
luminosité (deux règles udev) demande `root`, une fois.

## Prérequis

- KDE Plasma 6 sous Wayland (Bazzite, Fedora Kinoite, etc.)
- `spectacle`, `wl-clipboard` (`wl-copy`), `systemd` utilisateur
- Pour le clavier : un portable exposant `/sys/class/leds/*kbd_backlight`
  (écriture accessible à l'utilisateur ; c'est le cas des ASUS avec `asus-wmi`)
- Pour le pavé tactile : `python3-evdev`, `python3-pyside6`, `wpctl` (PipeWire)
  — présents par défaut sur Bazzite — et un accès en écriture à
  `/sys/class/backlight/*/brightness` (règle udev fournie)

---

## 1. Capture d'écran « Shift + Win + S » façon Windows

### Résultat

```
Shift + Win + S  →  tu dessines une zone  →  tu relâches  →  terminé.
```

- aucune fenêtre, aucun bouton « Copier » à cliquer ;
- l'image est **copiée dans le presse-papier** (`Ctrl+V` immédiat) ;
- le fichier est **enregistré** dans `~/Images/Captures d'écran/` ;
- petite notification discrète ;
- `Échap` annule : rien n'est créé.

### Installation

```bash
chmod +x installer-capture-shift-win-s.sh
./installer-capture-shift-win-s.sh
```

Puis teste directement `Shift + Win + S`. Si le raccourci ne réagit pas tout de suite,
déconnecte/reconnecte la session une fois (ou vérifie
*Paramètres système → Raccourcis → KWin → « Capture d'écran d'une région »*).

### Comment ça marche

Trois briques :

1. **`~/.local/bin/capture-region.sh`**
   Lance `spectacle -r -b -n -o <fichier>` (mode arrière-plan, aucune interface),
   puis `wl-copy` pour le presse-papier et `notify-send` pour la notification.
2. **`~/.config/systemd/user/capture-region.service`** (`Type=oneshot`)
   Démarre le script proprement, indépendamment du shell. Le service utilise
   `KillMode=process` pour que `wl-copy` survive et continue de servir le presse-papier.
3. **`~/.local/share/kwin/scripts/capture-region-silence/`** (script KWin)
   Possède le raccourci `Meta+Shift+S` et démarre le service — il s'active à chaud,
   contrairement à un raccourci « commande » classique.

Réglages Spectacle indispensables (`~/.config/spectaclerc`) :

| Clé | Valeur | Rôle |
|---|---|---|
| `useReleaseToCapture` | `true` | termine la capture **dès le relâchement** de la souris |
| `clipboardGroup` | `1` | copie l'image automatiquement |
| `autoSaveImage` | `true` | enregistre le fichier automatiquement |

> Sans `useReleaseToCapture=true`, Spectacle attend un clic sur « Copier ».

Le script libère aussi le raccourci que Spectacle se réattribue à chaque démarrage,
et réserve `Shift+Win+S` à la capture silencieuse (Spectacle reste sur `Impr. écran`).

### Désinstallation

```bash
./installer-capture-shift-win-s.sh --uninstall
```

### Dépannage

```bash
# Le service s'est-il lancé ?
systemctl --user status capture-region.service

# Journal des dernières captures
journalctl --user -b | grep capture-region

# Vérifier qui détient le raccourci
busctl --user call org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel getGlobalShortcutsByKey i 301989971
```

- Le service se termine en quelques millisecondes **sans fichier** : une autre
  capture est probablement en cours (verrou `$XDG_RUNTIME_DIR/capture-region.lock`).
- Le presse-papier se vide : vérifier que le service est bien en `KillMode=process`.

---

## 2. Rétroéclairage du clavier toujours allumé

### Le problème (bug noyau spécifique)

Sur l'**ASUS V16 V3607VM**, la **lecture** du niveau de rétroéclairage est cassée :

```bash
cat /sys/class/leds/asus::kbd_backlight/brightness   # renvoie toujours 0
```

…même quand le clavier est physiquement allumé (bug noyau, voir
[Ubuntu #2171178](https://bugs.launchpad.net/ubuntu/+bug/2171178)).
Conséquences : `systemd-backlight` sauvegarde `0` à l'extinction et restaure un
clavier éteint au démarrage ; KDE/powerdevil se trompe aussi sur l'état réel.

L'**écriture**, elle, fonctionne parfaitement.

### La solution

Comme l'état réel est illisible, le niveau voulu est **réécrit toutes les 5 secondes**.
Le clavier ne peut donc plus rester éteint (veille, changement de profil, bug de lecture…).

| Fichier | Rôle |
|---|---|
| `~/.local/bin/kbd-backlight-keep.sh` | écrit le niveau voulu dans le sysfs |
| `~/.config/systemd/user/kbd-backlight-keep.service` | exécute le script |
| `~/.config/systemd/user/kbd-backlight-keep.timer` | relance toutes les 5 s |

### Installation

```bash
chmod +x installer-clavier-toujours-allume.sh
./installer-clavier-toujours-allume.sh            # niveau 1 sur 3 (défaut)
./installer-clavier-toujours-allume.sh --level 3  # intensité maximale
```

### Désinstallation

```bash
./installer-clavier-toujours-allume.sh --uninstall
```

### À savoir

`cat /sys/class/leds/asus::kbd_backlight/brightness` affichera **toujours `0`**,
même quand le clavier est allumé : c'est le bug de lecture, pas la configuration.
Le correctif définitif viendra d'une mise à jour du noyau (`asus-wmi`).

Le service système `/etc/systemd/system/kbd-backlight.service` (s'il existe déjà)
est laissé en place : il allume le clavier au démarrage, avant la connexion,
et le minuteur utilisateur prend le relais après le login.

---

## 3. Ni veille, ni extinction d'écran, ni verrouillage automatique

### Résultat

- aucune veille automatique par inactivité (secteur, batterie, batterie faible) ;
- aucune veille à la fermeture du capot ;
- l'écran ne s'éteint pas et ne s'assombrit pas automatiquement ;
- aucun verrouillage automatique (inactivité ou reprise de veille) ;
- la **veille manuelle** (`systemctl suspend`) et le **verrouillage manuel** (`Meta+L`)
  restent disponibles.

### Installation

```bash
chmod +x installer-veille-jamais.sh
./installer-veille-jamais.sh              # applique / répare
./installer-veille-jamais.sh --uninstall  # remet les réglages KDE par défaut
```

### Comment ça marche

Le script écrit les profils `AC`, `Battery` et `LowBattery` dans
`~/.config/powerdevilrc` (groupes imbriqués `[profil][SuspendAndShutdown]` et
`[profil][Display]`), puis désactive le verrouillage automatique dans
`~/.config/kscreenlockerrc`. Il redémarre `plasma-powerdevil` pour appliquer
à chaud (un simple rechargement ne suffit pas pour l'action du capot).
Les réglages persistent après redémarrage.

Des copies de référence de la configuration appliquée sont conservées dans
`config/powerdevilrc` et `config/kscreenlockerrc` (réécrites à chaque exécution).

> ⚠️ Sans veille ni verrouillage automatique, pense à verrouiller manuellement
> (`Meta+L`) quand tu t'éloignes de la machine.

---

## 4. Zones du pavé tactile : bord gauche = volume, bord droit = luminosité

### Résultat

- **1 doigt posé au bord gauche** puis glissé haut/bas → **volume** (± 5 %) ;
- **1 doigt posé au bord droit** puis glissé haut/bas → **luminosité** (± 5 %) ;
- un OSD discret (volume / luminosité) apparaît en bas au milieu ;
- tap **3 doigts** sur une application → **ferme la fenêtre active** ;
- tap **3 doigts** sur le fond d'écran du bureau → **menu pour éteindre/redémarrer/…** ;
- tap **4 doigts** → `Entrée`.

Le moniteur est **passif** : il observe les événements du pavé sans les
intercepter. Le curseur, le clic et le **scroll à 2 doigts** continuent de
fonctionner normalement. Seules les bandes de 5 % aux bords, à la pose du
doigt, sont détournées.

### Installation

```bash
chmod +x installer-touchpad-zones.sh
./installer-touchpad-zones.sh            # installe / répare
./installer-touchpad-zones.sh --debug    # journal détaillé du démon
./installer-touchpad-zones.sh --uninstall
```

Les deux règles udev (`/etc/udev/rules.d/`) ne sont écrites que si elles
manquent : si `sudo` n'est pas disponible, l'installateur affiche les
commandes à lancer une fois. Elles donnent à l'utilisateur l'accès en lecture
au pavé tactile et en écriture à la luminosité.

### Comment ça marche

| Fichier | Rôle |
|---|---|
| `~/.local/bin/touchpad-zones.py` | lit le pavé via `python-evdev`, détecte les bandes de bord et les gestes |
| `~/.local/bin/touchpad-3tap-action.js` | script KWin : 3 doigts → ferme la fenêtre, ou menu extinction si bureau |
| `~/.local/bin/touchpad-osd.py` | overlay Qt en bas au milieu, piloté par un FIFO |
| `~/.config/systemd/user/touchpad-zones.service` | démon (redémarrage automatique) |
| `~/.config/systemd/user/touchpad-osd.service` | overlay |
| `/etc/udev/rules.d/99-touchpad-volume.rules` | accès au périphérique du pavé |
| `/etc/udev/rules.d/99-backlight-nico.rules` | accès en écriture à la luminosité |
| règle KWin `touchpad-osd` (`kwinrulesrc`) | position de l'OSD en bas au milieu |

Le volume passe par `wpctl` (PipeWire) et la luminosité par
`/sys/class/backlight/*/brightness`.

### Réglage

Dans `~/.local/bin/touchpad-zones.py` :

| Constante | Effet |
|---|---|
| `LEFT_FRACTION_1F` / `RIGHT_FRACTION_1F` | largeur des bandes de bord (5 %) |
| `STEP_PX_1F` | sensibilité : pixels à parcourir par cran (160) |
| `BRIGHT_STEP_PCT` | pas de luminosité (5 %) |
| `X_MAX` | résolution horizontale du pavé (4645 pour l'ASUS V16) |

Après modification : `systemctl --user restart touchpad-zones.service`.

### Dépannage

```bash
systemctl --user status touchpad-zones.service
journalctl --user -u touchpad-zones.service -f
```

- Rien ne se passe : vérifie que le démon surveille bien le pavé
  (`surveillance de … Touchpad` dans le journal).
- Le volume/luminosité change mais aucun OSD : `systemctl --user status touchpad-osd.service`
  (PySide6 doit être présent).
- La luminosité ne change pas : le fichier `brightness` n'est pas accessible
  en écriture → applique la règle udev puis redémarre (ou rebranche).

---

## 5. Pavé numérique (Num Lock) toujours activé au démarrage

### Résultat

Le pavé numérique (**Num Lock**) est automatiquement activé à chaque démarrage
de la session Plasma.

### Installation

```bash
chmod +x installer-numlock-toujours-actif.sh
./installer-numlock-toujours-actif.sh              # applique / répare
./installer-numlock-toujours-actif.sh --uninstall  # revient au comportement KDE par défaut
```

### Comment ça marche

Le script écrit la clé `NumLock` dans `~/.config/kcminputrc` (section `[Keyboard]`) :

| Valeur | Effet |
|---|---|
| `0` | activer au démarrage |
| `1` | désactiver au démarrage |
| `2` | laisser l'état précédent (défaut KDE) |

Une copie de référence de la configuration appliquée est conservée dans
`config/kcminputrc` (réécrite à chaque exécution).

Le réglage est pris en compte au prochain démarrage de session
(*Paramètres système → Clavier → « Verrouillage numérique au démarrage de Plasma »*).

---

## Désinstallation complète

```bash
./installer-capture-shift-win-s.sh --uninstall
./installer-clavier-toujours-allume.sh --uninstall
./installer-veille-jamais.sh --uninstall
./installer-touchpad-zones.sh --uninstall
./installer-numlock-toujours-actif.sh --uninstall
```

## Structure du dépôt

```
.
├── installer-capture-shift-win-s.sh     # Shift+Win+S silencieux
├── installer-clavier-toujours-allume.sh # rétroéclairage toujours allumé
├── installer-veille-jamais.sh           # ni veille, ni extinction, ni verrouillage
├── installer-touchpad-zones.sh          # bords du pavé : volume / luminosité + gestes
├── installer-numlock-toujours-actif.sh  # Num Lock activé à chaque démarrage
├── config/
│   ├── powerdevilrc                     # copie de référence
│   ├── kscreenlockerrc                  # copie de référence
│   ├── kcminputrc                       # copie de référence
│   └── touchpad-zones/                  # copies de référence (zones/gestes pavé)
│       ├── touchpad-zones.py            # démon gestes + zones
│       ├── touchpad-3tap-action.js       # 3 doigts : fermer app / menu extinction (bureau)
│       ├── touchpad-osd.py              # OSD volume/luminosité
│       ├── touchpad-zones.service
│       └── touchpad-osd.service
└── README.md
```

Les installateurs sont **idempotents** : les relancer répare/actualise la configuration.
