const assert = require("node:assert/strict")
const model = require("../Model.js")

assert.deepEqual(model.parseJournal("[]"), [])
assert.equal(model.parseJournal("not-json"), null)
assert.equal(model.nextId([]), "1")
assert.equal(model.nextId([{ id: "2" }, { id: "9" }]), "10")

const first = model.newEntry(new Date("2026-08-19T10:10:00Z"), "1")
assert.equal(first.id, "1")
assert.equal(first.timestamp, "2026-08-19T10:10:00.000Z")
assert.equal(first.content, "")
assert.ok(model.isBlank(first))

const written = { id: "1", timestamp: first.timestamp, content: "Hello journal" }
assert.equal(model.isBlank(written), false)
assert.equal(model.preview(written.content), "Hello journal")
assert.equal(model.preview("   "), "Empty note")

const two = model.upsert([first], written)
assert.equal(two.length, 1)
assert.equal(two[0].content, "Hello journal")
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

console.log("myjournal model tests passed")
