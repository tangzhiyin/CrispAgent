import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { PROJECT_ROOT } from "../src/config.js";
import { loadSkillBundle, parseSkillFrontmatter } from "../src/skill-bundle.js";

test("parses nested skill metadata", () => {
  const metadata = parseSkillFrontmatter(`---
name: demo
metadata:
  version: "1.2.3"
---
# Demo
`);

  assert.equal(metadata.name, "demo");
  assert.equal(metadata["metadata.version"], "1.2.3");
});

test("loads crisp-voice and its linked reference files", async () => {
  const bundle = await loadSkillBundle(
    path.join(PROJECT_ROOT, ".agents", "skills", "crisp-voice"),
  );

  assert.equal(bundle.name, "crisp-voice");
  assert.equal(bundle.version, "0.1.0");
  assert.equal(bundle.fileCount, 4);
  assert.match(bundle.supportingContext, /Confirmed authentic samples/);
  assert.match(bundle.supportingContext, /C and C\+\+/);
  assert.match(bundle.supportingContext, /Generated style examples/);
  assert.match(bundle.hash, /^[0-9a-f]{64}$/);
});
