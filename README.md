# 🧚 hey-listen

system utilities for coding agents on macOS — sounds, notifications, toasts, screen overlays, window info, and a fairy.

built for use inside sandboxed environments (like [safehouse](https://github.com/nichochar/agent-safehouse)) where `afplay` and other system commands are blocked.

## install

```bash
npm i -g hey-listen
```

or build from source:

```bash
git clone https://github.com/natew/hey-listen
cd hey-listen
swiftc -O -swift-version 5 \
  -framework AppKit -framework AVFoundation -framework UserNotifications \
  -framework IOKit -framework CoreGraphics \
  -parse-as-library -target arm64-apple-macosx13.0 \
  Sources/hey-listen/agent_ping.swift -o hey-listen
cp hey-listen ~/.local/bin/
```

## setup

run the setup screen to grant permissions (notifications, accessibility):

```bash
hey-listen setup
```

or start the menu bar daemon:

```bash
hey-listen
```

## commands

```
hey-listen sound done                    # play a system sound
hey-listen sound error --volume 0.5      # with volume control
hey-listen sound --list                  # list all sounds

hey-listen notify "title" "body"         # macOS notification
hey-listen toast "deploying..."          # floating HUD overlay
hey-listen fairy "hey! look!"            # animated fairy flies around screen

hey-listen highlight 100 200 400 300     # pulsing bounding box
hey-listen highlight 0 0 500 500 \
  --color green --label "here"           # with color + label

hey-listen windows                       # list visible windows + bounds
hey-listen windows --app Terminal        # filter by app
hey-listen windows --json                # json output

hey-listen say "task finished"           # text-to-speech
hey-listen say --list                    # list voices

hey-listen open https://example.com      # open URL
hey-listen info battery                  # system info

hey-listen login enable                  # start on login
```

### sound aliases

`success` `error` `warning` `done` `start` `ping` `pop` `purr` `tink` `morse` `submarine` `funk` `frog` `bottle`

## requirements

- macOS 13+
- Xcode command line tools (`xcode-select --install`)

## license

MIT
