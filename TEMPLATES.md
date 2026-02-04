# Message Templates

Discord notification messages are fully customisable using template files in the `templates/` directory. This allows you to translate messages, adjust formatting, or tailor content to your community's needs—all without modifying the scripts.

## Syntax Overview

Templates use a simple syntax inspired by Go templates. There are three main concepts:

### 1. Variables

Insert dynamic values using `{{ .variableName }}`:

```
Checksum failed for **{{ .driver }}** on {{ .contentType }} **{{ .contentName }}**
```

Variables are replaced with actual values when the message is sent. If a variable has no value, it becomes empty text.

### 2. Conditionals

Show content only when a variable has a value:

```
{{ if .downloadURL }}
:arrow_down: **Download:** <{{ .downloadURL }}>
{{ end }}
```

The content between `{{ if .variableName }}` and `{{ end }}` only appears if the variable is set.

#### If/Else

Provide alternative content when a variable is empty:

```
{{ if .downloadURL }}
:arrow_down: <{{ .downloadURL }}>
{{ else }}
No download link available.
{{ end }}
```

#### Negation

Show content only when a variable is **not** set:

```
{{ if not .dlcPack }}
This is third-party content.
{{ end }}
```

#### Value Comparison

Check if a variable equals a specific value:

```
{{ if eq .contentType "car" }}
This is a car mod.
{{ end }}

{{ if ne .contentType "track" }}
This is not a track.
{{ end }}
```

- `eq` = equals
- `ne` = not equals

### 3. Includes

Embed another template file:

```
{{ include "_footer.tmpl" }}
```

Useful for shared content like footers or disclaimers. By convention, partial templates are prefixed with `_`.

## Template Files

| File | Event | Key Variables |
|------|-------|---------------|
| `checksum_failure.tmpl` | Player kicked for checksum mismatch | `driver`, `contentType`, `contentName`, `failedFile`, `expectedChecksum`, `customName`, `downloadURL`, `dlcPack`, `notes` |
| `session_closed.tmpl` | Player rejected (session closed) | `driver` |
| `no_slots.tmpl` | Player rejected (no available slots) | `driver` |
| `plugin_kick.tmpl` | Player kicked by UDP plugin | `driver` |
| `_footer.tmpl` | Shared partial (example) | — |

## Available Variables

### All Templates

| Variable | Description |
|----------|-------------|
| `{{ .driver }}` | Driver name |

### Checksum Failure Only

| Variable | Description |
|----------|-------------|
| `{{ .contentType }}` | `car` or `track` |
| `{{ .contentName }}` | Content folder name (e.g. `ks_ferrari_488_gt3`) |
| `{{ .failedFile }}` | Full path of the mismatched file |
| `{{ .expectedChecksum }}` | Server's expected MD5 checksum |
| `{{ .customName }}` | Friendly name for custom checksum entries (e.g. "Helicorsa") |
| `{{ .downloadURL }}` | Download link from content metadata |
| `{{ .dlcPack }}` | DLC pack name (if applicable) |
| `{{ .notes }}` | Content notes from metadata (HTML stripped) |

## Example: Translating to German

Create or edit `templates/checksum_failure.tmpl`:

```
:warning: **Prüfsummenfehler erkannt**

**{{ .driver }}** wurde wegen einer Prüfsummendiskrepanz gekickt.
**Inhalt:** {{ .contentType }} - {{ .contentName }}
{{ if .downloadURL }}

:arrow_down: **Download:** <{{ .downloadURL }}>
{{ else }}

Wir haben keinen Download-Link. Falls es sich um Standard- oder DLC-Inhalte handelt, überprüfe deine Spieldateien in Steam.
{{ end }}
```

## Validation

Templates are validated when `checker.sh` starts. Errors are logged but won't prevent the script from running—it will fall back to a basic message format if a template fails.

Validation checks for:
- Unbalanced `{{ }}` braces
- Mismatched `{{ if }}` / `{{ end }}` blocks
- Missing include files

## Legacy Mode

If the `templates/` directory doesn't exist, the system falls back to a basic hardcoded message format. This ensures the script continues to function even without templates, though you'll lose customisation capabilities.

---

## Tip: Using Custom Discord Emojis

You can use custom emojis uploaded to your Discord server in templates. The syntax is:

```
<:emoji_name:emoji_id>
```

To find the emoji ID, type `\:my_custom_emoji:` in any Discord channel (with the backslash). Discord will display the full reference like `<:my_custom_emoji:1017269073622601729>`.

Use that exact string in your template:

```
<:my_custom_emoji:1234567890123456789> **Checksum Mismatch Detected**
```

This only works for emojis the webhook has access to—typically those uploaded to the same server the webhook posts to.
