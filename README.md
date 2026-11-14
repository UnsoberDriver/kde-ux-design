# Correctifs UX KDE Plasma (Bazzite / Wayland)

Deux correctifs « qualité de vie » pour **Bazzite / KDE Plasma 6 (Wayland)**, testés sur un
**ASUS V16 (V3607VM)** :

| Correctif | Effet |
|---|---|
| [`installer-capture-shift-win-s.sh`](#1-capture-décran--shift--win--s-façon-windows) | `Shift + Win + S` capture une région, copie et enregistre — **sans aucune fenêtre** |
| [`installer-clavier-toujours-allume.sh`](#2-rétroéclairage-du-clavier-toujours-allumé) | Le rétroéclairage du clavier **reste toujours allumé** |

Tout s'installe **au niveau utilisateur** : aucun `sudo`, aucun paquet à installer.

## Prérequis

- KDE Plasma 6 sous Wayland (Bazzite, Fedora Kinoite, etc.)
- `spectacle`, `wl-clipboard` (`wl-copy`), `systemd` utilisateur
- Pour le clavier : un portable exposant `/sys/class/leds/*kbd_backlight`
  (écriture accessible à l'utilisateur ; c'est le cas des ASUS avec `asus-wmi`)

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

## Désinstallation complète

```bash
./installer-capture-shift-win-s.sh --uninstall
./installer-clavier-toujours-allume.sh --uninstall
```

## Structure du dépôt

```
.
├── installer-capture-shift-win-s.sh     # Shift+Win+S silencieux
├── installer-clavier-toujours-allume.sh # rétroéclairage toujours allumé
└── README.md
```

Les installateurs sont **idempotents** : les relancer répare/actualise la configuration.
