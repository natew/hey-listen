---
description: "hey-listen: system utilities for coding agents — sounds, notifications, toasts, overlays, fairy, window info. Use /hey-listen for any alert, sound, notification, or visual overlay."
---

## sounds

```bash
hey-listen sound hey          # navi sounds: hey, hello, listen, look, watchout, in, out, float, bonk
hey-listen sound done         # system aliases: success, error, warning, done, start, ping, pop, purr, tink
hey-listen sound error --volume 0.5
```

## notifications

```bash
hey-listen notify "Title" "body text"
hey-listen toast "deploying..."          # floating HUD
```

## fairy overlay

```bash
hey-listen fairy "check this!" --window Terminal --sound hey
hey-listen fairy "look" --at 500,300 --corner tl --duration 10
```

## highlight

```bash
hey-listen highlight 100 200 400 300 --color green --label "button"
```

## windows

```bash
hey-listen windows --app Terminal --json
```

## other

```bash
hey-listen say "task finished"
hey-listen info battery
```
