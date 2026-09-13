# Ubuntu 22.04：Clash Verge、订阅导入与 Codex CLI 配置记忆

> 适用环境：VMware 虚拟机、Ubuntu 22.04（Jammy）、X11、Clash Verge Rev 2.5.1 amd64。
>
> 本文记录的是本机已经实际验证成功的处理过程。订阅地址、代理节点配置和 `~/.codex/auth.json` 都包含敏感信息，不应发给他人或提交到 Git。

## 一、Clash Verge 安装状态确认

使用本地 Deb 包安装：

```bash
sudo apt install ./Clash.Verge_2.5.1_amd64.deb
```

如果安装末尾出现下面这种 `N:` 提示，而没有 `E:` 错误，通常只是 `_apt` 用户不能读取当前目录中的本地 Deb，APT 临时以 root 身份读取，并不代表安装失败：

```text
N: 由于文件无法被用户 '_apt' 访问，已脱离沙盒并提权为根用户进行下载
```

使用以下命令确认：

```bash
dpkg-query -W -f='${Status}\nVersion: ${Version}\n' clash-verge
command -v clash-verge
dpkg -L clash-verge | grep -E '/usr/bin/|\.desktop$'
```

成功时应包含：

```text
install ok installed
Version: 2.5.1
/usr/bin/clash-verge
```

## 二、解决 Clash Verge 主界面花屏、斜线和缺块

### 1. 问题表现

直接执行 `/usr/bin/clash-verge` 时，窗口可以打开，但出现彩色斜线、空白区域、控件缺失等异常。

当前会话类型为 X11：

```bash
echo "$XDG_SESSION_TYPE"
```

输出：

```text
x11
```

该问题实际与 VMware 虚拟显卡和 WebKitGTK 的 DMA-BUF 渲染兼容性有关，不是安装失败。

### 2. 临时验证方法

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 /usr/bin/clash-verge
```

本机验证结果：主界面恢复正常。

### 3. 创建固定的兼容模式启动项

不要直接删除 `/usr/share/applications/Clash Verge.desktop`，因为它由 Deb 软件包管理，更新或重装时还会恢复。

创建当前用户专用的兼容入口：

```bash
mkdir -p "$HOME/.local/share/applications"

cp "/usr/share/applications/Clash Verge.desktop" \
  "$HOME/.local/share/applications/clash-verge-compatible.desktop"

sed -i 's/^Name=Clash Verge.*/Name=Clash Verge（兼容模式）/' \
  "$HOME/.local/share/applications/clash-verge-compatible.desktop"

sed -i 's|^Exec=.*|Exec=env WEBKIT_DISABLE_DMABUF_RENDERER=1 /usr/bin/clash-verge %u|' \
  "$HOME/.local/share/applications/clash-verge-compatible.desktop"

chmod 644 "$HOME/.local/share/applications/clash-verge-compatible.desktop"
update-desktop-database "$HOME/.local/share/applications"
```

检查：

```bash
grep -nE '^(Name|Exec)=' \
  "$HOME/.local/share/applications/clash-verge-compatible.desktop"
```

预期类似：

```text
Exec=env WEBKIT_DISABLE_DMABUF_RENDERER=1 /usr/bin/clash-verge %u
Name=Clash Verge（兼容模式）
```

启动前应彻底结束旧进程，因为关闭窗口后程序可能仍留在托盘后台；再次点击菜单可能只是唤醒旧进程：

```bash
pkill -x clash-verge
pgrep -a -x clash-verge || echo "Clash Verge 已完全退出"
```

之后从 Ubuntu 应用菜单启动“Clash Verge（兼容模式）”。

### 4. 可选：隐藏原始菜单入口

如果菜单中同时出现原入口和兼容入口，可以用用户级同名 Desktop 文件覆盖并隐藏原入口：

```bash
cp "/usr/share/applications/Clash Verge.desktop" \
  "$HOME/.local/share/applications/Clash Verge.desktop"

sed -i '/^Hidden=/d' \
  "$HOME/.local/share/applications/Clash Verge.desktop"

sed -i '/^\[Desktop Entry\]/a Hidden=true' \
  "$HOME/.local/share/applications/Clash Verge.desktop"

update-desktop-database "$HOME/.local/share/applications"
```

如果没有立即刷新，注销并重新登录 Ubuntu。

## 三、解决“订阅 → 新建”后界面卡住

### 1. 已确认的现象

主界面花屏修复后，点击“订阅 → 新建”仍会卡住，弹窗不显示，主界面也无法继续操作。

尝试同时加入以下变量仍未解决新建弹窗卡住：

```bash
WEBKIT_DISABLE_DMABUF_RENDERER=1 \
WEBKIT_DISABLE_COMPOSITING_MODE=1 \
/usr/bin/clash-verge
```

因此：

- `WEBKIT_DISABLE_DMABUF_RENDERER=1` 可以修复主界面花屏；
- 但当前 Ubuntu 22.04/X11/Clash Verge 2.5.1 环境中的“新建”弹窗仍存在 WebKit 界面兼容问题；
- 不再使用“新建”按钮，改用“终端下载配置 + 拖拽导入”。

不要通过 `sudo clash-verge` 或 root 身份运行图形程序，否则可能造成配置文件归 root 所有，产生新的权限问题。

### 2. 安全下载订阅文件

订阅 URL 通常包含账户令牌。使用隐藏输入，避免 URL 显示在屏幕或 shell 历史中：

```bash
mkdir -p "$HOME/Downloads"

read -rsp '粘贴订阅地址（屏幕不会显示）: ' SUB_URL
echo

curl -L --fail-with-body \
  --connect-timeout 10 \
  --max-time 30 \
  -A 'clash.meta' \
  -o "$HOME/Downloads/clash-subscription.yaml" \
  -w '\nHTTP=%{http_code} size=%{size_download} remote=%{remote_ip}\n' \
  "$SUB_URL"

CURL_RESULT=$?
unset SUB_URL

chmod 600 "$HOME/Downloads/clash-subscription.yaml" 2>/dev/null
echo "curl_exit=$CURL_RESULT"
```

输入注意事项：

1. 终端出现“粘贴订阅地址”后，使用 `Ctrl+Shift+V` 粘贴；
2. 因为 `read -s` 隐藏输入，屏幕不会出现任何字符，这是正常现象；
3. 粘贴后直接按 Enter，随后才会执行 `curl`；
4. 若要取消等待，按 `Ctrl+C`。

下载成功的典型结果：

```text
HTTP=200
curl_exit=0
```

可以进行不泄露节点内容的简单检查：

```bash
file "$HOME/Downloads/clash-subscription.yaml"

grep -qE '^(proxies|proxy-providers|proxy-groups|mixed-port|port):' \
  "$HOME/Downloads/clash-subscription.yaml" \
  && echo "检测到 Clash YAML 配置" \
  || echo "未检测到典型 Clash YAML 字段"
```

常见 `curl` 退出码：

- `0`：成功；
- `6`：DNS 解析失败；
- `7`：无法连接服务器；
- `22`：服务器返回 400、403、404 等 HTTP 错误；
- `28`：连接超时；
- `35`：TLS/证书握手问题。

### 3. 绕过“新建”弹窗导入

1. 使用“Clash Verge（兼容模式）”启动；
2. 打开左侧“订阅”页面，但不要点击“新建”；
3. 打开 Ubuntu“文件”应用，进入“下载”目录；
4. 将 `clash-subscription.yaml` 直接拖到 Clash Verge 订阅页面中；
5. 等待订阅卡片出现并选中订阅；
6. 选择可用节点，开启系统代理。

本机最终结果：订阅成功导入，代理正常，可以访问互联网。

## 四、代理成功后安装 Codex CLI

### 1. 先验证终端网络

浏览器能联网不一定代表终端会自动使用 GNOME 系统代理。先执行：

```bash
curl -sS -o /dev/null \
  --connect-timeout 10 \
  --max-time 30 \
  -w 'HTTP=%{http_code} total=%{time_total}s\n' \
  https://api.openai.com/v1/models
```

未携带 API Key 时，以下结果代表网络、DNS、TLS 和 OpenAI 服务均已连通：

```text
HTTP=401
```

如果浏览器正常但该命令超时，查看 GNOME 系统代理信息：

```bash
gsettings get org.gnome.system.proxy mode
gsettings get org.gnome.system.proxy.http host
gsettings get org.gnome.system.proxy.http port
```

将 Clash Verge 中显示的实际混合端口代入以下命令。不要照抄示例端口：

```bash
export http_proxy="http://127.0.0.1:实际混合端口"
export https_proxy="http://127.0.0.1:实际混合端口"
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
export no_proxy="localhost,127.0.0.1,::1"
export NO_PROXY="$no_proxy"
```

先在当前终端临时测试，确认有效后再考虑写入 shell 启动配置。

### 2. 安装基础工具

```bash
sudo apt update
sudo apt install -y curl ca-certificates git
```

### 3. 使用 OpenAI 官方独立安装器

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
hash -r
codex --version
```

`codex --version` 能输出版本号即表示安装完成。

### 4. 登录 Codex

Ubuntu 带图形浏览器时，优先尝试：

```bash
codex login
```

如果浏览器登录无法通过 localhost 回调返回 CLI，改用设备码：

```bash
codex login --device-auth
```

按照终端提示打开网址、登录，并输入一次性代码。最后检查：

```bash
codex login status
```

本机最终结果：Codex CLI 已成功安装，并已使用 ChatGPT 账户登录。

### 5. 凭据安全

Codex 登录凭据可能保存在：

```text
~/.codex/auth.json
```

该文件等同于密码：

- 不要复制到工程目录；
- 不要提交到 Git；
- 不要粘贴到聊天、Issue 或日志中；
- 不要让不可信用户读取。

## 五、建议的 Codex 使用方式

将工程放在 Ubuntu 自己的文件系统中，例如：

```bash
mkdir -p "$HOME/work/anlogic-task3-linux"
cd "$HOME/work/anlogic-task3-linux"
git init
```

建议使用工作区可写、越界操作需审批的模式：

```bash
codex --sandbox workspace-write --ask-for-approval on-request
```

不建议日常使用 `--dangerously-bypass-approvals-and-sandbox`。即使在虚拟机内，它仍可能误删工程、用户目录、登录凭据或 VMware 共享文件。

## 六、最终有效方案摘要

```text
主界面花屏
  -> WEBKIT_DISABLE_DMABUF_RENDERER=1
  -> 创建“Clash Verge（兼容模式）”用户启动项

点击“订阅 -> 新建”卡住
  -> 不再使用该弹窗
  -> 终端隐藏输入订阅 URL
  -> curl 下载为 clash-subscription.yaml
  -> 将 YAML 拖入订阅页面

代理正常
  -> curl 请求 OpenAI 接口得到 HTTP 401
  -> 执行 OpenAI 官方 Codex CLI 安装脚本
  -> codex login 或 codex login --device-auth
  -> codex login status 确认成功
```

## 七、参考资料

- Clash Verge Rev Linux FAQ：<https://github.com/clash-verge-rev/clash-verge-rev.github.io/blob/main/docs/faq/linux.md>
- Clash Verge Rev 订阅配置说明：<https://github.com/clash-verge-rev/clash-verge-rev.github.io/blob/main/docs/guide/profile.md>
- Ubuntu 22.04/X11/2.5.1 WebKit 界面问题：<https://github.com/clash-verge-rev/clash-verge-rev/issues/7350>
- OpenAI Docs：Codex CLI：<https://learn.chatgpt.com/docs/codex/cli>
- OpenAI Docs：身份验证：<https://learn.chatgpt.com/docs/auth>
