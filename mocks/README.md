# Mock Testing Scripts

This directory contains mock scripts for testing template rendering and webhook delivery without needing to generate real log events from the game.

## Quick Start

```bash
# Run all mocks in dry-run mode (no webhooks sent)
./mocks/run_all_mocks.sh

# Run all mocks and actually send to Discord
./mocks/run_all_mocks.sh --live
```

## Individual Scripts

### mock_plugin_kick.sh
Tests the plugin kick notification template.

```bash
./mocks/mock_plugin_kick.sh --dry-run
./mocks/mock_plugin_kick.sh --driver "Custom Name"
```

### mock_no_slots.sh
Tests the "no available slots" notification template.

```bash
./mocks/mock_no_slots.sh --dry-run
./mocks/mock_no_slots.sh --driver "Another Driver"
```

### mock_session_closed.sh
Tests the session closed notification template.

```bash
./mocks/mock_session_closed.sh --dry-run
```

### mock_checksum_failure.sh
Tests the checksum failure template with various scenarios covering different combinations of optional fields.

```bash
# Available scenarios:
./mocks/mock_checksum_failure.sh --dry-run --scenario minimal    # Only required fields
./mocks/mock_checksum_failure.sh --dry-run --scenario with-url   # With download URL
./mocks/mock_checksum_failure.sh --dry-run --scenario with-dlc   # With DLC pack info
./mocks/mock_checksum_failure.sh --dry-run --scenario with-notes # With notes field
./mocks/mock_checksum_failure.sh --dry-run --scenario notes-html-link     # Notes with a named HTML anchor
./mocks/mock_checksum_failure.sh --dry-run --scenario notes-self-link     # Notes with an HTML anchor whose text is the URL
./mocks/mock_checksum_failure.sh --dry-run --scenario notes-bare-url      # Notes with a bare URL in text
./mocks/mock_checksum_failure.sh --dry-run --scenario notes-multiple-urls # Notes with multiple bare URLs
./mocks/mock_checksum_failure.sh --dry-run --scenario custom-mod # Custom mod with checksum
./mocks/mock_checksum_failure.sh --dry-run --scenario full       # All fields populated
```

## Requirements

- The scripts use `_common.sh` which sources `checksum.env` and `.secrets` from the project root
- `jq` and `curl` must be installed
- A valid webhook URL must be set in `.secrets` for live mode
