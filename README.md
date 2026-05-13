# Clipboard Relay Skill

`clipboard-relay` is a Codex skill for moving clipboard contents between machines through a shared synced folder.

## What it does

- Sends either plain text or copied files into a relay directory.
- Restores the latest relay item back into the clipboard on another machine.
- Uses a manifest plus item folders so transfers are easy to inspect and troubleshoot.

## Requirements

- PowerShell
- A shared writable folder available on both machines
- `CLIPBOARD_RELAY_DIR` pointing to that folder

## Usage

Use `scripts/clipboard-relay.ps1` with one of two modes:

```powershell
.\scripts\clipboard-relay.ps1 -Mode send
.\scripts\clipboard-relay.ps1 -Mode receive
```

For validation or automation without touching the live clipboard, pass `-NoClipboard` and provide test input:

```powershell
.\scripts\clipboard-relay.ps1 -Mode send -NoClipboard -InputText "hello"
.\scripts\clipboard-relay.ps1 -Mode send -NoClipboard -InputPaths C:\Temp\file.txt
```

## Relay layout

The relay uses this structure:

```text
<relay-root>/
  latest.json
  items/
    <item-id>/
      manifest.json
      payload.txt
      payload.zip
```

Text payloads are stored in `payload.txt`. File clipboard payloads are zipped into `payload.zip`.

## Related files

- [`SKILL.md`](./SKILL.md)
- [`scripts/clipboard-relay.ps1`](./scripts/clipboard-relay.ps1)
- [`references/relay-format.md`](./references/relay-format.md)
