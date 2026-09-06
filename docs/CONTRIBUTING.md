# Contributing to My Journal

Omarchy bar-widget plugin (`io.github.mohuddle.myjournal`). QML + plain JavaScript, plus a stdlib Python store helper. No build step.

## Verify

```bash
omarchy plugin validate .
node tests/model.test.js
python3 tests/test_store.py
```

Run all three before committing. No linter, formatter, or typecheck.

## Architecture

- `manifest.json` — plugin id, kind (`bar-widget`), entry point (`BarWidget.qml`)
- `BarWidget.qml` — bar entry. Creates `Service` and a lazy-loaded `Panel`
- `Panel.qml` — popout UI. Imports `Model.js` as a QML singleton
- `Service.qml` — state + persistence via `bin/journal-store.py`
- `bin/journal-store.py` — descriptor-bound read/write of `journal.json` and `notes.txt`
- `Model.js` — pure data functions. No QML/Qt imports so Node tests can require it

## Entries

Each entry is `{ id, timestamp, content, kind }` with optional `done` on todos.

- `kind` is `"note"` (default) or `"todo"`
- Missing `kind` on disk is a note
- **New** → `Service.startNewNote()` / `Model.newEntry`
- **ToDo** → `Service.startNewTodo()` / `Model.newTodo`
- Do not add a parallel `createTodo` API or a separate `todos.json`
- Blank current entry: retag its kind instead of inserting another blank
- Toggle completion with `Service.toggleDone` / `Model.toggleDone`, not by rewriting content
- Numeric string ids only; content is capped in `Model.js` and the store helper

## Model.js dual-export

CommonJS guard (`typeof module !== "undefined"`) at the bottom, one export object. In QML: `import "Model.js" as Model`. Keep functions self-contained with no Qt dependencies. Replace a whole function; do not append after it.

## Persistence

Do not read or write the journal with `FileView.text()` / `setText()`. `FileView` is a change watcher only. All file I/O goes through `bin/journal-store.py` as an argv array (`/usr/bin/python3 -I -S`). Writes travel on stdin, not argv.

## Test

```bash
node tests/model.test.js
python3 tests/test_store.py
```
