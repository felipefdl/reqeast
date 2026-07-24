# Reqeast MCP Server

Connect your AI tools directly to Reqeast. The MCP server lets AI assistants inspect your API requests, responses, and session history without manual copy-pasting.

## What It Does

When you're debugging an API request in Reqeast, instead of copying URLs, headers, and response bodies into your AI tool, the MCP server gives the AI direct read-only access to:

- The request you're currently working on (method, URL, headers, body, auth type, settings)
- The full response (status, headers, body, timing breakdown, certificate, redirect chain)
- Your recent request history (last 10 executions across all projects)
- Your project and environment configuration (secrets redacted)
- The cookie jar

The AI sees your full debugging context in one call.

## How It Works

Reqeast exports session data snapshots to disk as you work. The MCP server reads those files when your AI tool requests information. Everything stays local. No data leaves your machine.

```
Reqeast App  -->  writes session data to disk  -->  MCP Server reads it
                                                         |
                                            AI Tool (Claude, Cursor, etc.)
```

## Setup

### 1. Install

```bash
npm install -g reqeast-mcp
```

### 2. Enable MCP Export in Reqeast

Open Reqeast, go to Settings > General, and make sure "Enable MCP Export" is turned on (enabled by default).

### 3. Configure your AI tool

**Claude Code** (add to `~/.claude.json` or project-level config):

```json
{
  "mcpServers": {
    "reqeast": {
      "command": "npx",
      "args": ["-y", "reqeast-mcp"]
    }
  }
}
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "reqeast": {
      "command": "npx",
      "args": ["-y", "reqeast-mcp"]
    }
  }
}
```

**Cursor**: Settings > MCP Servers > Add server with command `npx` and args `["-y", "reqeast-mcp"]`.

Other MCP-compatible tools (VS Code, Windsurf, Zed) follow similar patterns.

### 4. Use it

Open Reqeast, work with your requests as usual, then ask your AI tool:

- "Check my active request in Reqeast, something's off"
- "What was the response from my last API call?"
- "Compare my last few requests, when did it start failing?"
- "What cookies does Reqeast have stored?"

## Available Tools

8 read-only tools:

### get_active_context

Returns the currently selected project and request, plus a summary of recent executions. This is the main entry point -- your AI tool calls this first to understand what you're working on.

**Returns**: Selected project, selected request config, recent executions (last 10) with method, URL, status code, and timing.

### get_request_detail

Full configuration of a specific request.

**Parameters**: `requestId` (string)

**Returns**: Method, URL, query parameters, headers, body type and content, auth type (credentials stripped), timeout, redirect settings, SSL verification, HTTP version.

### get_last_response

The most recent HTTP response for a request, with full metadata.

**Parameters**: `requestId` (string), `includeBody` (boolean, default: true)

**Returns**:
- Status code and status text
- All response headers (Content-Type, Cache-Control, X-Request-Id, etc.)
- Response body as text (truncated at 50KB; binary reports type and size)
- Timing breakdown: DNS lookup, connection, download, total (in ms)
- TLS certificate info: subject, issuer, expiry
- Size info: request/response header and body sizes, compression
- Redirect chain: each hop with URL and status code
- Final URL, HTTP version, remote address

### get_request_history

Recent execution history for a request.

**Parameters**: `requestId` (string), `limit` (number, default: 10)

**Returns**: Array of past executions with method, URL, status code, elapsed time, body size, and timestamp.

### list_projects

All projects in Reqeast with request counts.

**Returns**: Array of projects with ID, name, emoji, and number of requests.

### list_requests

All requests in a specific project.

**Parameters**: `projectId` (string)

**Returns**: Array of requests with ID, name, protocol type (HTTP/TCP/UDP/WebSocket/SSE), and a summary (method + URL for HTTP, host + port for TCP/UDP).

### get_environment

Environment variables for a project.

**Parameters**: `projectId` (string)

**Returns**: Active environment name and variables. All environments listed with variable counts. Secret values replaced with `[REDACTED]`.

### get_cookies

The cookie jar contents.

**Parameters**: `domain` (string, optional) -- filter by domain

**Returns**: All stored cookies with name, value, domain, path, expiry, httpOnly, secure, and sameSite attributes.

## What Is Exposed

| Data | Exposed | Details |
|------|---------|---------|
| Request URL | Yes | Full URL including query parameters |
| Request headers | Yes | All custom headers |
| Request body | Yes | Full body content (JSON, form data, raw, etc.) |
| Auth type | Yes | Which auth method is configured (Bearer, Basic, API Key, etc.) |
| Auth credentials | No | Tokens, passwords, API keys, and secrets are never exported |
| Response status | Yes | Status code and status text |
| Response headers | Yes | All response headers (Content-Type, Cache-Control, CORS, custom, etc.) |
| Response body | Yes | Up to 50KB of text; binary reports type and size |
| Timing breakdown | Yes | DNS lookup, connection, download, total (ms) |
| TLS certificate | Yes | Subject CN, issuer CN, expiry date |
| Size info | Yes | Request/response header and body sizes, compression |
| Redirect chain | Yes | Each hop URL and status code |
| Response metadata | Yes | Final URL, HTTP version, remote address |
| Cookies | Yes | Full cookie jar with all attributes |
| Environment variables | Yes | Key-value pairs for all environments |
| Secret env variables | Partial | Keys visible, values replaced with `[REDACTED]` |
| Keychain credentials | No | Never accessed or exported |
| Project/request names | Yes | Names and organizational structure |
| Request history | Yes | Last N executions with status codes and timing |

## Security

- **Read-only**: The MCP server cannot modify requests, send requests, or change settings.
- **Local only**: All data stays on your machine. Nothing is sent to external servers.
- **No credentials**: Auth tokens, passwords, API keys, and secret environment variable values are stripped before export. The AI sees the auth method but not the secret.
- **No Keychain access**: Credentials stored in the system Keychain are never read.
- **User controlled**: Disable in Settings > General > Enable MCP Export.

## Requirements

- macOS (MCP export is not available on iOS/iPadOS)
- Node.js 18+
- Reqeast must be running (or have been used recently)
- An MCP-compatible AI tool

## Compatibility

Works with any tool that supports MCP servers via stdio transport:

- Claude Code
- Claude Desktop
- Cursor
- VS Code (with MCP extensions)
- Windsurf
- Zed

## Troubleshooting

**"Reqeast data not found. Make sure the app is running."**
Open Reqeast and interact with a project/request to trigger the initial export. Make sure "Enable MCP Export" is on in Settings.

**"Data may be stale."**
Reqeast isn't running. Open the app and the data refreshes automatically.

**Response headers or timing missing**
Make sure you're running Reqeast version 1.1 or later. Older versions don't export response metadata.

**Tools return empty results**
Make sure you have at least one project with requests in Reqeast.
