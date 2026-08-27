import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// In-memory journal persisted as journal.json plus a readable notes.txt.
Item {
  id: root
  property var settings: ({})
  readonly property string home: Quickshell.env("HOME")
  readonly property string storeDir: home + "/.local/state/omarchy/myjournal/"
  readonly property string jsonPath: storeDir + "journal.json"
  readonly property string txtPath: storeDir + "notes.txt"

  property var entries: []
  property string currentId: ""
  property bool filesReady: false
  property bool saving: false
  property bool writingOwn: false
  property bool pendingOpen: false
  property string lastError: ""
  property string statusText: "My Journal"

  readonly property var currentEntry: Model.findById(entries, currentId)
  readonly property int entryCount: entries.length

  function currentContent() {
    return currentEntry ? String(currentEntry.content || "") : ""
  }

  function begin() {
    pendingOpen = true
    if (!filesReady) {
      ensureDir.running = true
      return
    }
    startNewNote()
  }

  function startNewNote() {
    startFresh("note")
  }

  function startNewTodo() {
    startFresh("todo")
  }

  function startFresh(kind) {
    entries = Model.dropBlanks(entries, currentId)
    var current = Model.findById(entries, currentId)
    if (current && Model.isBlank(current)) {
      if (Model.entryKind(current) !== kind) {
        current.kind = kind
        if (kind === "todo") current.done = false
        entries = Model.upsert(entries, current)
        scheduleSave()
      }
      return
    }
    var entry = kind === "todo"
      ? Model.newTodo(new Date(), Model.nextId(entries))
      : Model.newEntry(new Date(), Model.nextId(entries))
    entries = Model.upsert(entries, entry)
    currentId = entry.id
    scheduleSave()
  }

  function toggleDone(id) {
    entries = Model.toggleDone(entries, id)
    scheduleSave()
  }

  function openEntry(id) {
    entries = Model.dropBlanks(entries, id)
    var found = Model.findById(entries, id)
    if (!found) return
    currentId = found.id
  }

  function setContent(text) {
    if (currentId === "") return
    var entry = Model.findById(entries, currentId)
    if (!entry) return
    entry.content = String(text || "")
    entries = Model.upsert(entries, entry)
    scheduleSave()
  }

  function flushBlank() {
    entries = Model.dropBlanks(entries, "")
    if (currentId !== "" && !Model.findById(entries, currentId)) currentId = ""
  }

  function scheduleSave() {
    saveTimer.restart()
  }

  function saveNow() {
    saveTimer.stop()
    if (!filesReady) return
    var list = Model.dropBlanks(entries, "")
    writingOwn = true
    saving = true
    jsonFile.setText(Model.serializeJournal(list))
    txtFile.setText(Model.notesTxt(list))
  }

  function applyLoaded(raw) {
    var parsed = Model.parseJournal(raw)
    if (parsed === null) {
      lastError = "Couldn’t parse the journal file."
      return
    }
    entries = parsed
    lastError = ""
    if (pendingOpen) startNewNote()
  }

  Timer {
    id: saveTimer
    interval: 900
    repeat: false
    onTriggered: root.saveNow()
  }

  Process {
    id: ensureDir
    command: ["mkdir", "-p", root.storeDir]
    onExited: function(code) {
      if (code !== 0) { root.lastError = "Couldn’t create the journal directory."; return }
      root.filesReady = true
      jsonFile.reload()
    }
  }

  property FileView jsonFile: FileView {
    path: root.jsonPath
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.writingOwn) {
        root.writingOwn = false
        root.saving = false
        return
      }
      root.applyLoaded(text())
    }
    onLoadFailed: {
      root.entries = []
      root.lastError = ""
      if (root.pendingOpen) root.startNewNote()
    }
  }

  property FileView txtFile: FileView {
    path: root.txtPath
    atomicWrites: true
    printErrors: false
  }

  Component.onCompleted: ensureDir.running = true
}
