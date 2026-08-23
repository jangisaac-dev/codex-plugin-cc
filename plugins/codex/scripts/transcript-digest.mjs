// Condense a Claude Code transcript JSONL into plain text an external model can read.
// Codex imports the raw session itself; this is for backends that only take a prompt.
import fs from "node:fs";

const MAX_TOOL_CHARS = 400;
const MAX_TEXT_CHARS = 4000;
const MAX_TOTAL_CHARS = 120000;

const sourcePath = process.argv[2];
if (!sourcePath) {
  process.stderr.write("usage: transcript-digest.mjs <transcript.jsonl>\n");
  process.exit(1);
}

function clip(value, limit) {
  const text = typeof value === "string" ? value : JSON.stringify(value ?? "");
  if (text.length <= limit) {
    return text;
  }
  return `${text.slice(0, limit)}… [${text.length - limit} more chars]`;
}

const lines = [];
for (const raw of fs.readFileSync(sourcePath, "utf8").split("\n")) {
  if (!raw.trim()) {
    continue;
  }
  let entry;
  try {
    entry = JSON.parse(raw);
  } catch {
    continue;
  }
  const role = entry?.message?.role;
  if (role !== "user" && role !== "assistant") {
    continue;
  }
  const content = entry.message.content;
  const blocks = Array.isArray(content) ? content : [{ type: "text", text: content }];
  for (const block of blocks) {
    if (block?.type === "text" && block.text?.trim()) {
      lines.push(`[${role}] ${clip(block.text.trim(), MAX_TEXT_CHARS)}`);
    } else if (block?.type === "thinking" && block.thinking?.trim()) {
      lines.push(`[${role} thinking] ${clip(block.thinking.trim(), MAX_TEXT_CHARS)}`);
    } else if (block?.type === "tool_use") {
      lines.push(`[tool ${block.name}] ${clip(block.input, MAX_TOOL_CHARS)}`);
    } else if (block?.type === "tool_result") {
      lines.push(`[tool result] ${clip(block.content, MAX_TOOL_CHARS)}`);
    }
  }
}

let digest = lines.join("\n");
if (digest.length > MAX_TOTAL_CHARS) {
  digest = `[earlier turns dropped to fit the size limit]\n${digest.slice(-MAX_TOTAL_CHARS)}`;
}
process.stdout.write(digest);
