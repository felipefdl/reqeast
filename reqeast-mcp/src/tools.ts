import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import {
  readContext,
  readProjects,
  readEnvironments,
  readHistory,
  readResponseBody,
  readResponseMeta,
  readCookies,
  getStalenessWarning,
  formatResponseBody,
} from "./data-reader.js";

function textResult(data: unknown): { content: Array<{ type: "text"; text: string }> } {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
}

function errorResult(message: string): { content: Array<{ type: "text"; text: string }>; isError: true } {
  return { content: [{ type: "text" as const, text: message }], isError: true };
}

export function registerTools(server: McpServer): void {
  // 1. get_active_context
  server.tool(
    "get_active_context",
    "Get the currently selected project and request in Reqeast, including recent execution history",
    {},
    async () => {
      try {
        const context = readContext();
        const projects = readProjects();
        const warnings: string[] = [];

        const stale = getStalenessWarning(context);
        if (stale) warnings.push(stale);

        const selectedProject = context.selectedProjectId
          ? projects.projects.find((p) => p.id === context.selectedProjectId) ?? null
          : null;

        const selectedRequest = context.selectedRequestId
          ? projects.requests.find((r) => r.id === context.selectedRequestId) ?? null
          : null;

        return textResult({
          warnings: warnings.length > 0 ? warnings : undefined,
          selectedProject,
          selectedRequest,
          recentExecutions: context.recentExecutions,
        });
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );

  // 2. get_request_detail
  server.tool(
    "get_request_detail",
    "Get full configuration of a specific request (method, URL, headers, body, auth type, settings)",
    { requestId: z.string().describe("The request UUID") },
    async ({ requestId }) => {
      try {
        const projects = readProjects();
        const request = projects.requests.find((r) => r.id === requestId);
        if (!request) return errorResult(`Request not found: ${requestId}`);
        return textResult(request);
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );

  // 3. get_last_response
  server.tool(
    "get_last_response",
    "Get the most recent HTTP response for a request (status, headers, body, timing)",
    {
      requestId: z.string().describe("The request UUID"),
      includeBody: z.boolean().optional().default(true).describe("Include response body text (default: true)"),
    },
    async ({ requestId, includeBody }) => {
      try {
        const meta = readResponseMeta(requestId);
        const history = readHistory(requestId);

        if (!meta && history.length === 0) {
          return errorResult(`No response data found for request: ${requestId}`);
        }

        const { data, exists } = readResponseBody(requestId);

        const result: Record<string, unknown> = meta
          ? {
              statusCode: meta.statusCode,
              statusText: meta.statusText,
              headers: meta.headers.filter((h) => h.enabled),
              elapsedMs: meta.elapsedMs,
              bodySize: meta.bodySize,
              finalUrl: meta.finalUrl,
              httpVersion: meta.httpVersion,
              remoteAddr: meta.remoteAddr,
              timestamp: meta.timestamp,
              timing: meta.timing,
              certificate: meta.certificate,
              sizeInfo: meta.sizeInfo,
              redirectChain: meta.redirectChain.length > 0 ? meta.redirectChain : undefined,
            }
          : {
              statusCode: history[history.length - 1].statusCode,
              method: history[history.length - 1].method,
              url: history[history.length - 1].url,
              elapsedMs: history[history.length - 1].elapsedMs,
              bodySize: history[history.length - 1].bodySize,
              timestamp: history[history.length - 1].timestamp,
            };

        if (includeBody && exists && data.length > 0) {
          const contentType = meta
            ? meta.headers.find((h) => h.key.toLowerCase() === "content-type")?.value ?? null
            : null;
          result.body = formatResponseBody(data, contentType);
        } else if (!exists) {
          result.body = "[No response body saved]";
        }

        return textResult(result);
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );

  // 4. get_request_history
  server.tool(
    "get_request_history",
    "Get recent execution history entries for a request",
    {
      requestId: z.string().describe("The request UUID"),
      limit: z.number().optional().default(10).describe("Max entries to return (default: 10)"),
    },
    async ({ requestId, limit }) => {
      try {
        const history = readHistory(requestId);
        if (history.length === 0) return errorResult(`No history found for request: ${requestId}`);
        const entries = history.slice(-limit);
        return textResult({ requestId, total: history.length, entries });
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );

  // 5. list_projects
  server.tool(
    "list_projects",
    "List all projects in Reqeast with request counts",
    {},
    async () => {
      try {
        const projects = readProjects();
        const result = projects.projects.map((p) => ({
          id: p.id,
          name: p.name,
          emoji: p.emoji,
          requestCount: projects.requests.filter((r) => r.projectId === p.id).length,
        }));
        return textResult(result);
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );

  // 6. list_requests
  server.tool(
    "list_requests",
    "List all requests in a project with type and URL summary",
    { projectId: z.string().describe("The project UUID") },
    async ({ projectId }) => {
      try {
        const projects = readProjects();
        const requests = projects.requests.filter((r) => r.projectId === projectId);
        if (requests.length === 0) {
          const project = projects.projects.find((p) => p.id === projectId);
          if (!project) return errorResult(`Project not found: ${projectId}`);
          return textResult({ projectId, projectName: project.name, requests: [] });
        }

        const project = projects.projects.find((p) => p.id === projectId);
        const result = requests.map((r) => {
          let summary = "";
          if (r.httpData) {
            summary = `${r.httpData.method} ${r.httpData.url}`;
          } else if (r.tcpData) {
            summary = `${r.tcpData.host}:${r.tcpData.port}${r.tcpData.useTls ? " (TLS)" : ""}`;
          } else if (r.udpData) {
            summary = `${r.udpData.host}:${r.udpData.port}`;
          }
          return {
            id: r.id,
            name: r.name,
            type: r.type,
            folderId: r.folderId,
            summary,
          };
        });

        return textResult({ projectId, projectName: project?.name, requests: result });
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );

  // 7. get_environment
  server.tool(
    "get_environment",
    "Get environment variables for a project (secret values are redacted)",
    { projectId: z.string().describe("The project UUID") },
    async ({ projectId }) => {
      try {
        const envData = readEnvironments();
        const envs = envData.environments.filter((e) => e.projectId === projectId);
        const active = envs.find((e) => e.isActive);

        return textResult({
          projectId,
          activeEnvironment: active
            ? {
                id: active.id,
                name: active.name,
                variables: active.variables.filter((v) => v.enabled).map((v) => ({
                  key: v.key,
                  value: v.isSecret ? "[REDACTED]" : v.value,
                  isSecret: v.isSecret,
                })),
              }
            : null,
          allEnvironments: envs.map((e) => ({
            id: e.id,
            name: e.name,
            isActive: e.isActive,
            variableCount: e.variables.length,
          })),
        });
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );

  // 8. get_cookies
  server.tool(
    "get_cookies",
    "Get the cookie jar contents (all stored cookies from HTTP responses)",
    {
      domain: z.string().optional().describe("Filter cookies by domain (optional)"),
    },
    async ({ domain }) => {
      try {
        let cookies = readCookies();
        if (cookies.length === 0) return errorResult("Cookie jar is empty");

        if (domain) {
          cookies = cookies.filter((c) => c.domain.includes(domain));
          if (cookies.length === 0) return errorResult(`No cookies found for domain: ${domain}`);
        }

        return textResult(cookies.map((c) => ({
          name: c.name,
          value: c.value,
          domain: c.domain,
          path: c.path,
          expires: c.expires,
          httpOnly: c.httpOnly,
          secure: c.secure,
          sameSite: c.sameSite,
        })));
      } catch (e) {
        return errorResult(e instanceof Error ? e.message : String(e));
      }
    }
  );
}
