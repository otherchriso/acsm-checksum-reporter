# PRD: Templated Output System

## Overview

Replace the current `message_prefix` / `message_suffix` variable system with a flexible templating system that allows administrators to fully customise Discord notification messages, including support for localisation and conditional content.

## Problem Statement

The current implementation hardcodes message structure in bash, with only prefix/suffix customisation. This creates several limitations:

1. **Localisation** - Administrators cannot translate messages to their community's language
2. **Customisation** - Message format and content cannot be tailored to community preferences
3. **Rigidity** - Adding new variables requires code changes
4. **Maintenance** - Message text is scattered across multiple bash functions

## Goals

1. Enable full message customisation without code changes
2. Support multi-language deployments
3. Provide access to all parsed log data as template variables
4. Allow conditional content based on variable presence/values
5. Keep implementation simple and maintainable in bash

## Non-Goals

- Complex template inheritance or partials
- External template engine dependencies
- Real-time template reloading (restart acceptable)

---

## Proposed Solution

### Templating Syntax

**Recommendation: Go-style templates (subset)**

Rationale:
- Familiar syntax from Docker, Kubernetes, Helm, Hugo
- Simple to parse with sed/awk in bash
- Clear distinction between variables `{{ .var }}` and conditionals `{{ if ... }}`
- Well-documented syntax that administrators may already know

Alternative considered: Mustache (`{{var}}`, `{{#var}}...{{/var}}`)
- Simpler but less intuitive conditional syntax
- Less widespread in DevOps tooling

### Template Files

Templates stored in a `templates/` directory:

```
templates/
├── checksum_failure.tmpl
├── session_closed.tmpl
├── no_slots.tmpl
├── plugin_kick.tmpl
└── _common.tmpl          # shared snippets (optional, phase 2)
```

### Variable Syntax

```
{{ .variableName }}
```

Variables are case-sensitive and prefixed with `.` to denote template scope.

### Available Variables

#### Global Variables (all templates)

| Variable | Description | Example |
|----------|-------------|---------|
| `{{ .driver }}` | Driver name | `John Smith` |
| `{{ .timestamp }}` | Event timestamp | `2026-01-18T10:09:50Z` |
| `{{ .serverName }}` | Server identifier (from log path) | `server1` |

#### Checksum Failure Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{{ .contentType }}` | `car` or `track` | `car` |
| `{{ .contentName }}` | Content folder name | `f1c75_tyrrell_p34` |
| `{{ .failedFile }}` | **NEW** Full path of mismatched file | `content/cars/f1c75_tyrrell_p34/data.acd` |
| `{{ .expectedChecksum }}` | **NEW** Server's expected MD5 from metadata | `a1b2c3d4e5f6...` |
| `{{ .customName }}` | **NEW** Friendly name for custom checksums | `Helicorsa` |
| `{{ .downloadURL }}` | From content metadata | `https://example.com/mod.zip` |
| `{{ .dlcPack }}` | DLC pack name if applicable | `Japanese Pack` |
| `{{ .notes }}` | Content notes (HTML stripped) | `Download v2.1 from...` |

#### Session/Slot Rejection Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{{ .steamID }}` | Driver's SteamID64 | `76561198012345678` |
| `{{ .reason }}` | Rejection reason | `session closed` |

### Conditional Syntax

#### If variable exists (non-empty)

```
{{ if .downloadURL }}
**Download:** {{ .downloadURL }}
{{ end }}
```

#### If variable equals value

```
{{ if eq .contentType "car" }}
This is a car mod.
{{ end }}
```

#### If variable is empty

```
{{ if not .downloadURL }}
No download link available.
{{ end }}
```

#### If/else

```
{{ if .dlcPack }}
Available in the **{{ .dlcPack }}** DLC.
{{ else }}
This is third-party content.
{{ end }}
```

### Example Template

**`templates/checksum_failure.tmpl`**

```
:warning: **Checksum Mismatch Detected**

**Driver:** {{ .driver }}
{{ if .contentName }}
**Content:** {{ .contentType }} - **{{ .contentName }}**
{{ end }}
{{ if .customName }}
**Required mod:** {{ .customName }}
{{ end }}
{{ if .failedFile }}
**File:** `{{ .failedFile }}`
{{ if .expectedChecksum }}
**Expected checksum:** `{{ .expectedChecksum }}`
{{ end }}
{{ end }}
{{ if .downloadURL }}

:arrow_down: **Download:** <{{ .downloadURL }}>
{{ else }}
We don't have a download link. If this is stock/DLC content, verify your game files in Steam.
{{ end }}
{{ if .dlcPack }}

:package: {{ .contentName }} is available with the **{{ .dlcPack }}** DLC.
{{ end }}
{{ if .notes }}

:memo: **Notes:**
{{ .notes }}
{{ end }}
```

---

## Implementation Phases

### Phase 1: Core Templating ✅ COMPLETE

1. ✅ Create `templates/` directory with default templates
2. ✅ Implement `render_template()` function in bash
   - Load template file
   - Substitute `{{ .var }}` with values
   - Process `{{ if .var }}...{{ end }}` blocks
   - Process `{{ if not .var }}...{{ end }}` blocks
3. ✅ Migrate all `prepare_*_message()` functions to use templates
4. ✅ Deprecate `message_prefix` / `message_suffix` (keep as fallback initially)

### Phase 2: Extended Variables

1. Parse `failedFile` from checksum warning log line
2. Implement `expectedChecksum` lookup from content metadata
   - Read `.checksums` array from `ui_car.json` or `meta_data.json`
   - Match `filepath` against `failedFile`
   - Return corresponding `checksum` value
   - Handle missing entries gracefully (empty string)
3. Implement custom checksum lookup for non-content files
   - Add `acsm_config_path` to `checksum.env` (path to ACSM's config.yml)
   - Parse `shared_data_path:` from config.yml (or default to `shared_store.json/`)
   - Look up `failedFile` in `custom_checksums.json`
4. Expose `{{ .customName }}` variable for custom checksums (e.g. "Helicorsa", "Custom Shaders Patch")

### Phase 3: Advanced Conditionals

1. Implement `{{ if eq .var "value" }}` syntax
2. Implement `{{ if else }}` blocks
3. Consider `{{ if ne .var "value" }}` (not equals)

### Phase 4: Enhancements (Optional)

1. Template validation on startup
2. Include/partial support (`{{ include "_footer.tmpl" }}`)
3. Variable escaping for special characters

---

## Technical Considerations

### Bash Implementation

The template engine can be implemented with sed/awk:

```bash
render_template() {
  local template_file="${1}"
  local template=$(cat "${template_file}")
  
  # Variable substitution
  template=$(echo "${template}" | sed "s/{{ \.driver }}/${driver}/g")
  # ... etc
  
  # Conditional blocks (simplified)
  # Remove {{ if .var }}...{{ end }} blocks where var is empty
  # Keep content between {{ if .var }}...{{ end }} where var is set
  
  echo "${template}"
}
```

### Performance

- Templates loaded once per event (acceptable)
- Checksum lookup via jq is lightweight (JSON already loaded for other variables)
- Consider caching parsed template structure if performance becomes an issue

### Error Handling

- Missing template file: fall back to hardcoded message, log warning
- Invalid template syntax: log error, use raw template text
- Missing variable: substitute empty string, optionally log debug message

### Backwards Compatibility

- If `templates/` directory doesn't exist, use legacy prefix/suffix behaviour
- Provide migration script or first-run template generation
- Document migration path in README

---

## Decisions

1. **Template file format**: `.tmpl`
2. **Default templates**: Ship with English defaults matching current hardcoded messages - 100% backwards-compatible
3. **Variable naming**: camelCase with dot prefix: `{{ .contentName }}`
4. **Emoji support**: Include Discord emoji (`:warning:`, `:arrow_down:`, etc.) in default templates

---

## Configuration Changes

New variables required in `checksum.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `acsm_config_path` | Path to ACSM's config.yml | `/opt/acsm/server/config.yml` |
| `templates_path` | Path to templates directory | `./templates` |

---

## Technical Notes

### Checksum Lookup

The expected checksum for a failed file can come from two sources:

#### 1. Content Metadata (cars/tracks)

For files under `content/cars/` or `content/tracks/`, checksums are in the content's metadata JSON:

```bash
# Example: ui_car.json contains .checksums array
jq '.checksums[] | select(.filepath == "content/cars/wsc_legends_gt40_mk2/collider.kn5") | .checksum' ui_car.json
# Returns: "4ad5882f66101717f1b58addc2b2337e"
```

Metadata file locations:
- Cars: `${contentpath}cars/${contentname}/ui/ui_car.json`
- Tracks: `${contentpath}tracks/${contentname}/ui/meta_data.json`

#### 2. Custom Checksums (apps, dlls, etc.)

For arbitrary files (apps, CSP, Sol, etc.), checksums are stored in ACSM's shared store:

```bash
# Default location (multiserver mode)
cat /opt/acsm/server/shared_store.json/custom_checksums.json
```

```json
{
  "entries": [
    {
      "id": "b0f195db-730c-4219-b9af-665eb18744f0",
      "name": "Helicorsa",
      "filepath": "apps/python/helicorsa/helicorsa.py",
      "checksum": "7dcdbc82db96a5450def733ac34263ef"
    },
    {
      "id": "5c1c6497-021c-4f40-b493-bcc995ac1dd5",
      "name": "Custom Shaders Patch",
      "filepath": "dwrite.dll",
      "checksum": ""
    }
  ]
}
```

**Path resolution for custom checksums:**

The shared store path may be overridden in ACSM's `config.yml`:

```yaml
store:
  type: boltdb
  path: server_manager.db
  shared_data_path:    # If empty, defaults to shared_store.json/
```

Lookup order:
1. Check `config.yml` for `shared_data_path:` value
2. If set, use `${shared_data_path}/custom_checksums.json`
3. If empty/absent, use `shared_store.json/custom_checksums.json`

**Checksum lookup logic:**

```bash
lookup_expected_checksum() {
  local failed_file="${1}"
  
  # Content checksums (cars/tracks)
  if [[ "${failed_file}" =~ ^content/(cars|tracks)/ ]]; then
    # Look up in ui_car.json or meta_data.json .checksums array
    jq -r --arg fp "${failed_file}" '.checksums[] | select(.filepath == $fp) | .checksum' "${hintfile}"
  else
    # Custom checksums (apps, dlls, etc.)
    local custom_checksums_path=$(resolve_shared_store_path)/custom_checksums.json
    if [[ -f "${custom_checksums_path}" ]]; then
      jq -r --arg fp "${failed_file}" '.entries[] | select(.filepath == $fp) | .checksum' "${custom_checksums_path}"
    fi
  fi
}
```

---

## Success Criteria

1. Administrators can translate all message text without modifying bash scripts
2. New variables can be added by editing only the relevant `prepare_*` function
3. Conditional content works correctly for all documented scenarios
4. Performance impact is negligible (< 100ms per message)
5. Existing deployments continue working without immediate changes

---

## References

- [Go text/template documentation](https://pkg.go.dev/text/template)
- [Mustache specification](https://mustache.github.io/mustache.5.html)
- Current implementation: `checker.sh` lines 73-250
