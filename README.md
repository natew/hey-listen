# hey-listen

system utilities for coding agents on macOS — sounds, notifications, toasts, screen overlays, window info, and a pixel art fairy.

built for use inside sandboxed environments (like [safehouse](https://github.com/nichochar/agent-safehouse)) where `afplay` and other system commands are blocked.

## install

```bash
bun i -g hey-listen-cli
```

the npm package ships a pre-built signed binary. after install, run:

```bash
hey-listen setup
```

## build from source

requires macOS 13+ and Xcode CLI tools (`xcode-select --install`).

```bash
git clone https://github.com/natew/hey-listen
cd hey-listen
bun run build
```

optionally sign the binary:

```bash
bun run sign
```

copy to your PATH:

```bash
cp hey-listen ~/.local/bin/
cp -r sounds ~/.local/bin/sounds
```

## commands

```
hey-listen                               # start menu bar daemon
hey-listen setup                         # grant permissions

hey-listen sound hey                     # navi sounds
hey-listen sound listen
hey-listen sound --list                  # list all sounds
hey-listen sound done --volume 0.5       # system sounds with volume

hey-listen notify "title" "body"         # macOS notification
hey-listen toast "deploying..."          # floating HUD overlay

hey-listen fairy "check this!"           # pixel art fairy overlay
  --window Terminal                      #   position on a window
  --corner tl                            #   tl, tr, bl, br, center
  --at 500,300                           #   exact screen position
  --sound hey                            #   play sound on appear
  --duration 10                          #   seconds (default: 10)

hey-listen highlight 100 200 400 300     # pulsing bounding box
  --color green --label "here"

hey-listen windows                       # list visible windows
hey-listen windows --app Terminal        # filter by app
hey-listen windows --json                # json output

hey-listen say "task finished"           # text-to-speech
hey-listen open https://example.com      # open URL
hey-listen info battery                  # system info
hey-listen login enable                  # start on login
```

### navi sounds

`hey` `hello` `listen` `look` `watchout` `in` `out` `float` `bonk`

### system sound aliases

`success` `error` `warning` `done` `start` `ping` `pop` `purr` `tink` `morse` `submarine` `funk` `frog` `bottle`

## license

MIT
