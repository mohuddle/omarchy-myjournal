import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// In-memory journal. Plain JSON + notes.txt until a passphrase is set;
// then the whole list is rewritten as an age-encrypted file at rest.
Item {
  id: root
  property var settings: ({})
  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string storeDir: home + "/.local/state/omarchy/myjournal/"
  readonly property string jsonPath: storeDir + "journal.json"
  readonly property string txtPath: storeDir + "notes.txt"
  readonly property string agePath: storeDir + "journal.json.age"
  readonly property string tempPath: runtimeDir + "/omarchy-myjournal.json"
  readonly property string helperPath: Model.fileUrlToPath(Qt.resolvedUrl("scripts/age-crypt.py"))

  property var entries: []
  property string currentId: ""
  property string passphrase: ""
  property bool unlocked: false
  property bool encryptedOnDisk: false
  property bool filesReady: false
  property bool saving: false
  property bool saveQueued: false
  property bool loading: false
  property bool writingOwn: false
  property bool pendingOpen: false
  property bool pendingLock: false
  property string cryptPass: ""
  property string lastError: ""
  property string statusText: "My Journal"

  readonly property var currentEntry: Model.findById(entries, currentId)
  readonly property bool locked: encryptedOnDisk && !unlocked
  readonly property bool canEdit: unlocked && !locked
  readonly property int entryCount: entries.length

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function currentContent() {
    return currentEntry ? String(currentEntry.content || "") : ""
  }

  function begin() {
    pendingOpen = true
    if (!filesReady) {
      ensureDir.running = true
      return
    }
    if (locked) return
    if (!unlocked) {
      loadPlain()
      return
    }
    startNewNote()
  }

  function startNewNote() {
    if (!unlocked) return
    entries = Model.dropBlanks(entries, currentId)
    var current = Model.findById(entries, currentId)
    if (current && Model.isBlank(current)) return
    var entry = Model.newEntry(new Date(), Model.nextId(entries))
    entries = Model.upsert(entries, entry)
    currentId = entry.id
    scheduleSave()
  }

  function openEntry(id) {
    if (!unlocked) return
    entries = Model.dropBlanks(entries, id)
    var found = Model.findById(entries, id)
    if (!found) return
    currentId = found.id
  }

  function setContent(text) {
    if (!unlocked || currentId === "") return
    var entry = Model.findById(entries, currentId)
    if (!entry) return
    entry.content = String(text || "")
    entries = Model.upsert(entries, entry)
    scheduleSave()
  }

  function unlock(secret) {
    var pass = String(secret || "")
    if (pass === "") {
      lastError = "Enter the journal passphrase."
      return
    }
    if (cryptProc.running) return
    loading = true
    lastError = ""
    passphrase = pass
    cryptProc.mode = "decrypt"
    cryptProc.secret = pass
    cryptProc.command = ["python3", helperPath, "decrypt", agePath]
    cryptProc.running = true
  }

  function enableEncryption(secret, confirm) {
    var pass = String(secret || "")
    if (pass === "" || pass !== String(confirm || "")) {
      lastError = "Passphrase and confirmation did not match."
      return
    }
    passphrase = pass
    unlocked = true
    encryptedOnDisk = true
    lastError = ""
    saveNow()
  }

  function disableEncryption() {
    passphrase = ""
    encryptedOnDisk = false
    lastError = ""
    saveNow()
  }

  function finishLock() {
    passphrase = ""
    cryptPass = ""
    entries = []
    currentId = ""
    unlocked = false
    pendingLock = false
    lastError = ""
    statusText = encryptedOnDisk ? "Locked" : "My Journal"
  }

  function lock() {
    flushBlank()
    if (unlocked && passphrase !== "") {
      pendingLock = true
      saveNow()
      return
    }
    finishLock()
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
    if (!unlocked) return
    if (cryptProc.running || encryptDelay.running) {
      saveQueued = true
      return
    }
    var list = Model.dropBlanks(entries, "")
    var payload = Model.serializeJournal(list)
    saving = true
    if (passphrase !== "") {
      cryptPass = passphrase
      writingOwn = true
      tempFile.setText(payload)
      encryptDelay.start()
      return
    }
    writingOwn = true
    jsonFile.setText(payload)
    txtFile.setText(Model.notesTxt(list))
    rmAge.running = true
  }

  function loadPlain() {
    jsonFile.reload()
  }

  function applyLoaded(raw) {
    var parsed = Model.parseJournal(raw)
    if (parsed === null) {
      lastError = "Couldn’t parse the journal file."
      unlocked = false
      loading = false
      return
    }
    entries = parsed
    unlocked = true
    lastError = ""
    loading = false
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
      ageCheck.running = true
    }
  }

  Process {
    id: ageCheck
    command: ["test", "-f", root.agePath]
    onExited: function(code) {
      root.encryptedOnDisk = code === 0
      root.filesReady = true
      if (root.encryptedOnDisk) {
        root.unlocked = false
        root.statusText = "Locked"
      } else jsonFile.reload()
    }
  }

  Timer {
    id: encryptDelay
    interval: 40
    repeat: false
    onTriggered: {
      if (root.cryptPass === "") {
        root.saving = false
        root.lastError = "No passphrase to encrypt with."
        if (root.pendingLock) root.finishLock()
        return
      }
      cryptProc.mode = "encrypt"
      cryptProc.secret = root.cryptPass
      cryptProc.command = ["python3", root.helperPath, "encrypt", root.tempPath, root.agePath]
      cryptProc.running = true
    }
  }

  Process {
    id: cryptProc
    property string mode: ""
    property string secret: ""
    stdinEnabled: true
    stdout: StdioCollector { id: cryptOut; waitForEnd: true }
    stderr: StdioCollector { id: cryptErr; waitForEnd: true }
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    onExited: function(code) {
      root.loading = false
      root.saving = false
      if (cryptProc.mode === "decrypt") {
        if (code !== 0) {
          root.passphrase = ""
          root.unlocked = false
          root.lastError = "Incorrect passphrase."
          return
        }
        root.applyLoaded(cryptOut.text)
        return
      }
      if (code !== 0) {
        root.lastError = "Couldn’t encrypt the journal with age."
        return
      }
      root.encryptedOnDisk = true
      root.lastError = ""
      rmPlain.running = true
      if (root.pendingLock) root.finishLock()
    }
  }

  Process {
    id: rmPlain
    command: ["rm", "-f", root.jsonPath, root.txtPath, root.tempPath]
    onExited: function() {
      if (root.saveQueued) { root.saveQueued = false; root.saveNow() }
    }
  }

  Process {
    id: rmAge
    command: ["rm", "-f", root.agePath, root.tempPath]
    onExited: function() {
      root.saving = false
      root.encryptedOnDisk = false
      root.lastError = ""
      if (root.saveQueued) { root.saveQueued = false; root.saveNow() }
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
      if (root.encryptedOnDisk) return
      root.applyLoaded(text())
    }
    onLoadFailed: {
      if (root.encryptedOnDisk) return
      root.entries = []
      root.unlocked = true
      root.lastError = ""
      if (root.pendingOpen) root.startNewNote()
    }
  }

  property FileView txtFile: FileView {
    path: root.txtPath
    atomicWrites: true
    printErrors: false
  }

  property FileView tempFile: FileView {
    path: root.tempPath
    atomicWrites: true
    printErrors: false
  }

  Component.onCompleted: ensureDir.running = true
}
