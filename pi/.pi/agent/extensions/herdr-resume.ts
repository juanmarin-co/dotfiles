// herdr-resume: Pi extension that records and clears the session on hc terminal labels.

import { spawn } from "node:child_process";

const SIGNALS = ["SIGTERM", "SIGHUP"];

function runHerdrResume(subcmd: string, payload?: unknown): Promise<void> {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn("herdr-resume", [subcmd, "--agent", "pi"], {
        stdio: ["pipe", "ignore", "ignore"],
      });
    } catch {
      resolve();
      return;
    }

    const timer = setTimeout(() => {
      child.kill();
    }, 5000);
    const done = () => {
      clearTimeout(timer);
      resolve();
    };
    child.on("error", done);
    child.on("close", done);
    child.stdin.on("error", () => {});
    if (payload !== undefined) {
      child.stdin.end(JSON.stringify(payload));
    } else {
      child.stdin.end();
    }
  });
}

export default function (pi: any) {
  if (!process.env.HC_TERMINAL_ID) {
    return;
  }

  let queue: Promise<void> = Promise.resolve();
  let signalled = false;
  let listening = false;
  const onSignal = () => {
    signalled = true;
  };

  function listenSignals() {
    if (listening) {
      return;
    }
    for (const sig of SIGNALS) {
      process.on(sig, onSignal);
    }
    listening = true;
  }

  async function wasSignalled(): Promise<boolean> {
    await new Promise((r) => {
      setImmediate(r);
    });
    if (listening) {
      for (const sig of SIGNALS) {
        process.off(sig, onSignal);
      }
      listening = false;
    }
    return signalled;
  }

  pi.on("session_start", (event: any, ctx: any) => {
    if (ctx.mode !== "tui") {
      return;
    }
    const transcript = ctx.sessionManager.getSessionFile();
    if (!transcript) {
      return;
    }
    listenSignals();
    const payload = {
      hook_event_name: "SessionStart",
      source: event.reason,
      session_id: ctx.sessionManager.getSessionId(),
      transcript_path: transcript,
      cwd: ctx.cwd,
      argv: ["pi", ...process.argv.slice(2)],
    };
    queue = queue.then(() => {
      return runHerdrResume("hook", payload);
    });
  });

  pi.on("session_shutdown", async (event: any, ctx: any) => {
    if (ctx.mode !== "tui") {
      return;
    }
    const gotSignal = await wasSignalled();
    if (event.reason !== "quit" || gotSignal) {
      return queue;
    }
    queue = queue.then(() => {
      return runHerdrResume("clear");
    });
    return queue;
  });
}
