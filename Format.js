.pragma library

// Strings this plugin hands to the bar label and tooltip are rendered by Text
// elements inside omarchy-shell, so they are sanitised on the way out.
function barSafe(value, maxLength) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/[\x00-\x1f\x7f]/g, " ")
  text = text.replace(/[<>&]/g, "")
  text = text.replace(/\s+/g, " ")
  text = text.replace(/^\s+|\s+$/g, "")
  var limit = maxLength > 0 ? maxLength : 200
  return text.length > limit ? text.substring(0, limit - 1) + "…" : text
}

// Whitelist for values read back out of the probe helper before they reach the
// panel, so a surprising interface name cannot become markup.
function whitelist(value, maxLength) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/[^A-Za-z0-9._:-]/g, "")
  var limit = maxLength > 0 ? maxLength : 32
  return text.substring(0, limit)
}

// Compact remaining-time label: "4h 05m" down to "12s" in the last minute.
function remaining(ms) {
  var total = Math.max(0, Math.floor(Number(ms) / 1000))
  if (!isFinite(total)) return ""
  if (total < 60) return total + "s"
  var minutes = Math.floor(total / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  return hours + "h " + (rest < 10 ? "0" : "") + rest + "m"
}

// Presets the panel offers. Zero means no deadline at all.
function durationOptions() {
  return [
    { "value": "30m", "label": "30m", "ms": 30 * 60000 },
    { "value": "1h", "label": "1h", "ms": 60 * 60000 },
    { "value": "2h", "label": "2h", "ms": 120 * 60000 },
    { "value": "4h", "label": "4h", "ms": 240 * 60000 },
    { "value": "8h", "label": "8h", "ms": 480 * 60000 },
    { "value": "forever", "label": "No limit", "ms": 0 }
  ]
}

function durationMs(value) {
  var options = durationOptions()
  for (var i = 0; i < options.length; i++)
    if (options[i].value === String(value)) return options[i].ms
  return 60 * 60000
}

function isDuration(value) {
  var options = durationOptions()
  for (var i = 0; i < options.length; i++)
    if (options[i].value === String(value)) return true
  return false
}
