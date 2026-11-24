import { execFile } from "node:child_process";
import { promisify, stripVTControlCharacters } from "node:util";

const run = promisify(execFile);
const keywordLimit = 64;
const contextLimit = 6000;
const sensitive =
  /(?:\b[\w-]*(?:api[_-]?key|token|password|secret)["']?\s*[:=]|\bBearer\s+\S+|\b(?:sk-|gh[pousr]_|github_pat_|xox[baprs]-)\S+|\b[A-Za-z0-9/+_-]{40,}={0,2}\b|-----(?:BEGIN|END) .*PRIVATE KEY-----)/i;

export async function herdrKeywords(key, sessionSignal) {
  const timeout = AbortSignal.timeout(3000);
  const signal = AbortSignal.any([sessionSignal, timeout]);
  const options = { signal, maxBuffer: 1024 * 1024 };
  try {
    const window = await run("niri", ["msg", "--json", "focused-window"], options)
      .then(({ stdout }) => JSON.parse(stdout))
      .catch(() => {
        throw new Error("Could not check the focused app");
      });
    if (window?.app_id !== "herdr-app") {
      return [];
    }

    const context = await readViewport(options).catch(() => {
      throw new Error("Could not read the focused Herdr viewport");
    });
    const apiKey = await key;
    if (!apiKey) {
      throw new Error("OpenAI key unavailable in the keyring");
    }
    return await selectKeywords(context, apiKey, signal).catch(() => {
      throw new Error("Could not get dictation keywords from Luna");
    });
  } catch (error) {
    if (timeout.aborted) {
      throw new Error("Herdr dictation context timed out");
    }
    throw error;
  }
}

async function readViewport(options) {
  const { stdout: status } = await run("herdr-app", ["status"], options);
  const { focused_pane: pane } = JSON.parse(status);
  if (!pane) {
    throw new Error("No focused Herdr pane");
  }

  const { stdout: layout } = await run("herdr-app", ["ls"], options);
  const terminals = JSON.parse(layout).spaces.flatMap((space) =>
    space.tabs.flatMap((tab) => tab.terminals),
  );
  const terminal = terminals.find((item) => item.pane === pane)?.terminal;
  if (!terminal) {
    throw new Error("No terminal for the focused Herdr pane");
  }

  const { stdout: viewport } = await run("hc", ["read", "--lines", "0", terminal], options);
  const context = stripVTControlCharacters(viewport)
    .split("\n")
    .filter((line) => !sensitive.test(line))
    .map((line) => line.replace(/https?:\/\/\S+/g, "[URL]").trimEnd())
    .join("\n")
    .trim()
    .slice(-contextLimit);
  if (!context) {
    throw new Error("No usable viewport text");
  }
  return context;
}

async function selectKeywords(context, apiKey, signal) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: "Bearer " + apiKey, "Content-Type": "application/json" },
    signal,
    body: JSON.stringify({
      model: "gpt-6-luna",
      reasoning: { effort: "none" },
      store: false,
      max_output_tokens: 1024,
      instructions: `You’re selecting vocabulary hints for an English and Spanish desktop dictation app. Pick up to ${keywordLimit} terms from the provided context that the user might say and the transcriber might mishear.`,
      input: context,
      text: {
        format: {
          type: "json_schema",
          name: "dictation_vocabulary",
          strict: true,
          schema: {
            type: "object",
            properties: {
              keywords: { type: "array", items: { type: "string" }, maxItems: keywordLimit },
            },
            required: ["keywords"],
            additionalProperties: false,
          },
        },
      },
    }),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error("Luna request failed");
  }

  const result = await response.json();
  if (result.status !== "completed") {
    throw new Error("Luna response did not complete");
  }
  const output = result.output
    ?.flatMap((item) => item.content ?? [])
    .find((item) => item.type === "output_text");
  if (!output) {
    throw new Error("Luna returned no structured output");
  }

  const { keywords } = JSON.parse(output.text);
  if (
    !Array.isArray(keywords) ||
    keywords.length > keywordLimit ||
    keywords.some((keyword) => typeof keyword !== "string")
  ) {
    throw new Error("Luna returned an invalid keyword list");
  }
  return [
    ...new Set(
      keywords
        .map((keyword) => keyword.trim())
        .filter(
          (keyword) =>
            keyword &&
            context.includes(keyword) &&
            !/[<>\p{Cc}]/u.test(keyword) &&
            !sensitive.test(keyword),
        ),
    ),
  ];
}
