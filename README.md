# Granola Quick Note

A [Hammerspoon](https://www.hammerspoon.org) Spoon that turns one key into "start a Granola note and record." Tap the key, Granola opens a new note with transcription running, and its window comes to the front, even if it was parked on another Space.

By default it grabs the **mic key** (the F5 dictation key on many Mac keyboards). It swallows the key, so dictation and hold-for-Siri never fire.

> **Not affiliated with Granola.** This is an independent hobby project. It relies on Granola's `granola://new-document` deep link, which is **unofficial and undocumented**. Granola can change or remove it at any time, and this will stop working when they do.

## What it does

1. You tap the key.
2. If Granola isn't running, it launches it and waits for the main window (a link sent during a cold start can get dropped).
3. It opens `granola://new-document?creation_source=hammerspoon&auto_transcribe=1` in Granola, which creates a note and starts recording.
4. It finds Granola's window (on any Space), switches to that Space if needed, and focuses it.

## Install

You need Hammerspoon, Granola, and the Xcode command line tools (`xcode-select --install`) if you want cross-Space focusing.

```bash
git clone https://github.com/teeejlind/granola-quick-note.git
cd granola-quick-note
GranolaQuickNote.spoon/helper/build.sh          # builds GranolaQuickNote.spoon/bin/app-windows
cp -R GranolaQuickNote.spoon ~/.hammerspoon/Spoons/
```

Add to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("GranolaQuickNote"):start()
```

Reload Hammerspoon. Hammerspoon needs the Accessibility permission (it asks the first time).

The helper is optional. Without it the Spoon still works, but it can only find Granola's window if that window is on a Space you can currently see.

## Configure

```lua
hs.loadSpoon("GranolaQuickNote")
spoon.GranolaQuickNote:configure({
  keyCode = "f19",          -- number or key name; default 176 (mic key)
  autoTranscribe = false,   -- default true; false opens the note without recording
  launchWaitSeconds = 30,   -- default 20; how long to wait for Granola's window after launching it
}):start()
```

| Option | Default | |
|---|---|---|
| `keyCode` | `176` | Key to capture. A number is a raw keycode; a string is looked up in `hs.keycodes.map`. |
| `autoTranscribe` | `true` | Adds `auto_transcribe=1` to the link so recording starts. |
| `launchWaitSeconds` | `20` | Max wait for Granola's window on a cold start. After that the link is sent anyway. |
| `launchSettleSeconds` | `1.5` | Pause after the window appears before sending the link. |
| `cooldownSeconds` | `2` | Ignore presses this soon after the last one. |
| `bundleID` | `com.granola.app` | Granola's bundle ID. |
| `url` | none | Replace the whole deep link (ignores `autoTranscribe`). |
| `windowHelper` | `bin/app-windows` in the Spoon | Path to the compiled helper. |
| `focusAttempts`, `focusRetrySeconds` | `8`, `0.4` | How hard to try to focus the window. |
| `logPath` | `granola_quick_note.log` in your Hammerspoon config folder | Set `false` to disable logging. |

### Finding your own keycode

The default `176` is what the mic key sends on the author's Mac (a plain key event, not a media-key event). Yours may differ. Paste this into the Hammerspoon console, press the key, and read the number:

```lua
tapper = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(e) print(e:getKeyCode()); return false end):start()
-- when done: tapper:stop()
```

If nothing prints when you press the key, it's a system media key (`NX_SYSDEFINED`) and not a plain key event. This Spoon only handles plain key events. You can remap that key to something else (for example F19) with Karabiner-Elements or a similar tool, then use `keyCode = "f19"`.

## The Spaces caveat

macOS has a setting, "When switching to an application, switch to a Space with open windows" (System Settings > Desktop & Dock > Mission Control). If it's off, activating Granola leaves its window on whatever Space it was on, and you see nothing. The Spoon works around this: Accessibility can only see windows on visible Spaces, so the `app-windows` helper asks CoreGraphics for Granola's windows on all Spaces, and the Spoon calls `hs.spaces.gotoSpace` for the right one. It only switches the display that Granola's window is on.

`hs.spaces` uses private macOS APIs. It can fail with "unable to get Mission Control data from the Dock," usually transiently, and it can break on macOS updates. The Spoon retries and falls back to a plain activate.

### The helper

`GranolaQuickNote.spoon/helper/app-windows.swift` is about 25 lines. It prints one line per normal-layer window of a given bundle ID (`<windowID> <width>x<height> <title>`) and nothing else. `helper/build.sh` compiles it with `swiftc` into `GranolaQuickNote.spoon/bin/`, which is gitignored. No binaries are shipped; build it yourself and read the source first.

## Debug

From the Hammerspoon console:

```lua
spoon.GranolaQuickNote:status()      -- tap running? key seen? last launch/focus result, helper built?
spoon.GranolaQuickNote:focusTest()   -- focus Granola's window only; no note, no recording
```

Check the log file (see `logPath`). Common problems:

- **Key does nothing:** `status().enabled` false means Hammerspoon lacks Accessibility permission. If it's true and `secondsSinceKeyDetected` stays nil, your keycode is wrong.
- **Note opens but window stays hidden:** helper not built (`helperBuilt = false`), or `gotoSpace` is failing. See the log.
- **Nothing happens after a cold start:** raise `launchWaitSeconds` / `launchSettleSeconds`.

Careful: pressing the key really does start a recording. Use `focusTest()` when testing window focus.

## Status

Written for and used on macOS with Hammerspoon. Not tested across macOS versions or keyboards beyond the author's.

## License

MIT, see [LICENSE](LICENSE).
