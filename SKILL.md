---
name: clipboard-relay
description: Shared clipboard relay between machines using a synced folder. Use when moving plain text or file clipboard contents between computers, including sending clipboard contents to a relay, restoring the latest relay item, or troubleshooting relay format and clipboard round-trips.
---

# Clipboard Relay

## Overview

Use a shared relay directory as a clipboard handoff point between machines. On the sending machine, package either text or a file-drop clipboard payload into the relay. On the receiving machine, restore the newest relay item back into the clipboard.

Prefer a relay directory that both computers can read and write, such as a OneDrive, Dropbox, Syncthing, or network-share folder. Set `CLIPBOARD_RELAY_DIR` to that path.

## Workflow

1. Decide whether the user wants to send the current clipboard or receive the latest relay item.
2. Confirm the relay directory exists and is shared between the machines.
3. Use `scripts/clipboard-relay.ps1`:
   - `send` captures clipboard text or copied files and writes a relay item.
   - `receive` restores the latest relay item back to the clipboard.
4. For file clipboard contents, zip the copied items before writing them to the relay and unzip them on restore.
5. If the relay is missing or stale, fix the relay directory before trying to transfer again.

## Usage Rules

- Preserve text exactly, including whitespace and newlines.
- Treat file-copy clipboard data as a list of paths, not as text.
- Do not assume the relay is secure unless the underlying synced folder is trusted and encrypted.
- Use the `-NoClipboard` switch in the helper script for validation, testing, or troubleshooting when you do not want to touch the live clipboard.

## Resources

### `scripts/clipboard-relay.ps1`

PowerShell helper that implements the send/receive flow and the relay item format.

### `references/relay-format.md`

Manifest and folder layout for the relay items.
