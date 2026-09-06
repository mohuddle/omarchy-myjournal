const assert = require("node:assert/strict")
const model = require("../Model.js")

assert.deepEqual(model.parseJournal("[]"), [])
assert.equal(model.parseJournal("not-json"), null)
assert.deepEqual(model.parseJournal(""), [])
assert.equal(model.parseJournal(JSON.stringify(Array.from({ length: 401 }, (_, i) => ({ id: String(i + 1), timestamp: "t", content: "x" })))), null)
assert.equal(model.parseJournal(JSON.stringify([{ id: "abc", timestamp: "t", content: "x" }])), null)
assert.equal(model.parseJournal(JSON.stringify([{ id: "1", timestamp: "t", content: "x".repeat(model.MAX_CONTENT + 1) }])), null)
assert.equal(model.nextId([]), "1")
assert.equal(model.nextId([{ id: "2" }, { id: "9" }]), "10")

const first = model.newEntry(new Date("2026-08-19T10:10:00Z"), "1")
assert.equal(first.id, "1")
assert.equal(first.timestamp, "2026-08-19T10:10:00.000Z")
assert.equal(first.content, "")
assert.equal(first.kind, "note")
assert.ok(model.isBlank(first))
assert.equal(model.isTodo(first), false)

const written = { id: "1", timestamp: first.timestamp, content: "Hello journal" }
assert.equal(model.isBlank(written), false)
assert.equal(model.preview(written.content), "Hello journal")
assert.equal(model.preview("   "), "Empty note")
assert.equal(model.entryKind(written), "note")

const two = model.upsert([first], written)
assert.equal(two.length, 1)
assert.equal(two[0].content, "Hello journal")
assert.equal(two[0].kind, "note")
assert.equal("done" in two[0], false)
const three = model.upsert(two, { id: "2", timestamp: "2026-08-20T08:30:00Z", content: "Second" })
assert.equal(three.length, 2)
assert.equal(model.findById(three, "2").content, "Second")

const cleaned = model.dropBlanks([
  written,
  { id: "3", timestamp: "t", content: "  " }
], "4")
assert.equal(cleaned.length, 1)
assert.equal(cleaned[0].id, "1")

const kept = model.dropBlanks([
  { id: "4", timestamp: "t", content: "" }
], "4")
assert.equal(kept.length, 1)

const filtered = model.filterEntries(three, "second")
assert.equal(filtered.length, 1)
assert.equal(filtered[0].id, "2")
assert.equal(model.filterEntries(three, "1").length, 1)

const txt = model.notesTxt(three)
assert.match(txt, /======= 1 ·/)
assert.match(txt, /Hello journal/)
assert.match(txt, /======= 2 ·/)

const roundTrip = model.parseJournal(model.serializeJournal(three))
assert.equal(roundTrip.length, 2)
assert.equal(roundTrip[1].id, "2")

const todo = model.newTodo(new Date("2026-08-27T12:00:00Z"), "5")
assert.equal(todo.kind, "todo")
assert.equal(todo.done, false)
assert.ok(model.isTodo(todo))
assert.ok(model.isBlank(todo))
assert.equal(model.previewEntry(todo), "Empty todo")
assert.equal(model.indexMark(todo), "[ ] ")

const withTodo = model.upsert(three, Object.assign({}, todo, { content: "Buy milk" }))
assert.equal(withTodo.length, 3)
assert.equal(model.previewEntry(model.findById(withTodo, "5")), "Buy milk")
assert.equal(model.filterEntries(withTodo, "todo").length, 1)
assert.equal(model.filterEntries(withTodo, "milk").length, 1)

const checked = model.toggleDone(withTodo, "5")
assert.equal(model.findById(checked, "5").done, true)
assert.equal(model.indexMark(model.findById(checked, "5")), "[x] ")
assert.equal(model.filterEntries(checked, "done").length, 1)
assert.equal(model.toggleDone(checked, "1").find(function(e) { return e.id === "1" }).kind, "note")

const todoTxt = model.notesTxt(checked)
assert.match(todoTxt, /======= 5 · .* · todo \[x\] =======/)
assert.match(todoTxt, /Buy milk/)
const serializedTodo = JSON.parse(model.serializeJournal(checked)).find(function(e) { return e.id === "5" })
assert.equal(serializedTodo.kind, "todo")
assert.equal(serializedTodo.done, true)

const parsedOld = model.parseJournal(JSON.stringify([{ id: "9", timestamp: "t", content: "legacy" }]))
assert.equal(parsedOld.length, 1)
assert.equal(model.entryKind(parsedOld[0]), "note")
assert.equal(model.isTodo(parsedOld[0]), false)

const droppedTodo = model.dropBlanks([
  { id: "5", timestamp: "t", content: "", kind: "todo", done: false },
  { id: "1", timestamp: "t", content: "keep" }
], "")
assert.equal(droppedTodo.length, 1)
assert.equal(droppedTodo[0].id, "1")

console.log("myjournal model tests passed")
