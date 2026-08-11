import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import test from "node:test";
import { createAppServer } from "../src/app-server.js";
import { PROJECT_ROOT } from "../src/config.js";

const TOKEN = "test-pairing-token-1234567890";

class FakeRuntime {
  async getStatus() {
    return {
      state: "ready",
      model: "fake-model",
      skill: { name: "crisp-voice", fingerprint: "abc123" },
    };
  }

  async streamConversation({ conversationId, message, onEvent }) {
    onEvent({ type: "start", conversationId, skill: "crisp-voice" });
    onEvent({ type: "delta", content: "我建议" });
    onEvent({ type: "final", content: `我建议：${message}`, model: "fake-model" });
    onEvent({ type: "done" });
  }

  async abortConversation() {
    return true;
  }

  async deleteConversation() {
    return true;
  }
}

async function startTestServer() {
  const server = await createAppServer({
    config: {
      publicDirectory: `${PROJECT_ROOT}\\public`,
      pairingToken: TOKEN,
      httpsCertPath: undefined,
      httpsKeyPath: undefined,
    },
    runtime: new FakeRuntime(),
    logger: { error() {} },
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();
  return { server, baseUrl: `http://127.0.0.1:${port}` };
}

test("serves the iPhone app and protects agent APIs", async (context) => {
  const { server, baseUrl } = await startTestServer();
  context.after(() => server.close());

  const page = await fetch(`${baseUrl}/`);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /Crisp Agent/);
  assert.match(page.headers.get("content-security-policy"), /default-src 'self'/);

  const health = await fetch(`${baseUrl}/api/health`);
  assert.deepEqual(await health.json(), { ok: true });

  const unauthorized = await fetch(`${baseUrl}/api/status`);
  assert.equal(unauthorized.status, 401);

  const status = await fetch(`${baseUrl}/api/status`, {
    headers: { Authorization: `Bearer ${TOKEN}` },
  });
  assert.equal(status.status, 200);
  assert.equal((await status.json()).skill.name, "crisp-voice");
});

test("streams authenticated NDJSON chat responses", async (context) => {
  const { server, baseUrl } = await startTestServer();
  context.after(() => server.close());

  const conversationId = randomUUID();
  const response = await fetch(`${baseUrl}/api/chat`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
      Origin: baseUrl,
    },
    body: JSON.stringify({
      conversationId,
      message: "先做什么？",
      history: [],
    }),
  });

  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /application\/x-ndjson/);
  const events = (await response.text())
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  assert.equal(events[0].skill, "crisp-voice");
  assert.equal(events.at(-1).type, "done");
  assert.equal(events.find((event) => event.type === "final").content, "我建议：先做什么？");
});

test("rejects cross-origin API requests", async (context) => {
  const { server, baseUrl } = await startTestServer();
  context.after(() => server.close());

  const response = await fetch(`${baseUrl}/api/status`, {
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Origin: "https://example.com",
    },
  });
  assert.equal(response.status, 403);
});
