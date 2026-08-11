import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import path from "node:path";
import test from "node:test";
import { AgentRuntime } from "../src/agent-runtime.js";
import { PROJECT_ROOT } from "../src/config.js";

class FakeSession {
  constructor() {
    this.handlers = new Map();
    this.lastPrompt = "";
  }

  on(eventType, handler) {
    const handlers = this.handlers.get(eventType) || new Set();
    handlers.add(handler);
    this.handlers.set(eventType, handlers);
    return () => handlers.delete(handler);
  }

  emit(eventType, data) {
    for (const handler of this.handlers.get(eventType) || []) {
      handler({ type: eventType, data });
    }
  }

  async sendAndWait({ prompt }) {
    this.lastPrompt = prompt;
    this.emit("assistant.message_delta", { deltaContent: "我建议" });
    this.emit("assistant.message", { content: "我建议先确认。", model: "fake-model" });
    return { data: { content: "我建议先确认。", model: "fake-model" } };
  }

  async abort() {}

  async disconnect() {}
}

class FakeClient {
  constructor() {
    this.session = new FakeSession();
    this.sessionConfig = undefined;
    this.started = false;
  }

  async start() {
    this.started = true;
  }

  async createSession(config) {
    this.sessionConfig = config;
    return this.session;
  }

  async stop() {
    this.started = false;
    return [];
  }
}

test("preloads crisp-voice into a tool-free custom agent", async () => {
  const fakeClient = new FakeClient();
  const config = {
    rootDirectory: PROJECT_ROOT,
    skillDirectory: path.join(PROJECT_ROOT, ".agents", "skills", "crisp-voice"),
    skillsRoot: path.join(PROJECT_ROOT, ".agents", "skills"),
    copilotHome: path.join(PROJECT_ROOT, ".data", "test-copilot-home"),
    model: "auto",
    reasoningEffort: undefined,
    requestTimeoutMs: 30_000,
    sessionTtlMs: 60_000,
    maxSessions: 2,
  };
  const runtime = new AgentRuntime(config, { clientFactory: () => fakeClient });
  const events = [];

  try {
    const answer = await runtime.streamConversation({
      conversationId: randomUUID(),
      message: "现在怎么做？",
      history: [{ role: "user", content: "电脑很卡。" }],
      onEvent: (event) => events.push(event),
    });

    assert.equal(answer, "我建议先确认。");
    assert.equal(fakeClient.sessionConfig.agent, "crisp-mobile");
    assert.deepEqual(fakeClient.sessionConfig.customAgents[0].skills, ["crisp-voice"]);
    assert.deepEqual(fakeClient.sessionConfig.customAgents[0].tools, []);
    assert.deepEqual(fakeClient.sessionConfig.availableTools.toArray(), []);
    assert.match(
      fakeClient.sessionConfig.customAgents[0].prompt,
      /Confirmed authentic samples/,
    );
    assert.match(fakeClient.session.lastPrompt, /conversation_history_json/);
    assert.ok(events.some((event) => event.type === "delta"));
    assert.ok(events.some((event) => event.type === "final"));
  } finally {
    await runtime.stop();
  }
});
