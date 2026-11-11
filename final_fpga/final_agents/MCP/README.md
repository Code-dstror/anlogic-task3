# 本工程的 MCP

本工程项目配置注册了下列两个 stdio 服务。这里保留可共享配置和源码，不附带软件安装、账户信息或运行会话。

| 服务名 | 实现 | 项目用途 |
|---|---|---|
| `matlab` | MathWorks 官方 `matlab-mcp-server`，项目登记版本 v0.15.0 | MATLAB 文档、数值分析、脚本、测试及科学作图 |
| `report_visio` | 本项目 [visio_mcp.py](visio_mcp.py)，服务版本 1.0.0 | 通过 Windows Visio COM 创建、读回和导出可编辑框图 |

Visio 适配器是项目自有实现。LaTeX/Tectonic 是报告编译工具，不是此处注册的 MCP 服务。

## 配置

[config.example.toml](config.example.toml)只包含两项 MCP，先替换以下文本，再将相应段合并到目标项目的 `.codex/config.toml`。保留目标文件中的其他配置；本模板不会自动安装或注册服务。

| 标记 | 填入内容 |
|---|---|
| `__PROJECT_ROOT__` | 目标项目绝对路径，建议在 TOML 中使用 `/` |
| `__MATLAB_ROOT__` | 已安装且可运行的 MATLAB 根目录，不含 `bin` |
| `__VISIO_PYTHON__` | 已安装本目录依赖的 Python 解释器完整路径 |

MATLAB 二进制按模板位于 `tools/technical_report/local/matlab-mcp-server.exe`；也可将 `command` 改成自己的实际位置。Visio 模板直接使用本交付目录的 `final_agents/MCP/visio_mcp.py`。如使用原仓库维护版本，将该项改成 `tools/technical_report/visio_mcp.py`。

MATLAB 保留项目原有参数：新建 `nodesktop` 会话、工作目录为 `work/technical_document`、关闭 MCP 遥测，启动/工具超时为 120/240 秒。请先创建工作目录，并按实际 `ver` 核对产品和许可证。

Visio 需要 Windows、桌面 Visio 和 Python COM 支持。依赖直接声明见 [requirements.txt](requirements.txt)，项目登记的完整版本清单见 [requirements-lock.txt](requirements-lock.txt)。在自行准备的 Python 虚拟环境中安装：

```powershell
& '<目标虚拟环境的 Python 完整路径>' -m pip install -r final_agents/MCP/requirements-lock.txt
```

配置加载后检查服务及工具是否实际可用。当前聊天是否加载服务应以工具列表和调用结果判断，不能仅凭配置文件存在。

## 官方 MATLAB MCP 来源

固定来源、Windows x64 下载地址和 SHA256 见 [matlab-source.json](matlab-source.json)。此版本和哈希来自项目已有安装脚本，本次未重新下载，也不声称它是最新版本。下载后核对 SHA256 和 MathWorks Authenticode 签名；其他系统应选择官方对应平台发行物，不能沿用 Windows 哈希。

## Visio 源码与示例

`visio_mcp.py` 与项目原源码保持字节一致。它从自身位置向上两级推导仓库根目录，因此应保留当前 `final_agents/MCP/` 布局，或使用原来的 `tools/technical_report/` 布局。

- `visio_status`：查询独立 Visio COM 实例是否可用。
- `create_diagram`：按 JSON 创建 VSDX，并导出 PDF、SVG、PNG；默认不覆盖已有文件。
- `inspect_diagram`：读回 VSDX 页面和形状信息。

允许的输入输出范围是仓库内的 `work/exp/` 与 `work/technical_document/`。将 [examples/diagram.json](examples/diagram.json) 复制到这两个目录之一后，再将该路径传给工具。此示例是示意图，不是 FPGA 实测证据。

[mcp_probe.py](mcp_probe.py) 是项目已有的 stdio 检查客户端副本，读取目标项目实际 `.codex/config.toml`；需要诊断时使用，执行会启动选定服务。
