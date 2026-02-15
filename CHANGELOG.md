# Changelog

## v2.0

### Template system

A complete Go-template-inspired template engine replaces the hardcoded message
format from v1. Every Discord notification can now be customised or translated
by editing plain-text `.tmpl` files.

- Variable substitution (`{{ .driver }}`, `{{ .contentName }}`, etc.)
- Conditional blocks with `if`/`else`, negation (`not`), and value comparison
  (`eq`, `ne`)
- Include directives for shared partials (e.g. `{{ include "_footer.tmpl" }}`)
- Comment blocks (`{{/* ... */}}`)
- Template validation at startup with automatic fallback to legacy format
- Full documentation in TEMPLATES.md

### New detection types

v1 detected only checksum failures. v2 detects and reports seven event types:

| Event | Trigger |
|-------|---------|
| Checksum failure | Mismatched car, track, or required file (apps, plugins) |
| Session closed | Player rejected because the current session is closed |
| No available slots | Player rejected due to locked entry list or driver swap overlap |
| UDP plugin kick | Kicked by a server plugin (e.g. RealPenalty, stracker) |
| High ping kick | Kicked for exceeding the server's ping limit |
| Idle kick | Kicked for idling too long |
| No join list | Rejected because the player was previously kicked this session |

### Required file checksum failures

Checksum failures are now classified by path: `content/cars/` → car,
`content/tracks/` → track, anything else → required file. Required files
display the basename (e.g. `sol_weather.py`) and, when a custom checksum entry
exists, the friendly name (e.g. "Sol").

### DLC and stock content handling

Checksum failure messages now cleanly distinguish between third-party content,
DLC packs, and original game content. DLC pack names are shown when available,
and stock content is identified so users know to verify their game files in
Steam rather than looking for a download.

### Announcement toggles

Each detection type can be individually enabled or disabled in `checksum.env`.
Setting a toggle to `false` still logs the event to the console but skips the
Discord webhook, useful for noisy event types or during testing.

### Configurable log rotation polling

The interval between checks for new session log files is now configurable via
`checkdelay` in `checksum.env` (default: 10 seconds).

### Structured console logging

Every detection is logged with structured fields: server name, trigger type,
driver, GUID, HTTP status, and result (`sent`, `failed`, or `suppressed`).

### Reliability and safety

- All scripts validate required config files, environment variables, and
  dependencies (`jq`, `curl`, `perl`) at startup
- Proper quoting throughout `checksum-manager.sh` and `latest-linker.sh` to
  handle paths with spaces
- Debug-level ACSM log lines are filtered out of the detection pipeline
- `jq` calls guard against null and empty-string values leaking into templates
- Content notes are stripped of HTML and tested for emptiness before display

### Testing

A mock testing framework (`mocks/`) allows template rendering and detection
pattern matching to be exercised locally without a running ACSM server.

### Documentation

- TEMPLATES.md: full syntax reference, variable tables, translation examples
- README.md: updated prerequisites (now includes `perl`) and detection list
- Inline code comments throughout

---

## v1

Initial release. Monitors ACSM multiserver session logs for checksum validation
failures and sends a Discord webhook notification with the driver name, content
name, DLC pack info, download link, and content notes parsed from metadata.
