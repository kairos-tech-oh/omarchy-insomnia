import QtQuick
import Quickshell.Io

// Settings and live session state in one small JSON file, so a shell restart
// resumes an inhibitor that is still within its deadline.
Item {
  id: root
  visible: false

  property string path: ""
  property var values: ({})
  property bool loaded: false

  // A real config is a few hundred bytes; the ceiling stops anything that grows
  // this file from being pulled whole into the long-lived shell process.
  readonly property int capBytes: 65536

  signal changed()

  function str(key, fallback) {
    var v = values ? values[key] : undefined
    return (typeof v === "string" && v !== "") ? v : fallback
  }

  function bool(key, fallback) {
    var v = values ? values[key] : undefined
    return typeof v === "boolean" ? v : fallback
  }

  function num(key, fallback, low, high) {
    var v = values ? values[key] : undefined
    var n = Number(v)
    if (v === undefined || v === null || !isFinite(n)) return fallback
    if (low !== undefined && n < low) return low
    if (high !== undefined && n > high) return high
    return n
  }

  function set(key, value) {
    var next = ({})
    for (var k in values) next[k] = values[k]
    next[key] = value
    values = next
    root.changed()
    save()
  }

  // One write for several keys, so arming a session cannot leave the deadline
  // and the active flag disagreeing on disk.
  function setAll(patch) {
    var next = ({})
    for (var k in values) next[k] = values[k]
    for (var p in patch) next[p] = patch[p]
    values = next
    root.changed()
    save()
  }

  function utf8ByteLength(text) {
    var bytes = 0
    for (var i = 0; i < text.length; i++) {
      var code = text.charCodeAt(i)
      if (code < 0x80) bytes += 1
      else if (code < 0x800) bytes += 2
      else if (code >= 0xd800 && code <= 0xdbff) { bytes += 4; i++ }
      else bytes += 3
    }
    return bytes
  }

  function requestRead() {
    if (String(root.path || "") === "") return
    if (reader.running) return
    reader.running = true
  }

  function parse(content) {
    var text = String(content || "")
    if (utf8ByteLength(text) > root.capBytes) {
      console.warn("insomnia: config over cap, ignoring", root.path)
      finish()
      return
    }
    if (text.replace(/^\s+|\s+$/g, "") === "") { finish(); return }
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        root.values = parsed
        root.changed()
      }
    } catch (error) {
      console.warn("insomnia: unparseable config, keeping defaults", root.path)
    }
    finish()
  }

  function finish() {
    if (!root.loaded) root.loaded = true
  }

  // Read once, bounded, on a descriptor opened with the right flags. Not
  // FileView (no bounded read), not `head` (follows symlinks, blocks on a FIFO).
  Process {
    id: reader
    running: false
    command: ["timeout", "-k", "2", "6", "dd",
              "if=" + root.path,
              "iflag=nofollow,nonblock,fullblock",
              "bs=" + String(root.capBytes + 1),
              "count=1", "status=none"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }

    // No config file is the normal first run, so a failed read is not a warning.
    onExited: function (exitCode) { if (exitCode !== 0) root.finish() }
  }

  // Change notification only; the bounded read above does the loading. Also
  // picks up a hand edit, which is the point of keeping this a plain file.
  FileView {
    path: root.path
    watchChanges: true
    blockAllReads: true
    printErrors: false
    onFileChanged: root.requestRead()
  }

  readonly property string writeScript:
    'p="$1"; d=$(dirname -- "$p")\n' +
    'mkdir -m 700 -p -- "$d" 2>/dev/null || exit 1\n' +
    '[ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] || exit 1\n' +
    't=$(mktemp "$d/.insomnia.XXXXXXXX") || exit 1\n' +
    'chmod 600 -- "$t" || { rm -f -- "$t"; exit 1; }\n' +
    'cat > "$t" || { rm -f -- "$t"; exit 1; }\n' +
    'mv -f -- "$t" "$p" || { rm -f -- "$t"; exit 1; }\n'

  property string payload: ""
  property bool savePending: false

  Process {
    id: writer
    running: false
    command: ["timeout", "-k", "2", "6", "sh", "-c", root.writeScript, "sh", root.path]

    // Re-armed by save() before every run: writing the payload closes the
    // channel so `cat` sees EOF, which leaves the flag false for next time.
    stdinEnabled: false

    onStarted: {
      write(root.payload)
      root.payload = ""
      stdinEnabled = false
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) console.warn("insomnia: config write failed", exitCode)
      if (!root.savePending) return
      root.savePending = false
      // Deferred: the process is still finalising here and `running` would not
      // take a fresh start yet.
      Qt.callLater(root.save)
    }
  }

  // Single-flight with a pending flag, so a change made mid-write is not lost.
  function save() {
    if (String(root.path || "") === "") return
    if (writer.running) { root.savePending = true; return }
    root.payload = JSON.stringify(root.values, null, 2)
    writer.stdinEnabled = true
    writer.running = true
  }

  onPathChanged: root.requestRead()
  Component.onCompleted: root.requestRead()
}
