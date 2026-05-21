# MCP server guide

`aiimageeditor-mcp` speaks Model Context Protocol over stdio (JSON-RPC 2.0,
newline-delimited). Every CLI command is also an MCP tool, plus `render` and
`inspect`.

## Registering with Claude Desktop

Add the following block to your Claude Desktop config
(`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp",
      "args": []
    }
  }
}
```

Restart Claude Desktop. The tools appear with the `aiimageeditor.` prefix.

## Registering with Claude Code

```bash
claude mcp add aiimageeditor /usr/local/bin/aiimageeditor-mcp
```

or edit `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "aiimageeditor": {
      "command": "/usr/local/bin/aiimageeditor-mcp"
    }
  }
}
```

## Protocol

- Transport: stdio, newline-delimited JSON-RPC 2.0.
- The server replies to `initialize` with its protocol version and capabilities.
- `tools/list` enumerates every command in
  [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md) with a JSON-Schema `inputSchema`.
- `tools/call` runs the command. Each tool takes `project` (string, path to
  `.aiproj`) plus the command's own arguments.
- `render` returns both a text summary and the rendered PNG as a base64
  `image` content item so the LLM can see what it produced.

## Statelessness

The server is intentionally stateless: every tool call reads the project from
disk, mutates it, and writes it back. This means the LLM (or you) can edit the
JSON between calls and the server will pick up the change.

## Example session

```
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"demo","version":"0"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}, "serverInfo":{"name":"aiimageeditor","version":"0.1.0"}}}

→ {"jsonrpc":"2.0","id":2,"method":"tools/list"}
← {"jsonrpc":"2.0","id":2,"result":{"tools":[ {"name":"new", ...}, ... ]}}

→ {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"new","arguments":{"project":"/tmp/x.aiproj","preset":"iphone-6.7"}}}
← {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"created /tmp/x.aiproj (1290x2796)"}]}}
```

## Errors

Errors are returned in `result.isError = true` form (per MCP spec) with a
human-readable `text` content item, so the LLM can recover and try again
without aborting the whole call.
