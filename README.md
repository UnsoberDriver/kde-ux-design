# Correctifs UX KDE Plasma (Bazzite / Wayland)

Une douzaine de correctifs / personnalisations « qualité de vie » pour **Bazzite / KDE Plasma 6 (Wayland)**, testés sur un
**ASUS V16 (V3607VM)** :

| Correctif | Effet |
|---|---|
| [`installer-capture-shift-win-s.sh`](#1-capture-décran--shift--win--s-façon-windows) | `Shift + Win + S` capture une région, copie et enregistre — **sans aucune fenêtre** |
| [`installer-clavier-toujours-allume.sh`](#2-rétroéclairage-du-clavier-toujours-allumé) | Le rétroéclairage du clavier **reste toujours allumé** |
| [`installer-clavier-retro-eclairage-ac.sh`](#2b-rétroéclairage-clavier-max-sur-secteur-min-sur-batterie) | Rétroéclairage clavier **au max sur secteur**, **au min sur batterie** |
| [`installer-veille-jamais.sh`](#3-ni-veille-ni-extinction-décran-ni-verrouillage-automatique) | **Jamais** de veille, d'extinction d'écran ni de verrouillage automatique |
| [`installer-touchpad-zones.sh`](#4-zones-du-pavé-tactile--bord-gauche-volume-bord-droit-luminosité) | **Bord gauche = volume**, **bord droit = luminosité** sur le pavé tactile |
| [`installer-numlock-toujours-actif.sh`](#5-pavé-numérique-num-lock-toujours-activé-au-démarrage) | Le **pavé numérique (Num Lock)** est **activé** à chaque démarrage de session |
| [`config/kxkbrc`](#5b-clavier-français-au-démarrage) | Le clavier démarre en **azerty (fr)**, l'US reste disponible |
| [`installer-icones-monochromes.sh`](#6-icônes-dapplications-en-monochrome-thème-sombre) | Les **icônes des applications** (système, Flatpak, Chromium, OpenCode, Dolphin…) en **monochrome** adapté au thème sombre |
| [`installer-firefox-config.sh`](#7-configuration-firefox-barre-de-favoris-en-icônes-seules) | **Firefox** (Flatpak) : barre personnelle en **icônes seules** (`userChrome.css`) et intégration Plasma |
| [`installer-fond-ecran-anime.sh`](#10-fond-décran-animé-wallpaper-engine-for-kde) | **Fond d’écran animé** via Wallpaper Engine for KDE (plugin `catsout`) |
| [`installer-fond-noir-batterie.sh`](#8-fond-décran-noir-automatique-sur-batterie) | **Fond noir pur** immédiat sur batterie, **dernier fond utilisé** restauré au rebranchement |
| [`installer-barre-taches-trait-blanc.sh`](#9-barre-des-tâches-épurée--trait-blanc-sous-les-applis-ouvertes) | Barre épurée (plus de CPU ni de « réduire tout ») et **trait blanc sous les applis ouvertes**, sans changement de fond |
| [`installer-larping-discord.sh`](#11-activit-discord-larping) | `AltGr + :` et `AltGr + !` **active / coupe deux activités Discord** (Larping / Jeu) |

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
| `~/.local/bin/touchpad-3tap-action.js` | script KWin : 3 doigts → ferme la fenêtre, ou **extinction directe** sur le bureau |
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

## 5b. Clavier français au démarrage

### Résultat

- au lancement de la session, le premier layout est **Français (azerty)** ;
- l'anglais (US) reste disponible via le raccourci de changement de layout ;
- l'icône de layout reste retirée de la barre des tâches.

### Comment ça marche

`~/.config/kxkbrc` contient `LayoutList=fr,us` (noms :
`Français,Anglais (US)`). La copie de référence est conservée dans
`config/kxkbrc`.

Le réglage est lu par KWin au prochain démarrage de session : pas besoin de
redémarrer la session immédiatement.

---

## 6. Icônes d'applications en monochrome (thème sombre)

### Résultat

- les **icônes/logos des applications** (système, Flatpak, Chromium, Dolphin,
  OpenCode, etc.) sont remplacés par des icônes **monochromes blanches**,
  adaptées aux thèmes sombres ;
- tout s'installe **au niveau utilisateur** via des surcharges de lanceurs
  (`~/.local/share/applications`) et des icônes locales — compatible avec les
  systèmes immuables comme Bazzite (aucun `root` nécessaire).

> Remarque : ce sont des icônes symboliques/monochromes (formes simplifiées).
> Lorsqu'il n'existe pas de variante de marque adaptée, une icône générique
> proche est utilisée.

### Installation

```bash
chmod +x installer-icones-monochromes.sh
./installer-icones-monochromes.sh              # applique / répare
./installer-icones-monochromes.sh --uninstall  # supprime surcharges et icônes
```

### Comment ça marche

| Fichier | Rôle |
|---|---|
| `~/.local/share/icons/custom-black/*-mono.svg` | icônes monochromes installées |
| `~/.local/share/icons/hicolor/scalable/apps/*-mono.svg` | copies dans le thème hicolor utilisateur |
| `~/.local/share/applications/<app>.desktop` | surcharge du lanceur pour pointer vers l'icône monochrome |
| `~/.local/share/applications/opencode.desktop` | lanceur créé si `opencode` est installé |

Des copies de référence des icônes sont conservées dans
`config/icones-monochromes/` (réécrites à chaque exécution du dépôt/script selon
le cas d'usage).

### À savoir

- **Barre des tâches / icônes épinglées** : Plasma garde souvent l'ancienne
  icône en cache. Quitte l'application, **détache** l'icône épinglée puis
  **réépingle-la** depuis le menu des applications. Si besoin, déconnecte/
  reconnecte la session (ou redémarre) pour purger le cache du panneau.
- Redémarre les applications ouvertes pour qu'elles reprennent la nouvelle icône.
- Si une application précise n'est pas couverte, il suffit d'ajouter/ajuster son
  lanceur dans `~/.local/share/applications/` et l'icône correspondante.

---

## 7. Configuration Firefox (barre de favoris en icônes seules)

> S'applique à **Firefox Flatpak** (`org.mozilla.firefox`, profil utilisateur sous
> `~/.var/app/org.mozilla.firefox`).

### Résultat

- la **barre personnelle** (favoris) affiche les favoris en **icônes seules**
  (libellés masqués, bouton « Importer les marque-pages… » masqué, espacement ajusté) ;
- activation du chargement des personnalisations d'interface (`chrome/userChrome.css`)
  via `user.js` ;
- surcharge Flatpak pour l'**intégration Plasma navigateur**.

### Installation

```bash
chmod +x installer-firefox-config.sh
./installer-firefox-config.sh              # applique / répare
./installer-firefox-config.sh --uninstall  # retire cette personnalisation
```

### Comment ça marche

| Fichier | Rôle |
|---|---|
| `~/.var/app/org.mozilla.firefox/config/mozilla/firefox/<profil>/user.js` | active `toolkit.legacyUserProfileCustomizations.stylesheets` |
| `~/.var/app/org.mozilla.firefox/config/mozilla/firefox/<profil>/chrome/userChrome.css` | style de la barre personnelle (icônes seules) |
| `~/.local/share/flatpak/overrides/org.mozilla.firefox` | surcharge Flatpak (intégration Plasma navigateur) |

Des copies de référence sont conservées dans `config/firefox/` (`user.js`,
`chrome/userChrome.css`, `flatpak-override.org.mozilla.firefox`,
`org.mozilla.firefox.desktop`).

### À savoir

- **Redémarre Firefox** pour appliquer `user.js` et `userChrome.css`.
- L'icône monochrome du lanceur Firefox est gérée par
  [`installer-icones-monochromes.sh`](#6-icônes-dapplications-en-monochrome-thème-sombre).
- Si tu as plusieurs profils, le script cible le profil par défaut (d'après
  `profiles.ini`, sinon le premier `*.default-release`).

---

## 8. Fond d'écran noir automatique sur batterie

### Résultat

- Dès que le chargeur est débranché, le fond passe en **noir pur `#000000`** (bascule mesurée en 0,05–0,1 s).
- Au rebranchement, le **dernier fond utilisé est restauré** automatiquement (même délai).
- Gain mesuré sur l'ASUS V16 (RTX 5060 Laptop) : d'environ **28 W à 14 W** quand le fond animé Wallpaper Engine (vidéo MP4) est actif — soit près de **50 % d'autonomie en plus**.

### Installation

```bash
chmod +x installer-fond-noir-batterie.sh
./installer-fond-noir-batterie.sh
```

Aucun `root` nécessaire. L'installateur est idempotent : le relancer répare/actualise l'installation.

### Comment ça marche

Un service utilisateur (`battery-wallpaper.service`) écoute le **signal D-Bus de UPower** (`OnBattery`) : pas de sondage, pas de délai de timer. Le fond actif est sauvegardé à **chaque débranchement** dans `~/.local/state/battery-wallpaper/original.json`, puis restauré au retour du secteur. Si tu changes de fond sur secteur, c'est ce nouveau fond qui sera enregistré lors de la prochaine déconnexion.

Fichiers créés :

| Fichier | Rôle |
|---|---|
| `~/.local/bin/battery-wallpaper.py` | démon de bascule |
| `~/.config/battery-wallpaper.conf` | réglages (`mode=black`, `color=#000000`) |
| `~/.config/systemd/user/battery-wallpaper.service` | service utilisateur |
| `~/.local/state/battery-wallpaper/original.json` | sauvegarde du dernier fond utilisé |

> La configuration animée sauvegardée est également conservée comme copie de
> référence dans [`config/fond-ecran-anime/wallpaper-engine.json`](config/fond-ecran-anime/wallpaper-engine.json)
> (plugin `com.github.catsout.wallpaperEngineKde` : source vidéo Wallpaper Engine,
> FPS, audio coupé, mode d'affichage, chemin de la bibliothèque Steam…).

### Réglage

Par défaut le fond est noir. Pour utiliser une image fixe à la place, éditer
`~/.config/battery-wallpaper.conf` puis `systemctl --user restart battery-wallpaper.service` :

```ini
mode=image
image=/usr/share/wallpapers/convergence.jxl
```

Commandes utiles :

```bash
~/.local/bin/battery-wallpaper.py status        # état actuel
~/.local/bin/battery-wallpaper.py force-static  # forcer le noir
~/.local/bin/battery-wallpaper.py force-restore # forcer la restauration
```

### Dépannage

```bash
systemctl --user status battery-wallpaper.service
journalctl --user -u battery-wallpaper.service -f
```

Si le dernier fond ne revient pas après un rebranchement :
`~/.local/bin/battery-wallpaper.py force-restore`.

Le fond est **ré-enregistré automatiquement à chaque déconnexion** : il n'est plus nécessaire de supprimer `original.json` après avoir changé de fond.

### Désinstallation

```bash
./installer-fond-noir-batterie.sh --uninstall
```

Le fond d'origine est restauré, le service et les fichiers sont supprimés.

---

## 9. Barre des tâches épurée + trait blanc sous les applis ouvertes

### Résultat

- plus de **widget CPU** dans le panneau ;
- plus de bouton **« réduire toutes les fenêtres »** ;
- les **applications épinglées restent intactes** (aucune n'est retirée ni réordonnée) ;
- quand une application est ouverte, un **trait blanc** apparaît sous son icône ;
- **aucun changement de couleur de fond** : une fenêtre active, inactive, minimisée,
  demandant l'attention ou survolée a exactement le même fond transparent que
  n'importe quel lanceur.

### Installation

```bash
chmod +x installer-barre-taches-trait-blanc.sh
./installer-barre-taches-trait-blanc.sh
```

L'installateur est idempotent : le relancer répare/actualise l'installation.

### Comment ça marche

Le gestionnaire de tâches (`org.kde.plasma.icontasks`) dessine son fond et son
indicateur avec les éléments SVG de `widgets/tasks`. Le QML choisit un **préfixe
différent selon l'état** du bouton :

| État | Préfixe SVG | Avant |
|---|---|---|
| appli ouverte, inactive | `normal-*` | fond gris très clair |
| appli active | `focus-*` | fond bleu à 45 % |
| appli minimisée | `minimized-*` | fond atténué |
| attention | `attention-*` | fond orange |
| survol | `hover-*` | fond bleu clair |

Un simple réglage de couleur ne suffit donc pas : à chaque changement d'état,
un autre élément SVG prend le dessus. Le correctif crée un thème local
**Vapor White Line** (copie du thème Vapor, jamais modifié) dans lequel :

- tous les éléments de fond (`center`, `top`, `left`, `right`, les quatre coins)
  passent à `opacity="0"` pour **chaque** état ;
- seul l'élément `bottom` passe en `fill="#ffffff"` et `opacity="1"` ;
- le trait blanc couvre toute la largeur du bouton (étirement 9-slice).

Deux pièges traités par l'installateur :

1. **Le cache KSvg** (`~/.cache/ksvg-elements`) mémorise l'ancien SVG : il est
   vidé avant chaque redémarrage de `plasmashell`, sinon les bordures colorées
   reviennent.
2. **Les règles KWin `skiptaskbar=true`** masquent la fenêtre elle-même dans la
   barre : sans indicateur possible. L'installateur retire ces règles (une
   éventuelle règle de OSD tactile est préservée). C'est pour cela qu'une
   « barre épurée » ne doit **pas** passer par une règle KWin globale.

Fichiers créés / modifiés :

| Fichier | Rôle |
|---|---|
| `~/.local/share/plasma/desktoptheme/VaporWhiteLine/` | thème local (tasks.svgz, colors, metadata) |
| `~/.config/plasmarc` | thème actif |
| `~/.config/plasma-org.kde.plasma.desktop-appletsrc` | retrait des applets CPU et « réduire tout » |
| `~/.config/kwinrulesrc` | retrait des règles `skiptaskbar` |
| `~/.local/state/barre-taches-trait-blanc/` | sauvegarde des fichiers d'origine |

### Désinstallation

```bash
./installer-barre-taches-trait-blanc.sh --uninstall
```

Les fichiers d'origine sont restaurés et le thème local supprimé.

---

## 10. Fond d’écran animé (Wallpaper Engine for KDE)

### Résultat

- restaure la configuration du **fond d’écran animé** utilisé sur ce poste,
  via le plugin Plasma **Wallpaper Engine for KDE** (`com.github.catsout.wallpaperEngineKde`).

### Installation

```bash
chmod +x installer-fond-ecran-anime.sh
./installer-fond-ecran-anime.sh              # applique / répare
./installer-fond-ecran-anime.sh --uninstall  # retire la config du plugin
```

### Comment ça marche

| Fichier | Rôle |
|---|---|
| `~/.config/plasma-org.kde.plasma.desktop-appletsrc` | configuration Plasma du fond d’écran (containment bureau) |
| `config/fond-ecran-anime/wallpaper-engine.json` | copie de référence (plugin, chemin Steam, source/ID Workshop, filtre) |

Le script lit `config/fond-ecran-anime/wallpaper-engine.json` et met à jour la
section `[Wallpaper][com.github.catsout.wallpaperEngineKde][General]` du
containment Plasma.

### Prérequis / à savoir

- Nécessite le plugin **Wallpaper Engine for KDE** (`com.github.catsout.wallpaperEngineKde`).
- Nécessite **Steam / Wallpaper Engine Workshop** avec le fond téléchargé.
- Les **chemins et l’ID Workshop sont spécifiques à cette machine** (ex. chemin Steam
  dans `/home/nico/...`). Avant d’appliquer sur une autre machine, édite
  `config/fond-ecran-anime/wallpaper-engine.json`.
- Après application, redémarre plasmashell si besoin :
  `kquitapp6 plasmashell && kstart plasmashell` (ou déconnexion/reconnexion).

---

## 11. Activité Discord Larping

### Résultat

- `AltGr + :` (touche `:` azerty) active l'activité **« En train de jouer à
  Larping »** avec l'icône de l'application `LARPING_CLIENT_ID`.
- `AltGr + !` (touche `!` azerty, `KEY_SLASH` evdev) active
  **« En train de jouer à Larping »** avec l'icône de l'application
  `GAME_CLIENT_ID` (libellé interne « Jeu »).
- Un second appui sur **la même** touche coupe l'activité ; appuyer sur
  **l'autre** touche remplace directement l'activité courante (une seule
  activité Discord à la fois).
- Fonctionne sous **Wayland**, même quand Discord n'a pas le focus.
- Aucun `root`, aucun bot et aucun token Discord : uniquement l'IPC locale de
  Discord (`SET_ACTIVITY`).
- Limite : Discord affiche une **Rich Presence** (« En train de jouer à… »),
  pas le champ « Statut personnalisé » (l'API RPC ne le permet pas).

### Installation

```bash
chmod +x installer-larping-discord.sh
./installer-larping-discord.sh
```

L'installateur est idempotent : le relancer répare/actualise l'installation.

### Comment ça marche

`~/.local/bin/larping` est un démon utilisateur qui :

1. lit directement le périphérique clavier via **evdev** (détecté dans
   `/proc/bus/input/devices`, surchargeable avec `LARPING_KEYBOARD`) —
   KGlobalAccel n'est pas fiable ici car XKB consomme AltGr pour produire `·` ;
2. garde une connexion ouverte au socket IPC local de Discord
   (`/run/user/$UID/app/com.discordapp.Discord/discord-ipc-0`) et envoie
   `SET_ACTIVITY` avec `{"name":"Larping","type":0}` ;
3. **reconnecte** l'IPC quand on change de profil : le handshake doit être
   refait avec le bon `client_id`, sinon Discord garde l'icône du profil
   précédent ;
4. mémorise l'état (`52` = `:`, `53` = `!`, `0` = OFF) dans
   `~/.local/state/larping/state` pour le restaurer au prochain démarrage
   de la session (les anciens états `1` sont migrés automatiquement).

### Réglages

| Variable | Défaut | Rôle |
|---|---|---|
| `LARPING_CLIENT_ID` | `717091213148160041` | client ID du profil `AltGr + :` (exemple public « Apple Music ») |
| `LARPING_NAME` | `Larping` | texte affiché pour `AltGr + :` |
| `LARPING_ICON_URL` | *(vide)* | badge optionnel (`small_image`) du profil `:` |
| `GAME_CLIENT_ID` | `1575228314140803175` | client ID du profil `AltGr + !` |
| `GAME_NAME` | `Larping` | texte affiché pour `AltGr + !` |
| `GAME_ICON_URL` | *(vide)* | badge optionnel (`small_image`) du profil `!` |
| `LARPING_KEYBOARD` | *(auto)* | force le périphérique evdev à lire |

> L'**icône principale** à gauche de « Larping » est celle de l'application Discord
> liée au `client_id` du profil. Pour la remplacer par la tienne : crée une
> application sur `discord.com/developers/applications`, uploade ton icône, puis
> passe son ID dans `LARPING_CLIENT_ID` ou `GAME_CLIENT_ID` (par exemple dans un
> drop-in systemd `~/.config/systemd/user/larping.service.d/override.conf` :
> `Environment=LARPING_CLIENT_ID=TON_ID` et/ou `Environment=GAME_CLIENT_ID=TON_AUTRE_ID`,
> puis `systemctl --user daemon-reload && systemctl --user restart larping.service`).
> `large_image`/`small_image` ne remplacent **pas** l'icône de la liste : elles
> n'ajoutent qu'un badge sur la carte détaillée.

### Commandes utiles

```bash
~/.local/bin/larping --status   # Larping / Jeu / OFF
~/.local/bin/larping --toggle   # équivalent AltGr + :
~/.local/bin/larping --game     # équivalent AltGr + !
systemctl --user status larping.service
journalctl --user -u larping.service -f
```

### Désinstallation

```bash
./installer-larping-discord.sh --uninstall
```

---

## Désinstallation complète

```bash
./installer-capture-shift-win-s.sh --uninstall
./installer-clavier-toujours-allume.sh --uninstall
./installer-veille-jamais.sh --uninstall
./installer-touchpad-zones.sh --uninstall
./installer-numlock-toujours-actif.sh --uninstall
./installer-icones-monochromes.sh --uninstall
./installer-firefox-config.sh --uninstall
./installer-fond-noir-batterie.sh --uninstall
./installer-barre-taches-trait-blanc.sh --uninstall
./installer-larping-discord.sh --uninstall
```

## Structure du dépôt

```
.
├── installer-capture-shift-win-s.sh     # Shift+Win+S silencieux
├── installer-clavier-toujours-allume.sh # rétroéclairage toujours allumé
├── installer-clavier-retro-eclairage-ac.sh # clavier max sur secteur / min sur batterie
├── installer-veille-jamais.sh           # ni veille, ni extinction, ni verrouillage
├── installer-touchpad-zones.sh          # bords du pavé : volume / luminosité + gestes
├── installer-numlock-toujours-actif.sh  # Num Lock activé à chaque démarrage
├── installer-icones-monochromes.sh      # icônes d'applications en monochrome (thème sombre)
├── installer-firefox-config.sh          # configuration Firefox (barre de favoris en icônes seules)
├── installer-fond-noir-batterie.sh      # fond noir immédiat sur batterie, restauration au secteur
├── installer-barre-taches-trait-blanc.sh # barre épurée + trait blanc sous les applis
├── installer-larping-discord.sh  # AltGr+: / AltGr+! activent deux activités Discord
├── config/
│   ├── powerdevilrc                     # copie de référence
│   ├── kscreenlockerrc                  # copie de référence
│   ├── kcminputrc                       # copie de référence
│   ├── kxkbrc                           # clavier français au démarrage (fr,us)
│   ├── firefox/                         # configuration Firefox de référence
│   │   ├── user.js
│   │   ├── chrome/
│   │   │   └── userChrome.css
│   │   ├── flatpak-override.org.mozilla.firefox
│   │   └── org.mozilla.firefox.desktop
│   ├── touchpad-zones/                  # copies de référence (zones/gestes pavé)
│   │   ├── touchpad-zones.py            # démon gestes + zones
│   │   ├── touchpad-3tap-action.js       # 3 doigts : fermer app / extinction directe (bureau)
│   │   ├── touchpad-osd.py              # OSD volume/luminosité
│   │   ├── touchpad-zones.service
│   │   └── touchpad-osd.service
│   ├── icones-monochromes/              # icônes SVG monochromes de référence
│   ├── battery-wallpaper/               # fond noir sur batterie (copies de référence)
│   │   ├── battery-wallpaper.py          # démon D-Bus UPower
│   │   ├── battery-wallpaper.conf        # réglages (noir / image)
│   │   └── battery-wallpaper.service     # unité systemd utilisateur
│   ├── larping/                         # AltGr+: / AltGr+! -> activités Discord (référence)
│   │   ├── larping                       # démon evdev + IPC Discord
│   │   └── larping.service               # unité systemd utilisateur
│   ├── barre-taches/                     # thème Vapor White Line (copies de référence)
│   │   └── theme/
│   │       ├── colors                     # palette Vapor
│   │       ├── plasmarc
│   │       ├── metadata.desktop
│   │       └── widgets/
│   │           ├── plasmoidheading.svg
│   │           └── tasks.svgz             # fond transparent + trait blanc
│   └── fond-ecran-anime/                 # fond animé Wallpaper Engine KDE
│       └── wallpaper-engine.json          # config de référence (source vidéo, FPS, audio…)
└── README.md
```

Les installateurs sont **idempotents** : les relancer répare/actualise la configuration.
