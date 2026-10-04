// Translate. The host shows the prompt form. This file only builds the
// completion request and turns the model reply into a bubble.

const LANGUAGE = {
  "zh-Hans": "Simplified Chinese",
  en: "English",
  ja: "Japanese"
};

export function run(params) {
  const prior = (params.inputResponses && params.inputResponses.completion) || null;
  if (prior) {
    if (prior.error) {
      const message = prior.error.message || say(params, "Translation failed.", "翻译失败。");
      return bubble(message);
    }
    const text = prior.text || "";
    if (!text) return bubble(say(params, "The model returned no text.", "模型没有返回文本。"));
    return {
      resultType: "complete",
      content: [
        {
          type: "bubble",
          summary: text,
          actions: [{ title: "Copy", copy: text }]
        }
      ]
    };
  }

  const input = params.input || {};
  const text = String(input.text || "").trim();
  if (!text) return bubble(say(params, "Enter some text to translate.", "请输入要翻译的文字。"));
  const target = input.target || "en";
  const language = LANGUAGE[target] || target;
  return {
    resultType: "input_required",
    inputRequests: {
      completion: {
        method: "aibo/llm",
        params: {
          system:
            "You are a translator. Translate the user's text into " +
            language +
            ". Reply with the translation only.",
          messages: [{ role: "user", text: text }],
          maxTokens: 1024
        }
      }
    },
    requestState: ""
  };
}

function bubble(summary) {
  return {
    resultType: "complete",
    content: [{ type: "bubble", summary: summary }]
  };
}

function say(params, en, zh) {
  return String((params && params.locale) || "").indexOf("zh") === 0 ? zh : en;
}
