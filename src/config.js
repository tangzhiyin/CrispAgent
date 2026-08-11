import { randomBytes } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SOURCE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
export const PROJECT_ROOT = path.resolve(SOURCE_DIRECTORY, "..");

function readInteger(value, fallback, { min, max, name }) {
  if (value === undefined || value === "") {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}.`);
  }
  return parsed;
}

function readOptionalPath(value, rootDirectory) {
  return value ? path.resolve(rootDirectory, value) : undefined;
}

function validatePairingToken(token) {
  if (token.length < 16 || token.length > 256) {
    throw new Error("CRISP_AGENT_TOKEN must contain between 16 and 256 characters.");
  }
  return token;
}

async function loadOrCreatePairingToken(dataDirectory, configuredToken) {
  if (configuredToken) {
    return validatePairingToken(configuredToken.trim());
  }

  await mkdir(dataDirectory, { recursive: true });
  const tokenPath = path.join(dataDirectory, "pairing-token");

  try {
    const existing = (await readFile(tokenPath, "utf8")).trim();
    return validatePairingToken(existing);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }

  const generated = randomBytes(32).toString("base64url");
  try {
    await writeFile(tokenPath, `${generated}\n`, { encoding: "utf8", flag: "wx", mode: 0o600 });
    return generated;
  } catch (error) {
    if (error.code !== "EEXIST") {
      throw error;
    }
    return validatePairingToken((await readFile(tokenPath, "utf8")).trim());
  }
}

export async function loadConfig(env = process.env, rootDirectory = PROJECT_ROOT) {
  const dataDirectory = path.resolve(rootDirectory, env.CRISP_AGENT_DATA_DIR || ".data");
  const pairingToken = await loadOrCreatePairingToken(dataDirectory, env.CRISP_AGENT_TOKEN);
  const skillDirectory = path.resolve(
    rootDirectory,
    env.CRISP_AGENT_SKILL_DIR || path.join(".agents", "skills", "crisp-voice"),
  );

  const httpsCertPath = readOptionalPath(env.CRISP_AGENT_HTTPS_CERT, rootDirectory);
  const httpsKeyPath = readOptionalPath(env.CRISP_AGENT_HTTPS_KEY, rootDirectory);
  if (Boolean(httpsCertPath) !== Boolean(httpsKeyPath)) {
    throw new Error("CRISP_AGENT_HTTPS_CERT and CRISP_AGENT_HTTPS_KEY must be set together.");
  }

  const reasoningEffort = env.CRISP_AGENT_REASONING_EFFORT?.trim() || undefined;
  if (reasoningEffort && !["low", "medium", "high", "xhigh", "max"].includes(reasoningEffort)) {
    throw new Error("CRISP_AGENT_REASONING_EFFORT must be low, medium, high, xhigh, or max.");
  }

  return Object.freeze({
    rootDirectory,
    publicDirectory: path.join(rootDirectory, "public"),
    dataDirectory,
    skillDirectory,
    skillsRoot: path.dirname(skillDirectory),
    pairingToken,
    host: env.CRISP_AGENT_HOST?.trim() || "0.0.0.0",
    port: readInteger(env.CRISP_AGENT_PORT, 8787, {
      min: 0,
      max: 65535,
      name: "CRISP_AGENT_PORT",
    }),
    model: env.CRISP_AGENT_MODEL?.trim() || "auto",
    reasoningEffort,
    requestTimeoutMs: readInteger(env.CRISP_AGENT_TIMEOUT_MS, 180_000, {
      min: 10_000,
      max: 900_000,
      name: "CRISP_AGENT_TIMEOUT_MS",
    }),
    sessionTtlMs: readInteger(env.CRISP_AGENT_SESSION_TTL_MS, 3_600_000, {
      min: 60_000,
      max: 86_400_000,
      name: "CRISP_AGENT_SESSION_TTL_MS",
    }),
    maxSessions: readInteger(env.CRISP_AGENT_MAX_SESSIONS, 20, {
      min: 1,
      max: 200,
      name: "CRISP_AGENT_MAX_SESSIONS",
    }),
    copilotHome: path.resolve(env.CRISP_AGENT_COPILOT_HOME || path.join(homedir(), ".copilot")),
    httpsCertPath,
    httpsKeyPath,
  });
}
