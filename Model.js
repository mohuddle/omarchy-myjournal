// Journal list math. Locale- and Qt-free so tests/model.test.js can run it
// under node. Each entry is { id, timestamp, content, kind, done? }.
// kind is "note" (default) or "todo". done is only stored on todos.

function parseJournal(raw) {
  try {
    var value = JSON.parse(String(raw || "[]"))
    if (Array.isArray(value)) return value.filter(isEntry)
    if (value && Array.isArray(value.entries)) return value.entries.filter(isEntry)
    return []
  } catch (e) {
    return null
  }
}

function isEntry(item) {
  return item && typeof item === "object" && item.id !== undefined && item.id !== null
}

function serializeJournal(entries) {
  return JSON.stringify(Array.isArray(entries) ? entries : [], null, 2) + "\n"
}

function nextId(entries) {
  var max = 0
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    var n = parseInt(String(list[i].id), 10)
    if (isFinite(n) && n > max) max = n
  }
  return String(max + 1)
}

function isoStamp(date) {
  return date.toISOString()
}

function entryKind(entry) {
  return entry && entry.kind === "todo" ? "todo" : "note"
}

function isTodo(entry) {
  return entryKind(entry) === "todo"
}

function newEntry(date, id) {
  return {
    id: String(id || "1"),
    timestamp: isoStamp(date || new Date()),
    content: "",
    kind: "note"
  }
}

function newTodo(date, id) {
  return {
    id: String(id || "1"),
    timestamp: isoStamp(date || new Date()),
    content: "",
    kind: "todo",
    done: false
  }
}

function isBlank(entry) {
  return !entry || String(entry.content || "").trim() === ""
}

function copyEntry(entry) {
  var out = {
    id: String(entry.id),
    timestamp: String(entry.timestamp || ""),
    content: String(entry.content || ""),
    kind: entryKind(entry)
  }
  if (out.kind === "todo") out.done = !!entry.done
  return out
}

function upsert(entries, entry) {
  var list = []
  var found = false
  var incoming = copyEntry(entry)
  var src = entries || []
  for (var i = 0; i < src.length; i++) {
    if (String(src[i].id) === incoming.id) {
      list.push(incoming)
      found = true
    } else list.push(copyEntry(src[i]))
  }
  if (!found) list.push(incoming)
  return list
}

function dropBlanks(entries, keepId) {
  var keep = keepId === undefined || keepId === null ? "" : String(keepId)
  var list = entries || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (isBlank(list[i]) && String(list[i].id) !== keep) continue
    out.push(copyEntry(list[i]))
  }
  return out
}

function findById(entries, id) {
  var wanted = String(id)
  var list = entries || []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].id) === wanted) return copyEntry(list[i])
  }
  return null
}

function toggleDone(entries, id) {
  var found = findById(entries, id)
  if (!found || !isTodo(found)) return entries || []
  found.done = !found.done
  return upsert(entries, found)
}

function preview(content, limit) {
  var text = String(content || "").replace(/\s+/g, " ").trim()
  var max = limit === undefined ? 72 : limit
  if (text === "") return "Empty note"
  if (text.length <= max) return text
  return text.slice(0, max).replace(/\s+$/, "") + "…"
}

function previewEntry(entry, limit) {
  if (isBlank(entry)) return isTodo(entry) ? "Empty todo" : "Empty note"
  return preview(entry.content, limit)
}

function indexMark(entry) {
  if (!isTodo(entry)) return ""
  return entry.done ? "[x] " : "[ ] "
}

function matchesQuery(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return true
  if (!entry) return false
  var hay = String(entry.id).toLowerCase()
    + " " + String(entry.timestamp || "").toLowerCase()
    + " " + String(entry.content || "").toLowerCase()
    + " " + entryKind(entry)
  if (isTodo(entry)) hay += entry.done ? " done" : " open"
  return hay.indexOf(q) >= 0
}

function filterEntries(entries, query) {
  var list = entries || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (matchesQuery(list[i], query)) out.push(copyEntry(list[i]))
  }
  return out
}

function notesTxt(entries) {
  var list = entries || []
  if (list.length === 0) return ""
  var parts = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    var mark = isTodo(e) ? (e.done ? " · todo [x]" : " · todo") : ""
    parts.push("======= " + e.id + " · " + e.timestamp + mark + " =======\n" + String(e.content || "").replace(/\s+$/, "") + "\n")
  }
  return parts.join("\n")
}

function fileUrlToPath(url) {
  var s = String(url || "")
  if (s.indexOf("file://") === 0) {
    s = s.substring(7)
    if (s.charAt(0) !== "/") s = "/" + s
    try { s = decodeURIComponent(s) } catch (e) {}
  }
  return s
}

if (typeof module !== "undefined") {
  module.exports = {
    parseJournal: parseJournal,
    serializeJournal: serializeJournal,
    nextId: nextId,
    isoStamp: isoStamp,
    entryKind: entryKind,
    isTodo: isTodo,
    newEntry: newEntry,
    newTodo: newTodo,
    isBlank: isBlank,
    upsert: upsert,
    dropBlanks: dropBlanks,
    findById: findById,
    toggleDone: toggleDone,
    preview: preview,
    previewEntry: previewEntry,
    indexMark: indexMark,
    matchesQuery: matchesQuery,
    filterEntries: filterEntries,
    notesTxt: notesTxt,
    fileUrlToPath: fileUrlToPath
  }
}
