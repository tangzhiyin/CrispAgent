import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { loadConfig } from "../src/config.js";

test("generates and reuses a local pairing token", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "crisp-agent-config-"));
  try {
    const first = await loadConfig({}, root);
    const second = await loadConfig({}, root);

    assert.equal(first.pairingToken, second.pairingToken);
    assert.ok(first.pairingToken.length >= 32);
    assert.equal(
      (await readFile(path.join(root, ".data", "pairing-token"), "utf8")).trim(),
      first.pairingToken,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("rejects incomplete HTTPS configuration", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "crisp-agent-https-"));
  try {
    await assert.rejects(
      loadConfig({ CRISP_AGENT_HTTPS_CERT: "cert.pem" }, root),
      /must be set together/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
