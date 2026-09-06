// Journal list math. Locale- and Qt-free so tests/model.test.js can run it
// under node. Each entry is { id, timestamp, content, kind, done? }.
// kind is "note" (default) or "todo". done is only stored on todos.

var MAX_ENTRIES = 400
var MAX_CONTENT = 16384
var MAX_SEARCH = 200
var MAX_ID = 16
var MAX_TIMESTAMP = 40
var MAX_BYTES = 262144
var ID_RE = /^[0-9]{1,16}$/

function clipContent(text) {
  var s = String(text || "")
  return s.length <= MAX_CONTENT ? s : s.substring(0, MAX_CONTENT)
}

function parseJournal(raw) {
  var source = String(raw || "")
  if (source.length > MAX_BYTES) return null
  var trimmed = source.replace(/^\s+|\s+$/g, "")
  if (trimmed === "") return []
  try {
    var value = JSON.parse(trimmed)
    var rows
    if (Array.isArray(value)) rows = value
    else if (value && Array.isArray(value.entries)) rows = value.entries
    else return null
    if (rows.length > MAX_ENTRIES) return null
    var out = []
    for (var i = 0; i < rows.length; i++) {
      if (!isEntry(rows[i])) return null
      out.push(copyEntry(rows[i]))
    }
    return out
  } catch (e) {
    return null
  }
}

function isEntry(item) {
  if (!item || typeof item !== "object") return false
  var ident = String(item.id)
  if (!ID_RE.test(ident)) return false
  if (String(item.timestamp || "").length > MAX_TIMESTAMP) return false
  if (String(item.content || "").length > MAX_CONTENT) return false
  if (item.kind !== undefined && item.kind !== "note" && item.kind !== "todo") return false
  if (item.done !== undefined && typeof item.done !== "boolean") return false
  return true
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
    content: clipContent(entry.content),
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
  var q = String(query || "")
  if (q.length > MAX_SEARCH) q = q.substring(0, MAX_SEARCH)
  q = q.trim().toLowerCase()
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
    MAX_ENTRIES: MAX_ENTRIES,
    MAX_CONTENT: MAX_CONTENT,
    MAX_SEARCH: MAX_SEARCH,
    MAX_BYTES: MAX_BYTES,
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
    clipContent: clipContent,
    fileUrlToPath: fileUrlToPath
  }
}
