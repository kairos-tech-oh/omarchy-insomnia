# Insomnia

An Omarchy bar widget that keeps the machine awake and on the network, so a
long-running Claude Code session — or any other agentic session — is still
running when you come back to it.

`󰒲` in the bar means the machine will sleep normally. `󰒳` means Insomnia is
holding it awake, with the remaining time beside it when the session is timed.

- **Left click** toggles the session on and off.
- **Right click** opens the settings popup.

The glyph is green while the inhibitor is actually held and gray when the
machine will sleep normally. It turns the theme's urgent colour, with a `!`
beside it, if logind refused the inhibitor. The switches in the settings popup
follow the same green-on/gray-off palette.

## What it actually does

Three separate things stop an unattended session, and Insomnia addresses them
independently.

### Suspend and idle (always, while enabled)

Insomnia runs

```
systemd-inhibit --what=sleep:idle --who=Insomnia --mode=block sleep infinity
```

for as long as the session is on. That is an ordinary logind block inhibitor
taken as your own user — no privilege escalation, no authentication prompt,
nothing written to system state. It stops a requested suspend, logind's own
idle action, and anything else that asks logind politely before suspending.
Releasing it is just ending the process, which Quickshell does when the
session ends or the shell exits.

You can see it while it is held:

```
systemd-inhibit --list
```

If logind refuses the inhibitor, or it dies while the session is still on,
Insomnia retries with exponential backoff (2s doubling to a 60s ceiling, eight
attempts) rather than staying failed until you toggle it by hand. A refusal is
usually transient — a locked session, or a shell restart mid-flight. The
refusal reason from `systemd-inhibit` is logged, so
`journalctl --user | grep insomnia` says why.

### The lid (optional, off by default)

Turning on **Ignore the lid closing** adds `handle-lid-switch` to the same
inhibitor, so closing a laptop no longer suspends it.

This one is off by default on purpose. A laptop that keeps running with the
lid shut, in a bag, gets hot enough to matter. Use it when the machine is on a
desk, not when it is about to be carried.

### The screen (optional, off by default)

Turning on **Keep the screen on** holds Omarchy's own stay-awake indicator —
the same state `omarchy toggle idle` sets — which suppresses the screensaver
and the idle lock.

Agent sessions do not need this: locking the screen does not stop anything
that is running. It is there for when you want to watch the work happen.

Insomnia takes ownership of that indicator with a random claim id written
into `~/.local/state/omarchy/indicators/stay-awake`, and only ever clears it
again if the claim id still matches. If you had already turned stay-awake on
yourself, Insomnia leaves it entirely alone and says so in the panel.

If the shell is killed while Insomnia holds the indicator, the file survives.
The next time the shell starts, Insomnia either re-adopts it (the session is
still within its deadline) or releases it (the session has expired) — so it
heals itself on the next login. To clear it by hand at any time:

```
omarchy toggle idle
```

### The network (optional, on by default)

Blocking suspend is what actually keeps the link up; nothing else in a normal
Omarchy session takes the interface down. The **gateway keepalive** exists for
the one case that is left: an access point that drops clients it has not heard
from in a while. Every four minutes Insomnia sends a single ICMP echo to the
default gateway.

The panel also reports the Wi-Fi power-save state, read with `iw`. Insomnia
never changes it — that is system configuration, and it belongs in a
NetworkManager drop-in rather than in a bar widget:

```
# /etc/NetworkManager/conf.d/wifi-powersave.conf
[connection]
wifi.powersave = 2
```

## Duration

Sessions are timed by default: 30m, 1h, 2h, 4h, 8h, or no limit. The deadline
is stored as an absolute timestamp, so it survives a shell restart and expires
on schedule either way. Picking a different preset while a session is running
restarts the clock from now, which is what "give me another two hours" means.

## Install

```bash
omarchy plugin add https://github.com/kairos-tech-oh/omarchy-insomnia --enable
omarchy restart shell
```

Then add the widget: **Omarchy menu → Setup → Bar → Widgets → Insomnia**.

## Remove

```bash
omarchy plugin remove kairos.insomnia
rm -f ~/.config/omarchy/kairos-insomnia.json
omarchy restart shell
```

The first line removes the widget and its code. The second deletes the
settings file; leaving it out keeps your preferences for a later reinstall.
Nothing else is written outside the plugin directory except the stay-awake
indicator described above, and only when that option is enabled.

## Dependencies

All of these ship with Omarchy already:

| Command | Used for |
|---|---|
| `systemd-inhibit` | the sleep/idle block inhibitor |
| `omarchy-toggle-idle` | the optional screen hold |
| `ip` | finding the default gateway |
| `ping` | the optional gateway keepalive |
| `iw` | reading Wi-Fi power-save state (optional; reports `unknown` if absent) |

## Files

| Path | Purpose |
|---|---|
| `~/.config/omarchy/kairos-insomnia.json` | settings and the active session's deadline |
| `~/.local/state/omarchy/indicators/stay-awake` | Omarchy's own indicator, only touched when **Keep the screen on** is enabled |

## Notes on the implementation

**One instance does the work.** A bar widget is instantiated once per monitor.
Only the instance on the first screen runs processes; the others are pure UI
reading the same config file. An unresolved screen counts as the first one, so
a wrong guess duplicates the inhibitor rather than dropping it.

**Nothing is read unbounded.** The config file is read once through a
`dd`-bounded, `O_NOFOLLOW` descriptor rather than `FileView` or `head`; helper
output is capped before `JSON.parse` sees it; every subprocess runs under
`timeout`. Values that come back from the helpers are whitelisted to a fixed
alphabet before they reach the bar label or tooltip.

**No privileged runtime actions.** Insomnia never escalates privileges and
never writes outside `$HOME`. The two things that would need root — Wi-Fi
power save and logind's own configuration — it reports rather than changes.
