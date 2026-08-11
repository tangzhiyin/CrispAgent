import { timingSafeEqual } from "node:crypto";
import { readFile } from "node:fs/promises";
import http from "node:http";
import https from "node:https";
import path from "node:path";
import { AgentBusyError, AgentCapacityError } from "./agent-runtime.js";

const MAX_REQUEST_BYTES = 128 * 1024;
const MIME_TYPES = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
  [".webmanifest", "application/manifest+json; charset=utf-8"],
]);

function applySecurityHeaders(response, isHttps) {
  response.setHeader(
    "Content-Security-Policy",
    "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
  );
  response.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("X-Frame-Options", "DENY");
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader("Permissions-Policy", "camera=(), geolocation=(), microphone=(self)");
  if (isHttps) {
    response.setHeader("Strict-Transport-Security", "max-age=31536000");
  }
}

function sendJson(response, statusCode, payload) {
  if (response.headersSent) {
    return;
  }
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(payload));
}

function tokenMatches(authorization, expectedToken) {
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return false;
  }
  const actual = Buffer.from(match[1], "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function requestHasValidOrigin(request) {
  const origin = request.headers.origin;
  if (!origin) {
    return true;
  }
  try {
    return new URL(origin).host === request.headers.host;
  } catch {
    return false;
  }
}

async function readJsonBody(request) {
  const contentType = request.headers["content-type"] || "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    const error = new Error("Content-Type must be application/json.");
    error.statusCode = 415;
    throw error;
  }

  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_REQUEST_BYTES) {
      const error = new Error("Request body is too large.");
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    const error = new Error("Request body is not valid JSON.");
    error.statusCode = 400;
    throw error;
  }
}

function validateHistory(history) {
  if (history === undefined) {
    return [];
  }
  if (!Array.isArray(history) || history.length > 50) {
    throw new TypeError("history must be an array with at most 50 messages.");
  }
  return history.map((message) => {
    if (
      !message ||
      !["user", "assistant"].includes(message.role) ||
      typeof message.content !== "string" ||
      message.content.length > 8_000
    ) {
      throw new TypeError("history contains an invalid message.");
    }
    return { role: message.role, content: message.content };
  });
}

function streamHeaders(response) {
  if (!response.headersSent) {
    response.writeHead(200, {
      "Content-Type": "application/x-ndjson; charset=utf-8",
      "Cache-Control": "no-store, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    response.flushHeaders?.();
  }
}

function writeStreamEvent(response, event) {
  if (response.destroyed || response.writableEnded) {
    return;
  }
  streamHeaders(response);
  response.write(`${JSON.stringify(event)}\n`);
}

function normalizeError(error) {
  if (error instanceof AgentBusyError) {
    return { statusCode: 409, code: "conversation_busy", message: error.message };
  }
  if (error instanceof AgentCapacityError) {
    return { statusCode: 503, code: "capacity_reached", message: error.message };
  }
  if (error instanceof TypeError) {
    return { statusCode: 400, code: "invalid_request", message: error.message };
  }
  if (error?.name === "AbortError") {
    return { statusCode: 499, code: "aborted", message: "The request was cancelled." };
  }
  return {
    statusCode: error?.statusCode || 500,
    code: "agent_error",
    message: error instanceof Error ? error.message : "Unexpected agent error.",
  };
}

function safePublicPath(publicDirectory, pathname) {
  const requested = pathname === "/" ? "index.html" : decodeURIComponent(pathname.slice(1));
  const resolved = path.resolve(publicDirectory, requested);
  const relative = path.relative(publicDirectory, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    return undefined;
  }
  return resolved;
}

async function serveStatic(request, response, config, pathname) {
  if (!["GET", "HEAD"].includes(request.method)) {
    sendJson(response, 405, { error: "method_not_allowed" });
    return;
  }

  const filePath = safePublicPath(config.publicDirectory, pathname);
  if (!filePath) {
    sendJson(response, 404, { error: "not_found" });
    return;
  }

  try {
    const content = await readFile(filePath);
    const extension = path.extname(filePath).toLowerCase();
    response.writeHead(200, {
      "Content-Type": MIME_TYPES.get(extension) || "application/octet-stream",
      "Cache-Control":
        path.basename(filePath) === "index.html" ? "no-cache" : "public, max-age=3600",
    });
    response.end(request.method === "HEAD" ? undefined : content);
  } catch (error) {
    if (error.code === "ENOENT" || error.code === "EISDIR") {
      sendJson(response, 404, { error: "not_found" });
      return;
    }
    throw error;
  }
}

function createRequestHandler({ config, runtime, logger, isHttps }) {
  return async (request, response) => {
    applySecurityHeaders(response, isHttps);
    const requestUrl = new URL(request.url || "/", `${isHttps ? "https" : "http"}://localhost`);
    const { pathname } = requestUrl;

    try {
      if (pathname === "/api/health" && request.method === "GET") {
        sendJson(response, 200, { ok: true });
        return;
      }

      if (pathname.startsWith("/api/")) {
        if (!requestHasValidOrigin(request)) {
          sendJson(response, 403, { error: "invalid_origin" });
          return;
        }
        if (!tokenMatches(request.headers.authorization, config.pairingToken)) {
          sendJson(response, 401, { error: "unauthorized" });
          return;
        }
      }

      if (pathname === "/api/status" && request.method === "GET") {
        sendJson(response, 200, await runtime.getStatus());
        return;
      }

      if (pathname === "/api/chat" && request.method === "POST") {
        const body = await readJsonBody(request);
        const history = validateHistory(body.history);
        const abortController = new AbortController();
        let completed = false;
        const handleClose = () => {
          if (!completed) {
            abortController.abort();
          }
        };
        response.on("close", handleClose);

        try {
          await runtime.streamConversation({
            conversationId: body.conversationId,
            message: body.message,
            history,
            signal: abortController.signal,
            onEvent: (event) => writeStreamEvent(response, event),
          });
          completed = true;
          if (!response.headersSent) {
            streamHeaders(response);
          }
          if (!response.writableEnded) {
            response.end();
          }
        } catch (error) {
          completed = true;
          const normalized = normalizeError(error);
          if (!response.headersSent) {
            sendJson(response, normalized.statusCode, {
              error: normalized.code,
              message: normalized.message,
            });
          } else if (!response.destroyed && !response.writableEnded) {
            writeStreamEvent(response, {
              type: "error",
              code: normalized.code,
              message: normalized.message,
            });
            response.end();
          }
          if (normalized.statusCode >= 500) {
            logger.error("Agent request failed:", normalized.message);
          }
        } finally {
          response.off("close", handleClose);
        }
        return;
      }

      const conversationRoute = pathname.match(
        /^\/api\/conversations\/([0-9a-f-]+)\/(abort|delete)$/,
      );
      if (conversationRoute && request.method === "POST") {
        const [, conversationId, action] = conversationRoute;
        const changed =
          action === "abort"
            ? await runtime.abortConversation(conversationId)
            : await runtime.deleteConversation(conversationId);
        sendJson(response, 200, { ok: true, changed });
        return;
      }

      if (pathname.startsWith("/api/")) {
        sendJson(response, 404, { error: "not_found" });
        return;
      }

      await serveStatic(request, response, config, pathname);
    } catch (error) {
      const normalized = normalizeError(error);
      logger.error("HTTP request failed:", normalized.message);
      sendJson(response, normalized.statusCode, {
        error: normalized.code,
        message: normalized.message,
      });
    }
  };
}

export async function createAppServer({ config, runtime, logger = console }) {
  const isHttps = Boolean(config.httpsCertPath);
  const handler = createRequestHandler({ config, runtime, logger, isHttps });
  if (!isHttps) {
    return http.createServer(handler);
  }

  const [cert, key] = await Promise.all([
    readFile(config.httpsCertPath),
    readFile(config.httpsKeyPath),
  ]);
  return https.createServer({ cert, key }, handler);
}
