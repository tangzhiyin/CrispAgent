import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const root = resolve(".");
const iosRoot = join(root, "ios");
const failures = [];

function fail(message) {
  failures.push(message);
}

function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });
}

function validateBalancedSwift(path) {
  const text = readFileSync(path, "utf8");
  const stack = [];
  let state = "code";
  let blockCommentDepth = 0;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];
    const triple = text.slice(index, index + 3);

    if (state === "line-comment") {
      if (char === "\n") state = "code";
      continue;
    }
    if (state === "block-comment") {
      if (char === "/" && next === "*") {
        blockCommentDepth += 1;
        index += 1;
      } else if (char === "*" && next === "/") {
        blockCommentDepth -= 1;
        index += 1;
        if (blockCommentDepth === 0) state = "code";
      }
      continue;
    }
    if (state === "string") {
      if (char === "\\") {
        index += 1;
      } else if (char === "\"") {
        state = "code";
      }
      continue;
    }
    if (state === "multiline-string") {
      if (triple === "\"\"\"") {
        state = "code";
        index += 2;
      }
      continue;
    }

    if (char === "/" && next === "/") {
      state = "line-comment";
      index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      state = "block-comment";
      blockCommentDepth = 1;
      index += 1;
      continue;
    }
    if (triple === "\"\"\"") {
      state = "multiline-string";
      index += 2;
      continue;
    }
    if (char === "\"") {
      state = "string";
      continue;
    }

    const pairs = { ")": "(", "]": "[", "}": "{" };
    if ("([{".includes(char)) {
      stack.push(char);
    } else if (char in pairs && stack.pop() !== pairs[char]) {
      fail(`${relative(root, path)} has an unmatched ${char}`);
      return;
    }
  }

  if (
    state === "block-comment"
    || state === "string"
    || state === "multiline-string"
  ) {
    fail(`${relative(root, path)} ends inside ${state}`);
  }
  if (stack.length > 0) {
    fail(`${relative(root, path)} has unclosed delimiters: ${stack.join("")}`);
  }
}

const requiredFiles = [
  "ios/project.yml",
  "ios/CrispAgent/App/CrispAgentApp.swift",
  "ios/CrispAgent/Models/ModelStore.swift",
  "ios/CrispAgent/Inference/LocalInferenceEngine.swift",
  "ios/CrispAgent/Skills/SkillStore.swift",
  "ios/CrispAgent/Views/ChatView.swift",
  "ios/CrispAgent/Resources/PrivacyInfo.xcprivacy",
  ".agents/skills/crisp-voice/SKILL.md",
];

for (const required of requiredFiles) {
  try {
    statSync(join(root, required));
  } catch {
    fail(`Missing required file: ${required}`);
  }
}

const swiftFiles = walk(iosRoot).filter((path) => path.endsWith(".swift"));
if (swiftFiles.length < 20) {
  fail(`Expected at least 20 Swift files, found ${swiftFiles.length}`);
}
for (const path of swiftFiles) {
  validateBalancedSwift(path);
}

for (const path of walk(iosRoot).filter((file) => file.endsWith(".json"))) {
  try {
    JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`${relative(root, path)} is invalid JSON: ${error.message}`);
  }
}

const project = readFileSync(join(iosRoot, "project.yml"), "utf8");
for (const fragment of [
  "exactVersion: 0.15.0",
  "product: LiteRTLM",
  "type: folder",
  "path: ../.agents/skills",
  "IPHONEOS_DEPLOYMENT_TARGET: 17.0",
]) {
  if (!project.includes(fragment)) {
    fail(`ios/project.yml is missing: ${fragment}`);
  }

  const privacyManifest = readFileSync(
    join(iosRoot, "CrispAgent", "Resources", "PrivacyInfo.xcprivacy"),
    "utf8",
  );
  for (const reason of ["CA92.1", "E174.1", "C617.1", "3B52.1"]) {
    if (!privacyManifest.includes(`<string>${reason}</string>`)) {
      fail(`PrivacyInfo.xcprivacy is missing required reason: ${reason}`);
    }
  }
}

const modelSource = readFileSync(
  join(iosRoot, "CrispAgent", "Models", "LocalModelDescriptor.swift"),
  "utf8",
);
for (const fragment of [
  "6b78abd019e61a1ca4cbe3b212d2c9ce8ff38a94",
  "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c",
  "2eee7ac325f20eb8c9ac1d0e972f7c84663062da",
  "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0",
]) {
  if (!modelSource.includes(fragment)) {
    fail(`Model catalog is missing pinned metadata: ${fragment}`);
  }
}

const iconPath = join(
  iosRoot,
  "CrispAgent",
  "Resources",
  "Assets.xcassets",
  "AppIcon.appiconset",
  "AppIcon-1024.png",
);
try {
  const icon = readFileSync(iconPath);
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!icon.subarray(0, 8).equals(signature)) {
    fail("AppIcon-1024.png is not a PNG");
  }
  if (icon.readUInt32BE(16) !== 1024 || icon.readUInt32BE(20) !== 1024) {
    fail("AppIcon-1024.png must be 1024 x 1024");
  }
  if (icon[25] !== 2) {
    fail("AppIcon-1024.png must be RGB without an alpha channel");
  }
} catch {
  fail("Missing generated AppIcon-1024.png; run npm run ios:icon");
}

if (failures.length > 0) {
  console.error(failures.map((failure) => `- ${failure}`).join("\n"));
  process.exitCode = 1;
} else {
  console.log(
    `Validated ${swiftFiles.length} Swift files and iOS project resources.`,
  );
}
