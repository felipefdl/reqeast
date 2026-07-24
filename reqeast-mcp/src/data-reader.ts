import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type {
  MCPContext,
  MCPProjectsExport,
  MCPEnvironmentsExport,
  MCPHistoryEntry,
  MCPResponseMeta,
  MCPStoredCookie,
} from "./types.js";

const HOME = os.homedir();
const BUNDLE_ID = "app.reqeast";

const SANDBOXED_BASE = path.join(
  HOME, "Library/Containers", BUNDLE_ID,
  "Data/Library/Application Support/reqeast"
);

const DIRECT_BASE = path.join(
  HOME, "Library/Application Support/reqeast"
);

function getBasePath(): string {
  if (fs.existsSync(path.join(SANDBOXED_BASE, "mcp"))) return SANDBOXED_BASE;
  if (fs.existsSync(path.join(DIRECT_BASE, "mcp"))) return DIRECT_BASE;
  throw new Error("Reqeast data not found. Make sure the app is running and has been used at least once.");
}

function readJSON<T>(filePath: string): T {
  const content = fs.readFileSync(filePath, "utf-8");
  return JSON.parse(content) as T;
}

export function readContext(): MCPContext {
  const base = getBasePath();
  return readJSON<MCPContext>(path.join(base, "mcp", "context.json"));
}

export function readProjects(): MCPProjectsExport {
  const base = getBasePath();
  return readJSON<MCPProjectsExport>(path.join(base, "mcp", "projects.json"));
}

export function readEnvironments(): MCPEnvironmentsExport {
  const base = getBasePath();
  return readJSON<MCPEnvironmentsExport>(path.join(base, "mcp", "environments.json"));
}

export function readHistory(requestId: string): MCPHistoryEntry[] {
  const base = getBasePath();
  const context = readContext();
  const historyPath = path.join(base, context.sessionsDir, `${requestId}-history.json`);
  if (!fs.existsSync(historyPath)) return [];
  return readJSON<MCPHistoryEntry[]>(historyPath);
}

export function readResponseMeta(requestId: string): MCPResponseMeta | null {
  const base = getBasePath();
  const context = readContext();
  const metaPath = path.join(base, context.sessionsDir, `${requestId}-response-meta.json`);
  if (!fs.existsSync(metaPath)) return null;
  return readJSON<MCPResponseMeta>(metaPath);
}

export function readResponseBody(requestId: string): { data: Buffer; exists: boolean } {
  const base = getBasePath();
  const context = readContext();
  const bodyPath = path.join(base, context.sessionsDir, `${requestId}-response.bin`);
  if (!fs.existsSync(bodyPath)) return { data: Buffer.alloc(0), exists: false };
  return { data: fs.readFileSync(bodyPath), exists: true };
}

export function readCookies(): MCPStoredCookie[] {
  const base = getBasePath();
  const context = readContext();
  const cookiesPath = path.join(base, context.sessionsDir, "cookies.json");
  if (!fs.existsSync(cookiesPath)) return [];
  return readJSON<MCPStoredCookie[]>(cookiesPath);
}

export function getStalenessWarning(context: MCPContext): string | null {
  const exported = new Date(context.timestamp);
  const now = new Date();
  const diffMs = now.getTime() - exported.getTime();
  const ONE_HOUR = 60 * 60 * 1000;
  if (diffMs > ONE_HOUR) {
    return `Note: Data may be stale. Reqeast last exported at ${context.timestamp}.`;
  }
  return null;
}

const MAX_TEXT_SIZE = 50_000;

export function formatResponseBody(data: Buffer, contentType: string | null): string {
  const isText = !contentType ||
    contentType.includes("text/") ||
    contentType.includes("json") ||
    contentType.includes("xml") ||
    contentType.includes("javascript") ||
    contentType.includes("html") ||
    contentType.includes("css") ||
    contentType.includes("yaml") ||
    contentType.includes("csv") ||
    contentType.includes("svg");

  if (!isText) {
    return `[Binary data, ${data.length} bytes, content-type: ${contentType}]`;
  }

  const text = data.toString("utf-8");
  if (text.length > MAX_TEXT_SIZE) {
    return text.slice(0, MAX_TEXT_SIZE) + `\n... [truncated, total ${data.length} bytes]`;
  }
  return text;
}
