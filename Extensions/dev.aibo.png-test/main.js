// Throwaway. Confirms a dropped PNG reached this plugin. Delete the folder when done.

export function run(params) {
  const image = String((params.input && params.input.image) || "").trim();
  if (!image) {
    return bubble("warning", "请拖入一张 PNG。");
  }
  const name = image.split("/").pop();
  return bubble("success", "收到 " + name);
}

function bubble(outcome, summary) {
  return {
    resultType: "complete",
    content: [{ type: "bubble", outcome: outcome, summary: summary }]
  };
}
