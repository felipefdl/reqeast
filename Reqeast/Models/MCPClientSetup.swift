//
//  MCPClientSetup.swift
//  Reqeast
//

#if os(macOS)
import Foundation

enum MCPClientSetup: String, CaseIterable, Identifiable, Codable {
    case claudeCode, cursor, vsCodeCopilot, antigravity, windsurf, zed,
         jetBrains, claudeDesktop, codex, geminiCli, openCode, crush,
         amp, cline, rooCode, amazonQ, warp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .vsCodeCopilot: "VS Code (Copilot)"
        case .antigravity: "Antigravity"
        case .windsurf: "Windsurf"
        case .zed: "Zed"
        case .jetBrains: "JetBrains"
        case .claudeDesktop: "Claude Desktop"
        case .codex: "Codex"
        case .geminiCli: "Gemini CLI"
        case .openCode: "OpenCode"
        case .crush: "Crush"
        case .amp: "Amp"
        case .cline: "Cline"
        case .rooCode: "Roo Code"
        case .amazonQ: "Amazon Q"
        case .warp: "Warp"
        }
    }

    var setupDescription: String {
        switch self {
        case .claudeCode, .codex, .geminiCli, .openCode, .amp:
            String(localized: "Run this command in your terminal:")
        case .cursor:
            String(localized: "Add to .cursor/mcp.json in your project:")
        case .vsCodeCopilot:
            String(localized: "Add to .vscode/mcp.json in your project:")
        case .antigravity:
            String(localized: "Add to ~/.gemini/antigravity/mcp_config.json:")
        case .windsurf:
            String(localized: "Add to ~/.codeium/windsurf/mcp_config.json:")
        case .zed:
            String(localized: "Add to your Zed settings JSON:")
        case .jetBrains:
            String(localized: "Go to Settings > Tools > AI Assistant > MCP, then add:")
        case .claudeDesktop:
            String(localized: "Add to ~/Library/Application Support/Claude/claude_desktop_config.json:")
        case .crush:
            String(localized: "Add to ~/.config/crush/crush.json:")
        case .cline:
            String(localized: "Open Cline MCP settings and add:")
        case .rooCode:
            String(localized: "Open Roo Code MCP settings and add:")
        case .amazonQ:
            String(localized: "Add to ~/.aws/amazonq/mcp.json:")
        case .warp:
            String(localized: "Add via Warp MCP settings UI:")
        }
    }

    var highlightLanguage: String {
        switch self {
        case .claudeCode, .codex, .geminiCli, .openCode, .amp:
            "bash"
        default:
            "javascript"
        }
    }

    private static let sharedMcpJson = """
        {
          "mcpServers": {
            "reqeast": {
              "command": "npx",
              "args": ["-y", "reqeast-mcp"]
            }
          }
        }
        """

    var setupSnippet: String {
        switch self {
        case .claudeCode:
            "claude mcp add reqeast -- npx -y reqeast-mcp"
        case .codex:
            "codex mcp add reqeast -- npx -y reqeast-mcp"
        case .geminiCli:
            "gemini mcp add reqeast npx -y reqeast-mcp"
        case .amp:
            "amp mcp add reqeast -- npx -y reqeast-mcp"
        case .vsCodeCopilot:
            """
            {
              "servers": {
                "reqeast": {
                  "command": "npx",
                  "args": ["-y", "reqeast-mcp"]
                }
              }
            }
            """
        case .zed:
            """
            {
              "context_servers": {
                "reqeast": {
                  "command": "npx",
                  "args": ["-y", "reqeast-mcp"]
                }
              }
            }
            """
        case .openCode:
            "opencode mcp add"
        case .crush:
            """
            {
              "mcp": {
                "reqeast": {
                  "type": "stdio",
                  "command": "npx",
                  "args": ["-y", "reqeast-mcp"]
                }
              }
            }
            """
        default:
            Self.sharedMcpJson
        }
    }
}
#endif
