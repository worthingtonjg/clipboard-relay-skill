# Relay Format

`clipboard-relay` uses a shared directory as the transport.

## Directory layout

```text
<relay-root>/
  latest.json
  items/
    <item-id>/
      manifest.json
      payload.txt
      payload.zip
```

Only one of `payload.txt` or `payload.zip` is present for a given item.

## Manifest fields

```json
{
  "version": 1,
  "id": "20260513T135200123Z-abc123",
  "createdUtc": "2026-05-13T13:52:00.123Z",
  "type": "text",
  "payloadFile": "payload.txt",
  "sourceMachine": "DESKTOP-1234"
}
```

`type` is one of:

- `text`
- `files`

For `files`, the payload is a zip archive containing the copied file or folder tree.

## Behavior

- `send` writes the item folder first, then updates `latest.json` last.
- `receive` reads `latest.json` and restores that item.
- `-NoClipboard` avoids touching the clipboard and returns structured output for validation or automation.
