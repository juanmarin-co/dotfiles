import { execFile, spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { promisify } from "node:util";

const run = promisify(execFile);
const rate = 24000;
const frameBytes = rate * 2 * 0.04;
const pauseMs = 500;
const turns = new Map();
const queuedAudio = [];
const input = createInterface({ input: process.stdin });
const keyLookup = new AbortController();
let socket;
let recorder;
let keyboard;
let deadline;
let microphoneDeadline;
let settleTimer;
let speechItem;
let audio = Buffer.alloc(0);
let hasAudio = false;
let connected = false;
let typed = false;
let stopping = false;
let settled = false;
let done = false;

function report(event) {
  process.stdout.write(JSON.stringify(event) + "\n");
}

function finish(message) {
  if (done) {
    return;
  }
  done = true;
  clearTimeout(deadline);
  clearTimeout(microphoneDeadline);
  clearTimeout(settleTimer);
  keyLookup.abort();
  recorder?.kill();
  keyboard?.kill();
  socket?.close();
  input.close();
  process.stdin.destroy();
  if (message) {
    process.exitCode = 1;
    report({ type: "error", message });
  }
}

function send(type, fields = {}) {
  socket.send(JSON.stringify({ type, ...fields }));
}

function append(pcm) {
  send("input_audio_buffer.append", { audio: pcm.toString("base64") });
}

function maybeFinish() {
  if (settled && !speechItem && turns.size === 0 && !keyboard) {
    finish();
  }
}

function stop() {
  if (done || stopping) {
    return;
  }
  stopping = true;
  clearTimeout(microphoneDeadline);
  recorder?.kill();
  if (!hasAudio) {
    finish();
    return;
  }
  if (connected) {
    flushFinalAudio();
  }
}

function flushFinalAudio() {
  clearTimeout(deadline);
  deadline = setTimeout(() => finish("Timed out finishing dictation"), 12000);
  if (audio.length >= 2) {
    append(audio.subarray(0, audio.length - (audio.length % 2)));
  }
  // Give server VAD a trailing pause so it commits any unfinished speech.
  append(Buffer.alloc((rate * 2 * (pauseMs + 200)) / 1000));
  settleTimer = setTimeout(() => {
    settled = true;
    maybeFinish();
  }, 1200);
}

function captureAudio(chunk) {
  if (done || stopping) {
    return;
  }
  // Allow the startup backlog plus five seconds of additional queued audio.
  if (connected && socket.bufferedAmount > (rate * 2 * 15 * 4) / 3) {
    finish("Dictation connection is too slow");
    return;
  }
  audio = Buffer.concat([audio, chunk]);
  hasAudio ||= audio.length >= 2;
  while (audio.length >= frameBytes) {
    const frame = audio.subarray(0, frameBytes);
    audio = audio.subarray(frameBytes);
    if (connected) {
      append(frame);
    } else {
      queuedAudio.push(frame);
    }
    let low = 0;
    let high = 0;
    for (let i = 0; i < frame.length; i += 2) {
      const sample = frame.readInt16LE(i) / 32768;
      low = Math.min(low, sample);
      high = Math.max(high, sample);
    }
    report({ type: "waveform", range: [low, high] });
  }
  clearTimeout(microphoneDeadline);
  microphoneDeadline = setTimeout(() => finish("Microphone stopped sending audio"), 5000);
}

function typeNext() {
  if (done || keyboard) {
    return;
  }
  for (const [id, transcript] of turns) {
    if (transcript === null) {
      return;
    }
    turns.delete(id);
    // wtype maps newlines, tabs and escape characters to key actions.
    let text = transcript.replace(/[\s\p{Cc}]+/gu, " ").trim();
    if (!text) {
      continue;
    }
    if (typed) {
      text = " " + text;
    }
    keyboard = spawn("wtype", ["-"], { stdio: ["pipe", "ignore", "ignore"] });
    keyboard.on("error", () => finish("Could not start wtype"));
    keyboard.stdin.on("error", () => finish("Could not send text to wtype"));
    keyboard.stdin.end(text);
    keyboard.on("close", (code) => {
      keyboard = undefined;
      if (code === 0) {
        typed = true;
        typeNext();
      } else {
        finish("wtype could not type the transcript");
      }
    });
    return;
  }
  maybeFinish();
}

function handleEvent(event) {
  if (done) {
    return;
  }
  switch (event.type) {
    case "session.updated":
      clearTimeout(deadline);
      connected = true;
      if (queuedAudio.length > 0) {
        append(Buffer.concat(queuedAudio));
        queuedAudio.length = 0;
      }
      if (stopping) {
        flushFinalAudio();
      }
      break;
    case "input_audio_buffer.speech_started":
      speechItem = event.item_id;
      break;
    case "input_audio_buffer.committed":
      if (event.item_id === speechItem) {
        speechItem = undefined;
      }
      turns.set(event.item_id, null);
      break;
    case "conversation.item.input_audio_transcription.completed":
      if (turns.has(event.item_id)) {
        turns.set(event.item_id, event.transcript);
        typeNext();
      }
      break;
    case "conversation.item.input_audio_transcription.failed":
      finish("OpenAI could not transcribe the audio");
      break;
    case "error":
      finish("OpenAI rejected the dictation request");
      break;
  }
}

input.on("line", (line) => {
  if (line === "stop") {
    stop();
  }
});
input.on("close", () => finish());
process.on("SIGTERM", () => finish());
process.on("SIGINT", () => finish());
process.stdout.on("error", () => finish());

deadline = setTimeout(() => finish("Timed out connecting to OpenAI"), 10000);
microphoneDeadline = setTimeout(() => finish("Microphone did not send audio"), 5000);
recorder = spawn(
  "pw-record",
  ["--raw", "--rate", String(rate), "--channels", "1", "--format", "s16", "--latency", "40ms", "-"],
  { stdio: ["ignore", "pipe", "ignore"] },
);
recorder.stdout.on("data", captureAudio);
recorder.on("error", () => finish("Could not start microphone recording"));
recorder.on("close", () => {
  recorder = undefined;
  if (!stopping) {
    finish("Microphone recording stopped");
  }
});

const { stdout } = await run(
  "secret-tool",
  ["lookup", "service", "openai", "purpose", "dictation"],
  { signal: keyLookup.signal },
).catch(() => ({ stdout: "" }));
const key = stdout.trim();
if (!done && !key) {
  finish("OpenAI key unavailable in the keyring");
}

if (!done) {
  socket = new WebSocket("wss://api.openai.com/v1/realtime?intent=transcription", {
    headers: { Authorization: "Bearer " + key },
  });
  socket.addEventListener("open", () =>
    send("session.update", {
      session: {
        type: "transcription",
        audio: {
          input: {
            format: { type: "audio/pcm", rate },
            transcription: { model: "gpt-transcribe", languages: ["en", "es"] },
            turn_detection: { type: "server_vad", silence_duration_ms: pauseMs },
          },
        },
      },
    }),
  );
  socket.addEventListener("message", ({ data }) => handleEvent(JSON.parse(data)));
  socket.addEventListener("error", () => finish("Could not connect to OpenAI"));
  socket.addEventListener("close", () => finish("OpenAI connection closed"));
}
