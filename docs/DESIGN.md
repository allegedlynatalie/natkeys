# Natkeys design decisions

Settled in a design interview on 2026-11-04. Change these deliberately.

## Panel
- **Option+Space** toggles a floating panel at the mouse cursor. It's a non-activating panel, so
  the app you were typing in stays frontmost and receives the paste.
- Mostly mouse-driven. **Esc** closes it, and so does a click elsewhere, but *starting a drag*
  elsewhere does not, so you can drag files or pictures into it. ⌘-Tab away also closes it.
- Right-click items for quick actions. Larger setup lives in the Settings window.

## Saving
- On open, Natkeys reads the selection through Accessibility (`AXSelectedText`). If the app
  doesn't answer, it presses ⌘C, reads the result, and restores the clipboard. An empty answer
  only counts as "nothing selected" when it comes from a real text control.
- When a selection is found it is "armed", and **Save** buttons appear on every slot. The current
  clipboard appears as a second chip that can be armed instead.

## Weekly groups (This Week / Last Week)
- Reusable groups. Only **Sermon Title** is pre-made.
- **Shift** moves This Week → Last Week and clears This Week. It's disabled when This Week is empty.
- **Auto-shift every Sunday at 2:00 PM** (configurable time). It catches up once after the Mac
  was off, no matter how many Sundays were missed. Groups with an empty This Week are skipped.
  A manual Shift before a flip covers that flip, so it doesn't shift twice. Tracking is by Sunday
  date, so changing the flip time can't cause a double shift.

## Image groups (added 2026-11-05)
- Each weekly group is **Text** or **Image** (Settings → Weekly Groups → Holds). Text and images are
  stored in separate fields, so switching kinds loses nothing. Switching to Image imports a slot
  whose text is an image file path.
- Image slots show side by side in time order (Last Week left, This Week right) to save height.
  Empty slots say "Drag image here"; clicking one opens a file chooser.
- The original file's bytes and name are kept (a JPG stays a JPG, so it stays under
  upload limits). Images from a browser or the clipboard with no file are saved as PNG.
- Dragging a thumbnail out hands over a file URL copy named after the original, which is what
  websites' upload boxes accept. While dragging, the panel turns see-through and ignores the
  mouse so it doesn't cover the drop box, and it closes after a successful drop. Scratch tiles do
  the same.
- Shift moves the image like text. Files nothing refers to any more (last week's graphic after a
  shift) are deleted from the Images folder, never when data.json failed to load.
- Image groups can't go in combos (combos are text); Insert Field leaves them out.

## Dates
- Grid columns: Last Sunday, Today, Coming Sunday. Default rows: `MMMM d`, `MM-dd-yy`,
  `MMMM d, yyyy`, `M/d/yy`, `EEEE, MMMM d`.
- On Sunday the dates flip at the same 2:00 PM as the shift. Before it, Last = a week ago and
  Coming = today. After it, Last = today and Coming = next week. The Last Week title therefore
  always pairs with the Last Sunday date.

## Combos
- Templates with fields in braces: `{Sermon Title: Last Week} – {Last Sunday: MMMM d}` (the seeded
  combo). Incomplete combos show placeholders and won't paste.
- Renaming a group rewrites its fields in combos.

## Pasting
- Natkeys writes to the clipboard, presses ⌘V, and restores the original clipboard about 0.6 s
  later (a setting). Writes are marked `org.nspasteboard.TransientType` so clipboard managers
  ignore them.
- Without Accessibility permission, clicking only copies, and a HUD says to press ⌘V.
- While not allowed, Natkeys checks once a second and confirms with a HUD the moment it's allowed.
- macOS stores each Accessibility grant with the allowed build's code requirement. An ad hoc
  build's requirement is its exact hash, and switching the grant off and on keeps that stored
  requirement. So after the signing identity changes (ad hoc → "Natkeys Local"), the grant
  silently stops matching (tccd: `auth_reason 5`, `SecStaticCodeCheckValidity … -67050`).
  **Reset Permission** runs `tccutil reset Accessibility io.github.allegedlynatalie.natkeys` and re-prompts. The
  panel's "Allow auto-paste…" offers it on the second click (added 2026-11-04).

## Scratch clipboards
- Hold plain text or images (stored as PNG files).
- Ways to fill one: save the selection, save the clipboard, drag into the panel, or type in an editor.
- Optional name; otherwise a content preview is shown.
- Pinned scratches show in the panel, and the others sit under a collapsible **More** row. New
  scratches start unpinned.
- Image tiles drag out as real file URLs (named after the scratch), so websites' "drop image here"
  upload boxes accept them.

## Right-click menu (added 2026-11-04)
- Built on macOS Services, the only supported way to add items to other apps' context menus.
  The entries are declared under `NSServices` in Info.plist and handled by `ServiceProvider`.
- **Open Natkeys** has a return type only, so it shows in any editable text box. **Save to Natkeys**
  has a send type only, so it shows on any selected text and hands that text to the panel, already armed.
- Handlers return immediately without writing anything back (the text box is left untouched) and
  open the panel 0.15 s later. Service calls are synchronous, so the other app waits on them.

## App
- App ID `io.github.allegedlynatalie.natkeys`.
- Menu bar only (no Dock icon), with launch at login turned on the first time the installed copy runs.
- Data stays on this Mac in `~/Library/Application Support/Natkeys`. Backup is Export/Import of a
  single JSON file that includes the images.
- Option+Space is fixed. If another app (for example Claude's Quick Entry) holds it, Natkeys
  warns and offers Try Again.
