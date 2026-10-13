// Alt text. The host shows the image picker and inlines the file the user
// chose before this request reaches the AI provider. One turn, then a bubble.

const LANGUAGE = {
  "zh-Hans": "Simplified Chinese",
  en: "English",
  ja: "Japanese"
};

const DEFAULT_PROMPT = "生成图片的 alt text，简洁一些";

export function run(params) {
  const prior = (params.inputResponses && params.inputResponses.completion) || null;
  if (prior) {
    if (prior.error) {
      const message = prior.error.message || say(params, "Couldn't write alt text.", "无法生成替代文本。");
      return bubble("failure", message);
    }
    const text = String(prior.text || "").trim();
    if (!text) return bubble("failure", say(params, "The model returned no text.", "模型没有返回文本。"));
    return bubble("success", text);
  }

  const input = params.input || {};
  const image = input.image;
  if (!image || (typeof image === "string" && !String(image).trim())) {
    return bubble("warning", say(params, "Choose an image.", "请选择一张图片。"));
  }

  const settings = params.settings || {};
  const prompt = String(settings.prompt || "").trim() || DEFAULT_PROMPT;
  const language = LANGUAGE[settings.language] || LANGUAGE["zh-Hans"];
  return {
    resultType: "input_required",
    inputRequests: {
      completion: {
        method: "aibo/llm",
        params: {
          system:
            "You write alt text for images. Follow the user's instructions. " +
            "Reply in " +
            language +
            " only, with the alt text and nothing else.",
          messages: [{ role: "user", text: prompt, image: image }],
          maxTokens: 512
        }
      }
    },
    requestState: ""
  };
}

function bubble(outcome, summary) {
  const item = { type: "bubble", outcome: outcome, summary: summary };
  if (outcome === "success") item.actions = [{ title: "Copy", copy: summary }];
  return { resultType: "complete", content: [item] };
}

function say(params, en, zh) {
  return String((params && params.locale) || "").indexOf("zh") === 0 ? zh : en;
}
