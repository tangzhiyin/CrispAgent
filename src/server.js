import { networkInterfaces } from "node:os";
import { AgentRuntime } from "./agent-runtime.js";
import { createAppServer } from "./app-server.js";
import { loadConfig } from "./config.js";

function getReachableHosts(config) {
  if (config.host === "127.0.0.1" || config.host === "localhost") {
    return ["127.0.0.1"];
  }
  if (config.host !== "0.0.0.0" && config.host !== "::") {
    return [config.host];
  }

  const addresses = [];
  for (const interfaces of Object.values(networkInterfaces())) {
    for (const address of interfaces || []) {
      if (address.family === "IPv4" && !address.internal) {
        addresses.push(address.address);
      }
    }
  }
  return [...new Set(addresses)];
}

function listen(server, port, host) {
  return new Promise((resolve, reject) => {
    const handleError = (error) => {
      server.off("listening", handleListening);
      reject(error);
    };
    const handleListening = () => {
      server.off("error", handleError);
      resolve();
    };
    server.once("error", handleError);
    server.once("listening", handleListening);
    server.listen(port, host);
  });
}

const config = await loadConfig();
const runtime = new AgentRuntime(config);
const server = await createAppServer({ config, runtime });

try {
  await listen(server, config.port, config.host);
} catch (error) {
  console.error(`Unable to start Crisp Agent: ${error.message}`);
  process.exitCode = 1;
  throw error;
}

const address = server.address();
const port = typeof address === "object" && address ? address.port : config.port;
const protocol = config.httpsCertPath ? "https" : "http";
const hosts = getReachableHosts(config);

console.log("\nCrisp iPhone Agent is running.");
for (const host of hosts) {
  console.log(`  Open on iPhone: ${protocol}://${host}:${port}/#token=${config.pairingToken}`);
}
if (hosts.length === 0) {
  console.log(`  Open locally: ${protocol}://127.0.0.1:${port}/#token=${config.pairingToken}`);
}
console.log(`  Skill: ${config.skillDirectory}`);
console.log(`  Model: ${config.model}`);
if (!config.httpsCertPath) {
  console.log("  Security: trusted LAN only; configure HTTPS before using an untrusted network.");
}
console.log("");

void runtime.start().catch((error) => {
  console.error(`Copilot runtime is not ready: ${error.message}`);
  console.error("Run `copilot login`, then restart this server.");
});

let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  server.close();
  const forceExit = setTimeout(() => process.exit(1), 10_000);
  forceExit.unref();
  await runtime.stop().catch((error) => {
    console.error(`Agent shutdown failed: ${error.message}`);
  });
  clearTimeout(forceExit);
}

process.once("SIGINT", () => {
  void shutdown();
});
process.once("SIGTERM", () => {
  void shutdown();
});
