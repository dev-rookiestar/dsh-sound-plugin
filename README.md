# dsh-sound-plugin

[中文](README.zh-CN.md) | English

> Want to do something else while DeepSeek Harness works for you? Just install this plugin — it calls you back with a system sound the moment it needs you.

A [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) plugin that plays a system sound when:

- the AI **finishes responding** (completion sound), and/or
- a **pending approval** or **user question** appears (approval reminder).

Each is an independent toggle in **Settings → General**.

## Install

```bash
# GitHub shorthand
dsh plugin --profile <name> add github:rookie/dsh-sound-plugin

# or full git URL
dsh plugin --profile <name> add git+https://github.com/rookie/dsh-sound-plugin.git
```

Replace `<name>` with your profile name:

- **Desktop** app: `desktop` (quit the app first — its profile is managed exclusively by the Electron application).
- **Web** app: `web`.
- Or any custom name, e.g. `my-profile`.

Then restart DSH (or reload the profile) and open **Settings → General** to see the two toggles.

## What is a profile?

A **profile** is a named, independent environment with its own plugins and settings — like a browser profile (each has its own extensions). Profiles live under `~/.dsh/profiles/<name>`.

Installing with `--profile <name>` adds the plugin to that environment only, so different profiles can hold different plugin sets without interfering.

## Requirements

- DeepSeek Harness `>=0.2.0 <0.3.0` (developed and tested on `0.2.1-rc.3`).
- Sound playback uses a system command:
  - **Windows**: PowerShell (`System.Media.SoundPlayer`) — built in.
  - **macOS**: `afplay` — built in.
  - **Linux**: `paplay` (PulseAudio / PipeWire). Install `pulseaudio-utils` if `paplay` is missing.

## How it works

- **Completion sound**: listens to `agent/status` and plays once after every agent (the main turn plus any subagents) has gone idle.
- **Approval reminder**: listens to the session event feed for `approval/asked` and `ask_user_question` tool calls.
- The "ding-dong" WAV is generated in memory (no bundled audio file) and played through the default audio device.

## License

[MIT](LICENSE)
