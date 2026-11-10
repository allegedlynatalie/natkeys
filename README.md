# Natkeys

A menu bar hotkey utility for church media work. Press **Option+Space** anywhere to open a
small panel at your mouse, then click once to paste a sermon title, a Sunday date, a combo of
the two, or one of your scratch clipboards into the app you're typing in.

## Using it

**Paste something:** click into a text box, press **Option+Space**, and click what you want.
Natkeys pastes it, then puts your own clipboard back.

**Save selected text:** select text in any app (for example, this week's sermon title), press
**Option+Space**, and click **Save** next to the slot it belongs in. The panel also shows your
current clipboard as a chip. Click that chip to save the clipboard instead, which is handy for
images you copied with "Copy Image".

**Panel sections**

| Section | What it does |
| --- | --- |
| **Sermon Title** (and any other weekly groups) | This Week / Last Week. **Shift This → Last** moves This Week down. This also happens automatically **every Sunday at 2:00 PM**, and catches up if the Mac was off. |
| **Combos** | One-click templates such as `The Narrow Gate – November 1`. |
| **Dates** | Every format × Last Sunday / Today / Coming Sunday. On Sundays the dates flip at 2:00 PM, matching the sermon shift. |
| **Scratch** | Text or image clipboards. Pinned ones always show; the rest are under **More**. Click to paste, drag an image straight into a website's upload box, or drop text or images onto a tile to save them. |

Right-click anything in the panel for more options: Copy, Edit…, Pin/Unpin, Replace with
Clipboard, Clear, and Delete. Press **Esc** or click elsewhere to close the panel.

**From any app's right-click menu:** Natkeys adds two macOS Services.
- **Open Natkeys** appears when you right-click in a text box, and works the same as Option+Space.
- **Save to Natkeys** appears when you right-click selected text, including on web pages. It
  opens the panel with that text ready to save.

macOS decides where they go. With text selected they're usually listed near the bottom of the
menu; otherwise look under **Services ▸**. You can turn either one off, or give it its own
shortcut, in System Settings → Keyboard → Keyboard Shortcuts… → Services → Text.

**Settings** (gear icon in the panel, or the ⌨︎ menu bar icon → Settings…) has these tabs:
- **General:** Sunday flip time, clipboard restore, launch at login, Export/Import backup.
- **Weekly Groups:** rename groups, add new ones (Scripture, Preacher…), edit values, and turn auto-shift on or off per group.
- **Combos:** edit templates. **Insert Field** adds `{Sermon Title: Last Week}`, `{Last Sunday: MMMM d}`, and similar fields.
- **Date Formats:** add, remove, and reorder rows of the date grid.
- **Scratch:** name, pin, reorder, and edit scratch clipboards.

## Permissions

Natkeys needs **Accessibility** access (System Settings → Privacy & Security → Accessibility)
to read selected text and press ⌘C/⌘V for you. Without it the panel still opens, but clicking an
item only copies it, so you'd press ⌘V yourself. Once you switch it on, a bubble says
"Natkeys can paste for you now".

**Switched on, but Natkeys still says it isn't allowed?** macOS saves the permission for the
exact build you allowed. If Natkeys was later signed differently (for example, before and after
you made the certificate below), that saved permission never matches again, and switching it off
and on doesn't update it. Click **Reset Permission** in Settings → General (or click *Allow
auto-paste…* in the panel a second time). Natkeys removes itself from the list and asks again;
switch it on when it reappears. You can also do this in Terminal:

```bash
tccutil reset Accessibility io.github.allegedlynatalie.natkeys
```

> The build signs Natkeys with a self-signed **Natkeys Local** certificate if one is in your
> keychain (Keychain Access → Certificate Assistant → Create a Certificate… → Code Signing).
> Keychain Access will say it's "not trusted"; that's fine. Because every build carries the same
> identity, the Accessibility permission survives rebuilds. Without the certificate each build is
> signed ad hoc, and you'd need **Reset Permission** after every reinstall.

If Option+Space doesn't open the panel, another app may own it. Claude's Quick Entry is a common
one: change its shortcut in Claude → Settings, then use the menu bar icon → *Try Again*.

## Building

Needs only the Xcode Command Line Tools (Swift 6), not the full Xcode.

```bash
./scripts/install.sh        # build, copy to /Applications, launch
./scripts/build-app.sh      # just build build/Natkeys.app
swift test                  # date math, weekly shift, combo template tests
```

`Natkeys --snapshot <folder>` renders the panel and Settings tabs to PNGs using sample data,
without touching your real data. It's useful for checking layout changes.

## Layout

```
Sources/NatkeysCore/   pure logic: data model, Sunday math, auto-shift, combo templates (tested)
Sources/Natkeys/
  AppDelegate.swift    menu bar icon, hotkey, timers, Settings window
  Store.swift          load/save ~/Library/Application Support/Natkeys (data.json + Images/)
  Panel/               the floating panel (AppKit window + SwiftUI views, drag & drop tiles)
  System/              hotkey, clipboard, selection grab, paste, HUD, login item
  Windows/             Settings and editor windows
Tests/NatkeysCoreTests/
docs/DESIGN.md         the decisions behind how it works
```
