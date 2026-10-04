// AI provider. Other plugins ask the host for `aibo/llm`; the host runs this file
// with that request as `input`. This plugin never holds the socket itself:
// it returns `aibo/fetch`, then reads the response on the next round.

const OPENAI_DEFAULT = "https://api.openai.com/v1";
const GOOGLE_DEFAULT = "https://generativelanguage.googleapis.com/v1beta";

export function run(params) {
  const settings = params.settings || {};
  const prior = (params.inputResponses && params.inputResponses.http) || null;
  if (prior) {
    if (prior.error) {
      return completeError(prior.error.message || say(params, "Request failed", "请求失败"));
    }
    const parsed = extract(settings.format, prior.body || "", params);
    if (parsed.error) return completeError(parsed.error);
    return { resultType: "complete", output: { text: parsed.text } };
  }

  const missing = missingField(settings, params);
  if (missing) return completeError(missing);

  const built = buildRequest(settings, params.input || {});
  if (built.error) return completeError(built.error);
  return {
    resultType: "input_required",
    inputRequests: {
      http: { method: "aibo/fetch", params: built }
    },
    requestState: ""
  };
}

function missingField(settings, params) {
  if (!settings.apiKey) return say(params, "Add an API key in the AI provider settings.", "请先在 AI 供应商设置里填写 API 密钥。");
  if (!settings.model) return say(params, "Choose a model in the AI provider settings.", "请先在 AI 供应商设置里填写模型。");
  return "";
}

function buildRequest(settings, input) {
  const format = settings.format || "chat-completions";
  const base = resolvedBase(settings, format);
  const maxTokens = Math.min(Number(input.maxTokens) || 1024, 1024);
  if (format === "google-interactions") {
    return {
      url: join(base, "/interactions"),
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": settings.apiKey
      },
      body: JSON.stringify({
        model: settings.model,
        input: userText(input),
        system_instruction: input.system || "",
        store: false
      })
    };
  }
  return {
    url: chatURL(base),
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer " + settings.apiKey
    },
    body: JSON.stringify({
      model: settings.model,
      messages: chatMessages(input),
      max_tokens: maxTokens
    })
  };
}

function resolvedBase(settings, format) {
  const base = String(settings.baseURL || "").trim().replace(/\/+$/, "");
  if (format === "google-interactions") {
    if (!base || base === OPENAI_DEFAULT) return GOOGLE_DEFAULT;
    return base;
  }
  return base || OPENAI_DEFAULT;
}

function chatURL(base) {
  if (base.endsWith("/chat/completions")) return base;
  return base + "/chat/completions";
}

function join(base, path) {
  if (base.endsWith(path)) return base;
  return base + path;
}

function chatMessages(input) {
  const messages = [];
  if (input.system) messages.push({ role: "system", content: input.system });
  const rows = input.messages || [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i] || {};
    messages.push({
      role: row.role || "user",
      content: row.text || row.content || ""
    });
  }
  return messages;
}

function userText(input) {
  const rows = input.messages || [];
  const parts = [];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i] || {};
    const text = row.text || row.content || "";
    if (text) parts.push(text);
  }
  return parts.join("\n\n");
}

function extract(format, body, params) {
  let json;
  try {
    json = JSON.parse(body);
  } catch (error) {
    return { error: say(params, "The model response was not JSON.", "模型返回的不是 JSON。") };
  }
  if (json && json.error) {
    return { error: (json.error && json.error.message) || say(params, "Request failed", "请求失败") };
  }
  if (format === "google-interactions") return interactionsText(json, params);
  return chatText(json, params);
}

function chatText(json, params) {
  const choice = json.choices && json.choices[0];
  const message = choice && choice.message;
  const content = message && message.content;
  if (typeof content === "string" && content.trim()) return { text: content.trim() };
  if (Array.isArray(content)) {
    let text = "";
    for (let i = 0; i < content.length; i++) {
      const part = content[i];
      if (part && part.text) text += part.text;
    }
    if (text.trim()) return { text: text.trim() };
  }
  return { error: say(params, "The model returned no text.", "模型没有返回文本。") };
}

function interactionsText(json, params) {
  if (json.status && json.status !== "completed" && json.status !== "incomplete") {
    return { error: "Interaction status: " + json.status };
  }
  const steps = json.steps || [];
  let text = "";
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    if (!step || step.type !== "model_output") continue;
    const content = step.content || [];
    for (let j = 0; j < content.length; j++) {
      const part = content[j];
      if (part && part.type === "text" && part.text) text += part.text;
    }
  }
  if (!text.trim()) return { error: say(params, "The model returned no text.", "模型没有返回文本。") };
  return { text: text.trim() };
}

function say(params, en, zh) {
  return String((params && params.locale) || "").indexOf("zh") === 0 ? zh : en;
}

function completeError(message) {
  return { resultType: "complete", output: { error: { message: message } } };
}
