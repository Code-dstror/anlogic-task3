# Ubuntu 22.04 Codex CLI 响应缓慢排障记忆

> 整理日期：2026-09-13
> 环境：VMware Ubuntu 22.04（Jammy）、X11、Clash Verge 2.5.1、Codex CLI 0.154.0
> 用户：`uisrc`
> Clash 本地混合代理：`127.0.0.1:7897`

## 1. 最终结论

Codex CLI 响应超过两分钟的根因不是普通网络速度或模型推理，而是：

1. GNOME 已配置 Clash 系统代理，但当前终端没有 `http_proxy`、`https_proxy`、`HTTP_PROXY`、`HTTPS_PROXY` 等代理环境变量。
2. Codex 的 WebSocket 连接没有稳定进入 Clash，等待超时后才降级到 HTTPS，因此每轮请求额外等待约两分钟。
3. 内置 `codex_apps` 服务也因同一代理问题等待 30 秒并超时。

为 Codex 进程显式提供代理环境变量后：

- WebSocket 不再超时或降级；
- `codex_apps` 不再出现 30 秒启动超时；
- 简单请求可以快速返回；
- 不需要关闭 Apps；
- 不需要启用实验性的 `respect_system_proxy`。

## 2. 主要症状

最小测试提示词：

```text
只回复 OK，不读取文件，不运行命令，也不要进行额外解释。
```

未修复时 Codex 长时间停留在 `Working`，并显示：

```text
Falling back from WebSockets to HTTPS transport: request timed out
```

有时还会显示：

```text
MCP client for `codex_apps` timed out after 30 seconds
MCP startup incomplete (failed: codex_apps)
```

## 3. 排查证据

### 3.1 Codex 版本

```bash
command -v codex
codex --version
```

当时输出：

```text
/home/uisrc/.local/bin/codex
codex-cli 0.154.0
```

### 3.2 普通 HTTPS 链路正常

对 ChatGPT 和 OpenAI API 进行 `curl` 计时，结果约为：

```text
chatgpt: total=0.64s http=403
api:     total=0.88s http=401
```

测试中的 `403` 和 `401` 不表示网络故障：前者是站点访问响应，后者是未携带 API 凭据时的正常未授权响应。关键是 DNS、TCP、TLS 和首字节时间均低于一秒。

### 3.3 GNOME 系统代理存在

```bash
gsettings get org.gnome.system.proxy mode
gsettings get org.gnome.system.proxy.http host
gsettings get org.gnome.system.proxy.http port
gsettings get org.gnome.system.proxy.https host
gsettings get org.gnome.system.proxy.https port
gsettings get org.gnome.system.proxy.socks host
gsettings get org.gnome.system.proxy.socks port
```

有效配置为：

```text
mode: manual
host: 127.0.0.1
port: 7897
```

### 3.4 当前 shell 没有代理变量

最终检查发现以下变量全部为 `unset`：

```text
http_proxy
https_proxy
all_proxy
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
```

这说明 GNOME 图形界面的“系统代理”和 Bash 进程的环境变量不是同一套配置。浏览器或部分程序能够联网，并不代表 Codex 的 WebSocket 客户端一定会读取到代理。

## 4. 最终解决办法

推荐只为 Codex CLI 注入代理，不全局导出代理变量。这样即使 Clash 未启动，也不会连带影响 `apt`、`git`、`curl` 等其他终端程序。

编辑 Bash 配置：

```bash
nano ~/.bashrc
```

在文件末尾加入：

```bash
# Run Codex CLI through Clash Verge
codex() {
    env \
        http_proxy=http://127.0.0.1:7897 \
        https_proxy=http://127.0.0.1:7897 \
        HTTP_PROXY=http://127.0.0.1:7897 \
        HTTPS_PROXY=http://127.0.0.1:7897 \
        no_proxy=localhost,127.0.0.1 \
        NO_PROXY=localhost,127.0.0.1 \
        /home/uisrc/.local/bin/codex "$@"
}
```

Nano 保存方法：

1. 按 `Ctrl+O`；
2. 按回车确认文件名；
3. 按 `Ctrl+X` 退出。

重新加载配置：

```bash
source ~/.bashrc
```

检查包装函数和程序版本：

```bash
type codex
codex --version
```

正常结果应表明 `codex` 是函数，并显示实际程序版本，例如：

```text
codex 是函数
codex-cli 0.154.0
```

## 5. 日常使用方法

1. 启动 Clash Verge，并确认代理节点可用。
2. 进入具体工程目录，不要直接在 `~` 下启动 Codex。
3. 正常执行 `codex`，包装函数会自动为它注入代理。

例如：

```bash
cd ~/work/anlogic-task3
codex
```

无需再添加：

```text
--enable respect_system_proxy
--disable apps
```

## 6. 本次无效尝试及原因

### 6.1 覆盖内置 OpenAI provider

尝试：

```bash
codex -c 'model_providers.openai.supports_websockets=false'
```

报错：

```text
model_providers contains reserved built-in provider IDs: `openai`
Built-in providers cannot be overridden.
```

原因：`openai` 是保留的内置 provider，不能用自定义 provider 配置覆盖。

### 6.2 使用已移除的 WebSocket 功能开关

检查结果：

```text
responses_websockets     removed  false
responses_websockets_v2  removed  false
```

原因：Codex CLI 0.154.0 已移除这些旧开关，不能依靠它们关闭 WebSocket。

### 6.3 只启用 `respect_system_proxy`

尝试：

```bash
codex --enable respect_system_proxy --disable apps
```

结果：依然出现 WebSocket 请求超时并降级到 HTTPS。

原因：在本环境中，这个尚处于 `under development` 状态的功能没有解决 Codex WebSocket 的代理问题。最终方案不依赖该功能。

### 6.4 使用不完整的 `mcp_servers` 覆盖

尝试：

```bash
codex -c 'mcp_servers.codex_apps.enabled=false'
```

报错：

```text
Error loading config.toml: invalid transport
in `mcp_servers.codex_apps`
```

原因：`codex_apps` 是 Codex 内置的 Apps/Connectors 服务，不是 `codex mcp list` 中由用户注册的普通 MCP。该一次性配置被当作缺少 `command` 或 `url` 的新 MCP 定义，因此无效。

### 6.5 临时关闭 Apps

```bash
codex --disable apps
```

这个参数成功消除了 `codex_apps` 的 30 秒等待，适合用于隔离问题；但显式设置代理环境变量后，Apps 本身也能正常快速启动，所以最终无需关闭。

## 7. 快速复查命令

如果以后再次变慢，先确认 Clash 端口是否仍为 `7897`：

```bash
gsettings get org.gnome.system.proxy.https host
gsettings get org.gnome.system.proxy.https port
```

然后进行最小测试：

```bash
cd ~/codex-practice
codex
```

输入：

```text
只回复 OK，不读取文件，不运行命令。
```

重点观察是否重新出现：

```text
Falling back from WebSockets to HTTPS transport
MCP client for `codex_apps` timed out
```

若 Clash 端口改变，需要同步修改 `~/.bashrc` 中 Codex 函数的所有 `7897`。

## 8. 恢复原始 Codex 命令

如需撤销包装函数：

1. 删除 `~/.bashrc` 中 `# Run Codex CLI through Clash Verge` 开始的整个函数块；
2. 在当前终端运行：

```bash
unset -f codex
hash -r
```

或者关闭当前终端并重新打开。

原始可执行文件仍位于：

```text
/home/uisrc/.local/bin/codex
```

## 9. 注意事项

- 必须先启动 Clash Verge，再运行 `codex`。
- 不要把订阅地址、访问令牌、`auth.json` 内容或完整会话 ID 写入排障记录。
- 不建议把代理变量全局永久导出，除非确实希望所有终端程序都经过 Clash。
- 如果网络恢复正常但复杂任务仍慢，再检查模型和 reasoning effort；本次故障的明显特征是固定的 WebSocket 超时及 HTTPS 降级提示。
