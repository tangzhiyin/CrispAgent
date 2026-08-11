const STORAGE_KEYS = {
  token: "crisp-agent.token",
  conversationId: "crisp-agent.conversation-id",
  messages: "crisp-agent.messages",
};

const elements = {
  conversation: document.querySelector("#conversation"),
  messages: document.querySelector("#messages"),
  welcome: document.querySelector("#welcome"),
  composer: document.querySelector("#composer"),
  input: document.querySelector("#message-input"),
  sendButton: document.querySelector("#send-button"),
  voiceButton: document.querySelector("#voice-button"),
  newChatButton: document.querySelector("#new-chat-button"),
  typingIndicator: document.querySelector("#typing-indicator"),
  typingStatus: document.querySelector("#typing-status"),
  statusButton: document.querySelector("#status-button"),
  statusDot: document.querySelector("#status-dot"),
  statusText: document.querySelector("#status-text"),
  settingsDialog: document.querySelector("#settings-dialog"),
  settingsToken: document.querySelector("#settings-token"),
  saveTokenButton: document.querySelector("#save-token-button"),
  runtimeValue: document.querySelector("#runtime-value"),
  modelValue: document.querySelector("#model-value"),
  skillValue: document.querySelector("#skill-value"),
  fingerprintValue: document.querySelector("#fingerprint-value"),
  clearChatButton: document.querySelector("#clear-chat-button"),
  disconnectButton: document.querySelector("#disconnect-button"),
  pairingDialog: document.querySelector("#pairing-dialog"),
  pairingToken: document.querySelector("#pairing-token"),
  pairButton: document.querySelector("#pair-button"),
  pairingError: document.querySelector("#pairing-error"),
  toast: document.querySelector("#toast"),
};

function createConversationId() {
  if (typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }

  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((value) => value.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const state = {
  token: readStorage(STORAGE_KEYS.token) || "",
  conversationId: readStorage(STORAGE_KEYS.conversationId) || createConversationId(),
  messages: readMessages(),
  generating: false,
  requestController: undefined,
  recognition: undefined,
  toastTimer: undefined,
};

function readStorage(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStorage(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // The current session still works when persistent browser storage is unavailable.
  }
}

function removeStorage(key) {
  try {
    localStorage.removeItem(key);
  } catch {
    // Nothing else is needed when storage is unavailable.
  }
}

function readMessages() {
  try {
    const parsed = JSON.parse(readStorage(STORAGE_KEYS.messages) || "[]");
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed
      .filter(
        (message) =>
          message &&
          ["user", "assistant"].includes(message.role) &&
          typeof message.content === "string",
      )
      .slice(-50);
  } catch {
    return [];
  }
}

function saveConversation() {
  writeStorage(STORAGE_KEYS.conversationId, state.conversationId);
  writeStorage(STORAGE_KEYS.messages, JSON.stringify(state.messages.slice(-50)));
}

function tokenHeaders(token = state.token) {
  return {
    Authorization: `Bearer ${token}`,
  };
}

function setConnectionState(connectionState, label) {
  elements.statusDot.dataset.state = connectionState;
  elements.statusText.textContent = label;
}

function showToast(message) {
  clearTimeout(state.toastTimer);
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  state.toastTimer = setTimeout(() => {
    elements.toast.hidden = true;
  }, 2200);
}

async function copyText(content) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(content);
    return;
  }

  const textarea = document.createElement("textarea");
  textarea.value = content;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.append(textarea);
  textarea.select();
  const copied = document.execCommand("copy");
  textarea.remove();
  if (!copied) {
    throw new Error("Copy is unavailable.");
  }
}

function scrollToBottom() {
  requestAnimationFrame(() => {
    elements.conversation.scrollTop = elements.conversation.scrollHeight;
  });
}

function appendLinkedText(container, content) {
  const urlPattern = /(https?:\/\/[^\s<]+)/g;
  let cursor = 0;
  for (const match of content.matchAll(urlPattern)) {
    if (match.index > cursor) {
      container.append(document.createTextNode(content.slice(cursor, match.index)));
    }
    const link = document.createElement("a");
    link.href = match[0];
    link.textContent = match[0];
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    container.append(link);
    cursor = match.index + match[0].length;
  }
  if (cursor < content.length) {
    container.append(document.createTextNode(content.slice(cursor)));
  }
}

function createMessageElement(message, { live = false } = {}) {
  const article = document.createElement("article");
  article.className = `message ${message.role}`;

  const bubble = document.createElement("div");
  bubble.className = "message-bubble";
  if (live) {
    bubble.dataset.live = "true";
  }
  appendLinkedText(bubble, message.content);
  article.append(bubble);

  if (message.role === "assistant" && !live) {
    const actions = document.createElement("div");
    actions.className = "message-actions";

    const copyButton = document.createElement("button");
    copyButton.type = "button";
    copyButton.textContent = "复制";
    copyButton.addEventListener("click", async () => {
      try {
        await copyText(message.content);
        showToast("已复制");
      } catch {
        showToast("暂时无法复制");
      }
    });
    actions.append(copyButton);

    if (navigator.share) {
      const shareButton = document.createElement("button");
      shareButton.type = "button";
      shareButton.textContent = "分享";
      shareButton.addEventListener("click", async () => {
        try {
          await navigator.share({ text: message.content });
        } catch (error) {
          if (error.name !== "AbortError") {
            showToast("暂时无法分享");
          }
        }
      });
      actions.append(shareButton);
    }
    article.append(actions);
  }

  return article;
}

function renderMessages() {
  elements.messages.replaceChildren();
  elements.welcome.hidden = state.messages.length > 0;
  for (const message of state.messages) {
    elements.messages.append(createMessageElement(message));
  }
  scrollToBottom();
}

function updateLiveMessage(element, content) {
  const bubble = element.querySelector(".message-bubble");
  bubble.replaceChildren();
  appendLinkedText(bubble, content);
  scrollToBottom();
}

function autoSizeInput() {
  elements.input.style.height = "auto";
  elements.input.style.height = `${Math.min(elements.input.scrollHeight, 130)}px`;
}

function setGenerating(generating, status = "正在思考") {
  state.generating = generating;
  elements.sendButton.classList.toggle("generating", generating);
  elements.sendButton.setAttribute("aria-label", generating ? "停止生成" : "发送");
  elements.input.disabled = generating;
  elements.voiceButton.disabled = generating;
  elements.newChatButton.disabled = generating;
  elements.typingIndicator.hidden = !generating;
  elements.typingStatus.textContent = status;
  scrollToBottom();
}

async function readErrorResponse(response) {
  try {
    const payload = await response.json();
    return payload.message || payload.error || `HTTP ${response.status}`;
  } catch {
    return `HTTP ${response.status}`;
  }
}

async function readEventStream(response, onEvent) {
  if (!response.body) {
    throw new Error("当前浏览器不支持流式响应。");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";

    for (const line of lines) {
      if (line.trim()) {
        onEvent(JSON.parse(line));
      }
    }
    if (done) {
      if (buffer.trim()) {
        onEvent(JSON.parse(buffer));
      }
      return;
    }
  }
}

async function sendMessage(message) {
  const prompt = message.trim();
  if (!prompt || state.generating) {
    return;
  }
  if (!state.token) {
    openPairingDialog();
    return;
  }

  const priorHistory = state.messages.slice(-16);
  state.messages.push({ role: "user", content: prompt });
  saveConversation();
  renderMessages();
  elements.input.value = "";
  autoSizeInput();

  const liveMessage = createMessageElement({ role: "assistant", content: "" }, { live: true });
  elements.messages.append(liveMessage);
  let streamedContent = "";
  let finalContent = "";
  let completed = false;
  let framePending = false;
  state.requestController = new AbortController();
  setGenerating(true);

  try {
    const response = await fetch("/api/chat", {
      method: "POST",
      headers: {
        ...tokenHeaders(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        conversationId: state.conversationId,
        message: prompt,
        history: priorHistory,
      }),
      signal: state.requestController.signal,
    });
    if (!response.ok) {
      throw new Error(await readErrorResponse(response));
    }

    await readEventStream(response, (event) => {
      if (event.type === "status") {
        const labels = {
          "loading-skill": "正在加载你的语气",
          thinking: "正在思考",
        };
        elements.typingStatus.textContent = labels[event.status] || "正在处理";
      } else if (event.type === "delta") {
        streamedContent += event.content;
        if (!framePending) {
          framePending = true;
          requestAnimationFrame(() => {
            framePending = false;
            updateLiveMessage(liveMessage, streamedContent);
          });
        }
      } else if (event.type === "final") {
        finalContent = event.content;
        updateLiveMessage(liveMessage, finalContent);
      } else if (event.type === "done") {
        completed = true;
      } else if (event.type === "error") {
        throw new Error(event.message || "Agent 返回错误。");
      }
    });

    const answer = finalContent || streamedContent;
    if (!completed || !answer.trim()) {
      throw new Error("Agent 没有返回完整结果。");
    }
    state.messages.push({ role: "assistant", content: answer });
    saveConversation();
    renderMessages();
    setConnectionState("online", "已连接");
  } catch (error) {
    liveMessage.remove();
    if (error.name === "AbortError") {
      showToast("已停止生成");
    } else {
      showToast(error.message || "发送失败");
      setConnectionState("error", "连接异常");
      if (/unauthorized|未授权|401/i.test(error.message)) {
        openPairingDialog("Token 无效，请重新配对。");
      }
    }
  } finally {
    state.requestController = undefined;
    setGenerating(false);
    elements.input.focus();
  }
}

async function stopGeneration() {
  if (!state.generating) {
    return;
  }
  state.requestController?.abort();
  void fetch(`/api/conversations/${state.conversationId}/abort`, {
    method: "POST",
    headers: tokenHeaders(),
    keepalive: true,
  }).catch(() => {});
}

async function loadStatus(token = state.token) {
  if (!token) {
    throw new Error("缺少配对 Token。");
  }
  const response = await fetch("/api/status", {
    headers: tokenHeaders(token),
    cache: "no-store",
  });
  if (!response.ok) {
    throw new Error(await readErrorResponse(response));
  }
  const status = await response.json();
  elements.runtimeValue.textContent = status.state || "unknown";
  elements.modelValue.textContent = status.model || "—";
  elements.skillValue.textContent = status.skill?.name || "—";
  elements.fingerprintValue.textContent = status.skill?.fingerprint || "—";

  if (status.state === "ready") {
    setConnectionState("online", "已连接");
  } else if (status.state === "error") {
    setConnectionState("error", "Runtime 错误");
  } else {
    setConnectionState("connecting", "正在启动");
  }
  return status;
}

function openSettings() {
  elements.settingsToken.value = state.token;
  if (!elements.settingsDialog.open) {
    elements.settingsDialog.showModal();
  }
  void loadStatus().catch((error) => {
    elements.runtimeValue.textContent = "error";
    elements.fingerprintValue.textContent = error.message;
  });
}

function openPairingDialog(errorMessage = "") {
  elements.pairingError.textContent = errorMessage;
  elements.pairingToken.value = state.token;
  if (!elements.pairingDialog.open) {
    elements.pairingDialog.showModal();
  }
}

async function pairWithToken(token) {
  const candidate = token.trim();
  if (candidate.length < 16) {
    throw new Error("Token 长度不正确。");
  }
  await loadStatus(candidate);
  state.token = candidate;
  writeStorage(STORAGE_KEYS.token, candidate);
  elements.settingsToken.value = candidate;
  if (elements.pairingDialog.open) {
    elements.pairingDialog.close();
  }
  showToast("配对成功");
}

async function resetConversation({ notifyServer = true } = {}) {
  const previousId = state.conversationId;
  state.conversationId = createConversationId();
  state.messages = [];
  saveConversation();
  renderMessages();
  if (notifyServer && state.token) {
    void fetch(`/api/conversations/${previousId}/delete`, {
      method: "POST",
      headers: tokenHeaders(),
    }).catch(() => {});
  }
}

function configureVoiceInput() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    elements.voiceButton.hidden = true;
    return;
  }

  const recognition = new SpeechRecognition();
  recognition.lang = navigator.language?.startsWith("zh") ? "zh-CN" : navigator.language || "zh-CN";
  recognition.interimResults = true;
  recognition.continuous = false;
  state.recognition = recognition;

  let originalText = "";
  recognition.addEventListener("start", () => {
    originalText = elements.input.value.trim();
    elements.voiceButton.classList.add("listening");
    elements.voiceButton.setAttribute("aria-label", "停止语音输入");
  });
  recognition.addEventListener("result", (event) => {
    let transcript = "";
    for (let index = event.resultIndex; index < event.results.length; index += 1) {
      transcript += event.results[index][0].transcript;
    }
    elements.input.value = [originalText, transcript].filter(Boolean).join(" ");
    autoSizeInput();
  });
  recognition.addEventListener("end", () => {
    elements.voiceButton.classList.remove("listening");
    elements.voiceButton.setAttribute("aria-label", "语音输入");
  });
  recognition.addEventListener("error", (event) => {
    if (event.error !== "aborted" && event.error !== "no-speech") {
      showToast("语音输入需要 HTTPS 或麦克风权限");
    }
  });
}

function consumePairingTokenFromHash() {
  if (!location.hash) {
    return;
  }
  const parameters = new URLSearchParams(location.hash.slice(1));
  const token = parameters.get("token");
  if (token) {
    state.token = token;
    writeStorage(STORAGE_KEYS.token, token);
    history.replaceState(null, "", `${location.pathname}${location.search}`);
  }
}

elements.composer.addEventListener("submit", (event) => {
  event.preventDefault();
  if (state.generating) {
    void stopGeneration();
  } else {
    void sendMessage(elements.input.value);
  }
});

elements.input.addEventListener("input", autoSizeInput);
elements.input.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    elements.composer.requestSubmit();
  }
});

elements.voiceButton.addEventListener("click", () => {
  if (!state.recognition) {
    return;
  }
  if (elements.voiceButton.classList.contains("listening")) {
    state.recognition.stop();
  } else {
    state.recognition.start();
  }
});

elements.newChatButton.addEventListener("click", () => {
  void resetConversation();
});
elements.statusButton.addEventListener("click", openSettings);

document.querySelectorAll("[data-prompt]").forEach((button) => {
  button.addEventListener("click", () => {
    elements.input.value = button.dataset.prompt;
    autoSizeInput();
    elements.input.focus();
  });
});

elements.saveTokenButton.addEventListener("click", async () => {
  elements.saveTokenButton.disabled = true;
  try {
    await pairWithToken(elements.settingsToken.value);
    elements.settingsDialog.close();
  } catch (error) {
    showToast(error.message);
  } finally {
    elements.saveTokenButton.disabled = false;
  }
});

elements.pairButton.addEventListener("click", async () => {
  elements.pairButton.disabled = true;
  elements.pairingError.textContent = "";
  try {
    await pairWithToken(elements.pairingToken.value);
  } catch (error) {
    elements.pairingError.textContent = error.message;
  } finally {
    elements.pairButton.disabled = false;
  }
});

elements.clearChatButton.addEventListener("click", async () => {
  await resetConversation();
  elements.settingsDialog.close();
  showToast("对话已清空");
});

elements.disconnectButton.addEventListener("click", () => {
  state.token = "";
  removeStorage(STORAGE_KEYS.token);
  elements.settingsDialog.close();
  setConnectionState("offline", "未配对");
  openPairingDialog();
});

window.addEventListener("online", () => {
  void loadStatus().catch(() => setConnectionState("error", "连接异常"));
});
window.addEventListener("offline", () => setConnectionState("offline", "网络离线"));

consumePairingTokenFromHash();
configureVoiceInput();
renderMessages();
autoSizeInput();

if ("serviceWorker" in navigator) {
  void navigator.serviceWorker.register("/sw.js").catch(() => {});
}

if (!state.token) {
  setConnectionState("offline", "未配对");
  openPairingDialog();
} else {
  void loadStatus().catch((error) => {
    setConnectionState("error", "连接异常");
    if (/unauthorized|401/i.test(error.message)) {
      openPairingDialog("Token 无效，请重新配对。");
    }
  });
}
