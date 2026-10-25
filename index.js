import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import z from "@deepseek-ai/schemastery";

const __dirname = dirname(fileURLToPath(import.meta.url));

export const Config = z.object({
  completion: z.boolean().default(true).volatile(),
  approval: z.boolean().default(true).volatile(),
});

function fieldEnabled(config, field) {
  const value = config?.[field];
  if (value && typeof value.get === "function") return value.get();
  return value;
}

// Build a short two-tone "ding-dong" WAV (mono, 16-bit PCM, 22050 Hz).
// Pure Node Buffer math, so it works on every platform.
function buildDingWav() {
  const rate = 22050;
  const tones = [
    [880, 0.16], // A5
    [1174.66, 0.2], // D6
  ];
  const samples = [];
  for (const [freq, dur] of tones) {
    const n = Math.floor(rate * dur);
    for (let i = 0; i < n; i++) {
      const t = i / rate;
      const attack = Math.min(1, t / 0.008);
      const decay = Math.pow(1 - i / n, 1.5);
      samples.push(Math.sin(2 * Math.PI * freq * t) * attack * decay);
    }
  }
  const dataSize = samples.length * 2;
  const buf = Buffer.alloc(44 + dataSize);
  buf.write("RIFF", 0);
  buf.writeUInt32LE(36 + dataSize, 4);
  buf.write("WAVE", 8);
  buf.write("fmt ", 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * 2, 28);
  buf.writeUInt16LE(2, 32);
  buf.writeUInt16LE(16, 34);
  buf.write("data", 36);
  buf.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < samples.length; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    buf.writeInt16LE(Math.round(v * 31000), 44 + i * 2);
  }
  return buf;
}

// Resolve the platform command that plays a .wav file through the default
// audio device. Only playback differs per platform; the WAV itself is the same.
function playbackCommand(wavPath) {
  switch (process.platform) {
    case "win32": {
      const scriptPath = join(__dirname, "wasapi-play.ps1");
      return {
        command: "powershell.exe",
        args: [
          "-NoProfile",
          "-NonInteractive",
          "-ExecutionPolicy",
          "Bypass",
          "-WindowStyle",
          "Hidden",
          "-File",
          scriptPath,
          "-Path",
          wavPath,
        ],
        options: { windowsHide: true },
      };
    }
    case "darwin":
      return { command: "afplay", args: [wavPath], options: {} };
    default:
      // PulseAudio / PipeWire; on ALSA-only systems install pulseaudio-utils or
      // swap this for `aplay`.
      return { command: "paplay", args: [wavPath], options: {} };
  }
}

export function apply(ctx, config) {
  ctx.inject(["settings"], (child) => {
    child.effect(() => child.settings.configure({ auto: false }, ctx.fiber));
  });

  const warn = (message) => {
    try {
      ctx.logger?.warn?.(message);
    } catch {
      console.error(message);
    }
  };

  let dingPath;
  function playSystemSound() {
    try {
      if (dingPath === undefined) {
        dingPath = join(tmpdir(), "dsh-completion-sound-ding.wav");
        writeFileSync(dingPath, buildDingWav());
      }
      const { command, args, options } = playbackCommand(dingPath);
      const child = spawn(command, args, { stdio: "ignore", ...options });
      child.unref();
      child.on("error", (error) =>
        warn(`completion-sound: play failed (${command}): ${error.message}`),
      );
    } catch (error) {
      warn(`completion-sound: play error: ${String(error)}`);
    }
  }

  const maybePlay = (field) => {
    if (fieldEnabled(config, field) !== false) playSystemSound();
  };

  // Completion sound: inject the `agents` service, then play when a root
  // (main) agent goes idle — its whole turn, including any subagents, has
  // then finished. Tracking only roots avoids a stale-agent leak that could
  // permanently stop the sound.
  ctx.inject(["agents"], (child) => {
    ctx.on(
      "agent/status",
      ({ agent, status }) => {
        if (status !== "idle") return;
        const roots = child.agents.roots();
        if (roots.some((root) => root.id === agent.id)) {
          maybePlay("completion");
        }
      },
      { global: true },
    );
  });

  // Approval reminder: play when a permission approval or a user question is
  // asked. Detected from the durable session event feed, which reaches a
  // global listener reliably on every platform.
  ctx.on(
    "session/event",
    (_session, event) => {
      if (event.type === "approval/asked") {
        maybePlay("approval");
      } else if (
        event.type === "tool/call" &&
        event.data?.name === "ask_user_question"
      ) {
        maybePlay("approval");
      }
    },
    { global: true },
  );
}
