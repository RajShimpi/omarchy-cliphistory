# Clipboard History

Everything you copy, text and images, kept for 24 hours (or as long as you
like) and one click away in the Omarchy bar. Search it, copy it back, type it
into any window, and pin what you want to keep. Password-manager copies are
never stored, and nothing leaves your computer.

Plugin id: `techspawn.cliphistory`

## What it does

- **Records in the background.** A small service watches the clipboard and
  stores each new text or image copy (PNG, JPEG, WebP, GIF, BMP). Copying the
  same thing again moves it to the top instead of adding a duplicate.
- **Bar:** a quiet clipboard icon. Hover it to see how many items are stored.
  Click it to open the panel.
- **Panel:** a search field and the history, newest first, with how long ago
  you copied each item and from which app. Text shows a two-line preview and
  images show a thumbnail. Pinned items sit in their own section at the top.
- **Copy back:** click an item, or press Enter, to put it on the clipboard
  again.
- **Type it:** Shift+Enter, or Shift+click, types a text item straight into
  the window you were in, using `wtype`. This helps with apps that block paste.
- **Pin:** pinned items never expire and are not counted against the item
  limit. Unpinning an item older than the retention window gives it a fresh
  window rather than deleting it on the spot.
- **Delete** one item, or **clear** the whole history (pinned items stay)
  after a confirmation.
- **Expiry:** items older than the retention window are deleted, image files
  included. This happens on every copy, every hour, and whenever the panel
  opens.

### Keyboard

When the panel is open:

| Key | Action |
| --- | --- |
| `j` / `k`, Down / Up | Move. PageUp / PageDown jump, `g` / `G` go to the first / last item. |
| Enter | Copy the item back to the clipboard and close. |
| Shift+Enter | Type it into the focused window (text only). |
| `p` | Pin / unpin. |
| `x`, Delete | Delete the item. |
| `/` or any other letter | Search. Words match anywhere in the text or the source app. `image` finds images. |
| Shift+C | Clear the history (asks first, pinned items stay). |
| Esc | Clear the search, then close. |
| Tab | Next bar panel. |

In the search field, Up / Down (or Ctrl+J / Ctrl+K) still move, Enter and
Shift+Enter work the same, Ctrl+P pins, and Tab returns to the list with the
filter kept, so `x` and `p` work on what you found.

The mouse works too: click copies, Shift+click types, middle-click pins, and
the icons on the highlighted row pin, type or delete.

## Install

```bash
omarchy plugin add https://github.com/RajShimpi/omarchy-cliphistory
omarchy plugin enable techspawn.cliphistory
omarchy bar put techspawn.cliphistory
```

You can also use **Install plugin** in the Omarchy menu with the repository URL.

### Open it with a key

Nothing is bound by default. To open the panel on the focused monitor with
Super+Alt+V, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + V", "Clipboard history", "omarchy-shell shell toggle techspawn.cliphistory")
```

(Omarchy already uses Super+V to paste and Super+Ctrl+V for its own clipboard
manager.)

## Remove

```bash
omarchy plugin remove techspawn.cliphistory
```

To delete the stored history and your settings as well:

```bash
rm -rf ~/.local/state/omarchy/clip24 ~/.config/omarchy/cliphistory.json
```

## Settings

Click the pencil in the panel. The first time, this creates
`~/.config/omarchy/cliphistory.json` with the defaults and opens it in your
editor. The plugin never writes that file otherwise. Missing keys use these
defaults:

```json
{
  "retentionHours": 24,
  "maxItems": 500,
  "images": true,
  "maxImageMB": 10,
  "maxTextKB": 512,
  "ignoreApps": ["*keepassxc*", "*bitwarden*", "*1password*", "*proton*pass*", "*enpass*", "org.gnome.World.Secrets"]
}
```

| Key | Meaning |
| --- | --- |
| `retentionHours` | Unpinned items older than this are deleted (1 to 8760). |
| `maxItems` | The newest unpinned items to keep (10 to 5000). Pinned items don't count. |
| `images` | Record copied images. |
| `maxImageMB` | Larger images are not stored. |
| `maxTextKB` | Larger text is not stored. It is skipped rather than cut off, so what you copy back is always complete. |
| `ignoreApps` | Window classes whose copies are never stored. These are glob patterns matched case-insensitively against the class of the focused window (`hyprctl activewindow`). Find a window's class with `hyprctl clients`. |

Changes apply to the next copy. There is no need to restart anything.

## Privacy

- Everything is stored only on this computer, in
  `~/.local/state/omarchy/clip24/`: `history.json` for text and `images/` for
  pictures. The folder is private to your user (mode 700, files 600), but
  **it is not encrypted**. Anyone who can read your home directory as you can
  read your recent copies.
- Never stored:
  - copies marked sensitive: `wl-copy --sensitive`, and password managers that
    set the `x-kde-passwordManagerHint` type, such as KeePassXC
  - copies made while an app in `ignoreApps` has focus
  - empty or whitespace-only text
  - anything over the size limits
- Expired items are deleted from disk, not hidden.
- To wipe everything now, use **Clear** in the panel (pinned items stay), or:

  ```bash
  ~/.config/omarchy/plugins/techspawn.cliphistory/scripts/clip24 clear --all
  ```

- Omarchy's own clipboard manager (Super+Ctrl+V) keeps a separate history in
  `~/.local/state/omarchy/clipboard-history.json` and `clipboard-images/`.
  This plugin neither reads nor changes it.

## How it works and dependencies

- `Service.qml` runs once per shell. It starts two `wl-paste --watch`
  processes, one for text and one for images, and each new copy is handed to
  `scripts/clip24`. Watchers left over from an earlier shell are stopped first.
  Ours are tied to the shell with `setpriv --pdeathsig`, so they cannot pile up
  across restarts. A watcher that exits is restarted, backing off while it
  keeps failing.
- `Panel.qml` is the bar widget, one per monitor. It records nothing. It only
  calls `scripts/clip24` when you open the panel, hover the icon or act on an
  item.
- `scripts/clip24` is a Python 3 script that uses only the standard library.
  Every change happens under a file lock and is written atomically, so two
  copies at once can't corrupt the history.
- Requires:
  - `wl-clipboard` (`wl-copy`, `wl-paste`)
  - `wtype`, for Shift+Enter
  - `python3`
  - `hyprctl`, `setpriv` and `pkill`

  Omarchy ships all of them. Thumbnails are drawn by the shell itself, so
  ImageMagick is not needed.

### Command line

Other scripts and plugins can use the helper directly:

```
clip24 list                 every entry as JSON, newest first
clip24 copy <id>            put an entry back on the clipboard
clip24 type <id>            type a text entry into the focused window
clip24 pin <id> [on|off]    pin / unpin (toggles without on|off)
clip24 delete <id>
clip24 clear [--all]        delete everything except pinned entries (--all: those too)
clip24 prune                drop expired entries now
clip24 config               print the settings in effect
```

`CLIPHISTORY_DIR` and `CLIPHISTORY_CONFIG` point it at another state folder
or settings file, which is handy for testing.

## License

MIT. See [LICENSE](LICENSE).
