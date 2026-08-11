import { randomUUID } from "node:crypto";
import { AgentRuntime } from "../src/agent-runtime.js";
import { loadConfig } from "../src/config.js";

const config = await loadConfig();
const runtime = new AgentRuntime(config);
const events = [];

try {
  await runtime.start();
  const status = await runtime.getStatus();
  if (status.state !== "ready" || status.skill?.name !== "crisp-voice") {
    throw new Error(`Unexpected runtime status: ${JSON.stringify(status)}`);
  }

  const answer = await runtime.streamConversation({
    conversationId: randomUUID(),
    message: "同事问我要不要马上重装系统，帮我直接回复他。",
    history: [],
    onEvent: (event) => events.push(event),
  });

  if (!answer.trim()) {
    throw new Error("The smoke test returned an empty answer.");
  }
  if (/crisp-voice|skill/i.test(answer)) {
    throw new Error("The answer exposed internal skill details.");
  }
  if (!events.some((event) => event.type === "start" && event.skill === "crisp-voice")) {
    throw new Error("The runtime did not report the crisp-voice skill.");
  }

  console.log(answer);
} finally {
  await runtime.stop();
}
