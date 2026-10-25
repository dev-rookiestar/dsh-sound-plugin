# dsh-sound-plugin

中文 | [English](README.md)

> 如何在 DeepSeek Harness 工作时去做别的事？你只需要这款插件——在它需要你的时候，用一声系统提示音把你召回。

一个 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 插件，在以下场景播放系统提示音：

- AI **回复完成**时（完成提示音）；
- 出现**待审批事项**或**用户提问**时（待审批提醒）。

每个功能都是 **设置 → 通用** 里的一个独立开关。

## 安装

```bash
# GitHub 简写
dsh plugin --profile <name> add github:rookie/dsh-sound-plugin

# 或完整 git 地址
dsh plugin --profile <name> add git+https://github.com/rookie/dsh-sound-plugin.git
```

把 `<name>` 换成你的 profile 名：

- **桌面版**：`desktop`（需先完全退出桌面应用——其 profile 由 Electron 应用独占管理）。
- **Web 版**：`web`。
- 或任意自定义名字，如 `my-profile`。

然后重启 DSH（或重载 profile），打开 **设置 → 通用** 即可看到两个开关。

## 系统要求

- DeepSeek Harness `>=0.2.0 <0.3.0`（在 `0.2.1-rc.3` 上开发并测试）。
- 声音播放依赖系统命令：
  - **Windows**：PowerShell（`System.Media.SoundPlayer`）—— 系统内置。
  - **macOS**：`afplay` —— 系统内置。
  - **Linux**：`paplay`（PulseAudio / PipeWire）。若缺失请安装 `pulseaudio-utils`。

## 工作原理

- **完成提示音**：监听 `agent/status`，在所有 agent（主回合 + 子代理）都空闲后播放一次。
- **待审批提醒**：监听会话事件流中的 `approval/asked` 和 `ask_user_question` 工具调用。
- "叮咚" WAV 在内存中生成（不附带音频文件），通过默认音频设备播放。

## 许可证

[MIT](LICENSE)
