# My Journal for Omarchy

A stream-of-consciousness journal for the Omarchy Quattro bar. Click the notebook to start a new dated note. Search previous sessions by id, time, or text. Autosave writes a JSON list of entries; optionally encrypt the whole file at rest with [age](https://github.com/FiloSottile/age).

![Plugin preview](preview.png)

Plugin id: `io.github.mohuddle.myjournal`

## What it does

- Opening the panel creates a new empty note, stamps it with the current date and time, and puts the cursor on a blank line.
- **New** starts another session. The left index lists every saved note by id.
- Search filters the index. Click a row to reopen that note.
- Autosave (about a second after typing, and again on close) writes the full entry list.
- Until you set a passphrase, that list is `journal.json` plus a readable `notes.txt`.
- With a passphrase, the same JSON is encrypted with `age --passphrase` to `journal.json.age`, and the plaintext files are removed.

No Omarchy keybindings are changed.

## Data

Unencrypted:

```
~/.local/state/omarchy/myjournal/journal.json
~/.local/state/omarchy/myjournal/notes.txt
```

Encrypted:

```
~/.local/state/omarchy/myjournal/journal.json.age
```

The JSON is an append-only list of sessions:

```json
[
  {
    "id": "1",
    "timestamp": "2026-08-19T10:10:00.000Z",
    "content": "Had a great brainstorming session about my new TUI app today."
  }
]
```

Blank sessions are dropped on close so the file does not fill with empty opens. The passphrase is held in memory for the shell session only; **Lock** in settings forgets it.

## Install

```bash
omarchy pkg add age
omarchy plugin add https://github.com/mohuddle/omarchy-myjournal.git --enable
```

`age` is only required if you want encryption at rest. The journal works without it, using JSON + `notes.txt`.

Move the widget:

```bash
omarchy bar move io.github.mohuddle.myjournal --section right
```

## Usage

- Left-click the notebook: open a pinned journal (stays on top across windows and workspaces) and start a new dated note. Click the icon again to close and save.
- **New**: another empty session.
- Search box: filter by id, timestamp, or content.
- Click an index row: open that note.
- Gear: set an age passphrase (encrypts the whole file) or lock an encrypted journal.
- Escape closes the panel and saves.

## Remove

```bash
omarchy plugin remove io.github.mohuddle.myjournal
```

Journal files under `~/.local/state/omarchy/myjournal/` are left in place. To start over without reinstalling the plugin, close My Journal and delete that directory:

```bash
rm -rf ~/.local/state/omarchy/myjournal
```

Then click the notebook icon again. You get a fresh unencrypted journal.

## Development checks

```bash
omarchy plugin validate .
node tests/model.test.js
```

## License

MIT. See [LICENSE](LICENSE).
