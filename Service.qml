import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// In-memory journal persisted through bin/journal-store.py.
Item {
  id: root
  property var settings: ({})
  readonly property string home: Quickshell.env("HOME")
  readonly property string storeDir: home + "/.local/state/omarchy/myjournal/"
  readonly property string jsonPath: storeDir + "journal.json"
  readonly property string helperPath: Model.fileUrlToPath(Qt.resolvedUrl("bin/journal-store.py"))

  property var entries: []
  property string currentId: ""
  property bool filesReady: false
  property bool saving: false
  property bool pendingOpen: false
  property bool pendingSave: false
  property bool ignoreOwnWrite: false
  property string lastError: ""
  property string statusText: lastError !== "" ? lastError : "My Journal"
  property string storeOp: "read"
  property string pendingPayload: ""
  property string outBuf: ""
  property string errBuf: ""

  readonly property var currentEntry: Model.findById(entries, currentId)
  readonly property int entryCount: entries.length

  function currentContent() {
    return currentEntry ? String(currentEntry.content || "") : ""
  }

  function begin() {
    pendingOpen = true
    if (!filesReady) {
      loadFromDisk()
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
    entry.content = Model.clipContent(text)
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
    runStore("write", Model.serializeJournal(Model.dropBlanks(entries, "")))
  }

  function loadFromDisk() {
    if (storeProc.running) return
    runStore("read", "")
  }

  function runStore(op, payload) {
    if (storeProc.running) {
      if (op === "write") pendingSave = true
      return
    }
    if (op === "write") {
      ignoreOwnWrite = true
      saving = true
    }
    storeOp = op
    pendingPayload = payload || ""
    outBuf = ""
    errBuf = ""
    storeProc.running = true
  }

  function applyLoaded(raw) {
    var parsed = Model.parseJournal(raw)
    if (parsed === null) {
      lastError = "Couldn’t parse the journal file."
      return
    }
    entries = parsed
    lastError = ""
    filesReady = true
    if (pendingOpen) startNewNote()
  }

  function finishStore(code) {
    deadline.stop()
    killTimer.stop()
    if (storeOp === "read") {
      if (code !== 0) {
        lastError = errBuf !== "" ? errBuf.replace(/\s+$/, "") : "Couldn’t read the journal file."
        return
      }
      applyLoaded(outBuf)
      return
    }
    saving = false
    if (code !== 0) {
      lastError = errBuf !== "" ? errBuf.replace(/\s+$/, "") : "Couldn’t save the journal."
      ignoreOwnWrite = false
    } else {
      lastError = ""
      ownWriteTimer.restart()
    }
    if (pendingSave) {
      pendingSave = false
      saveNow()
    }
  }

  Timer {
    id: saveTimer
    interval: 900
    repeat: false
    onTriggered: root.saveNow()
  }

  Timer {
    id: deadline
    interval: 15000
    repeat: false
    onTriggered: {
      storeProc.signal(15)
      killTimer.start()
    }
  }

  Timer {
    id: killTimer
    interval: 2000
    repeat: false
    onTriggered: storeProc.signal(9)
  }

  Timer {
    id: ownWriteTimer
    interval: 400
    repeat: false
    onTriggered: root.ignoreOwnWrite = false
  }

  Process {
    id: storeProc
    command: ["/usr/bin/python3", "-I", "-S", root.helperPath, root.storeOp]
    clearEnvironment: true
    environment: ({
      "HOME": root.home || "",
      "PATH": "/usr/bin",
      "LC_ALL": "C"
    })
    stdinEnabled: root.storeOp === "write"
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.outBuf += chunk
        if (root.outBuf.length > Model.MAX_BYTES) {
          storeProc.signal(15)
          killTimer.start()
        }
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.errBuf += chunk
        if (root.errBuf.length > 200)
          root.errBuf = root.errBuf.substring(0, 200)
      }
    }
    onStarted: {
      deadline.restart()
      if (root.storeOp === "write") storeProc.write(root.pendingPayload)
    }
    onExited: function(code) { root.finishStore(code) }
  }

  FileView {
    id: jsonWatch
    path: root.filesReady ? root.jsonPath : ""
    preload: false
    watchChanges: true
    blockAllReads: true
    printErrors: false
    onFileChanged: if (!root.ignoreOwnWrite) root.loadFromDisk()
  }

  Component.onDestruction: {
    if (storeProc.running) {
      storeProc.signal(15)
      killTimer.start()
    }
  }
}
