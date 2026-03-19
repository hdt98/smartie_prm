# SMARTIE OpenViking Plugin

OpenCode plugin for enterprise document search via OpenViking.

## Features

- `memsearch` - Search across enterprise documents
- `memread` - Read full document content
- `membrowse` - Browse document structure

## Build

```bash
cd openviking/plugin
bun install
bun run build
```

## Configuration

Edit `openviking-config.json`:

```json
{
  "endpoint": "http://localhost:1934",
  "apiKey": "your-openviking-api-key",
  "enabled": true,
  "timeoutMs": 30000
}
```

## Usage

Once built, reference in `opencode.json`:

```json
{
  "plugins": {
    "smartie-openviking": {
      "command": "node",
      "args": ["./openviking/plugin/dist/openviking-plugin.js"]
    }
  }
}
```
