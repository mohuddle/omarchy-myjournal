// Journal list math. Locale- and Qt-free so tests/model.test.js can run it
// under node. Each entry is { id, timestamp, content }.

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

function newEntry(date, id) {
  return {
    id: String(id || "1"),
    timestamp: isoStamp(date || new Date()),
    content: ""
  }
}

function isBlank(entry) {
  return !entry || String(entry.content || "").trim() === ""
}

function copyEntry(entry) {
  return {
    id: String(entry.id),
    timestamp: String(entry.timestamp || ""),
    content: String(entry.content || "")
  }
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

function preview(content, limit) {
  var text = String(content || "").replace(/\s+/g, " ").trim()
  var max = limit === undefined ? 72 : limit
  if (text === "") return "Empty note"
  if (text.length <= max) return text
  return text.slice(0, max).replace(/\s+$/, "") + "…"
}

function matchesQuery(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return true
  if (!entry) return false
  return String(entry.id).toLowerCase().indexOf(q) >= 0
    || String(entry.timestamp || "").toLowerCase().indexOf(q) >= 0
    || String(entry.content || "").toLowerCase().indexOf(q) >= 0
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
    parts.push("======= " + e.id + " · " + e.timestamp + " =======\n" + String(e.content || "").replace(/\s+$/, "") + "\n")
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
    newEntry: newEntry,
    isBlank: isBlank,
    upsert: upsert,
    dropBlanks: dropBlanks,
    findById: findById,
    preview: preview,
    matchesQuery: matchesQuery,
    filterEntries: filterEntries,
    notesTxt: notesTxt,
    fileUrlToPath: fileUrlToPath
  }
}
