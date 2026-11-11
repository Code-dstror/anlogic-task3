# 本工程的 Codex Skills 与 MCP

包含 **16 个 Skills** 和 **2 个项目 MCP**，用于 FPGA 开发、验证、资料检索和技术报告。技能脚本、参考资料、模板和第三方许可证随包保存；来源与逐文件 SHA256 见 [manifest.json](manifest.json)。

## 目录

| 目录 / 文件 | 内容 |
|---|---|
| [skills/](skills/) | 可供 Codex 使用的技能目录，每个技能以 `SKILL.md` 为入口 |
| [MCP/README.md](MCP/README.md) | MATLAB、Visio MCP 的来源、配置和使用说明 |
| [MCP/config.example.toml](MCP/config.example.toml) | 按目标机器填写路径的项目配置模板 |
| [licenses/](licenses/) | MathWorks 许可与来源登记；Verilog 技能自带 Apache-2.0 许可证 |

## Skills 清单

| 技能 | 用途 |
|---|---|
| [anlogic-td-fpga](skills/anlogic-td-fpga/SKILL.md) | Anlogic TD 工程、IP 注册、约束、构建和报告处理 |
| [rtl-stream-contract](skills/rtl-stream-contract/SKILL.md) | 流接口、背压、帧边界、复位、CDC 及独立黑盒验证 |
| [jpeg-fixedpoint](skills/jpeg-fixedpoint/SKILL.md) | 硬件 JPEG、定点计算、MCU 和熵编码验证 |
| [readable-verilog-generator](skills/readable-verilog-generator/SKILL.md) | 按规范生成 Verilog、结构化评审和代码质量检查 |
| [td-build-evidence](skills/td-build-evidence/SKILL.md) | 按源码与运行阶段核对 TD 综合、实现和时序证据 |
| [td-timing-closure](skills/td-timing-closure/SKILL.md) | 物理 setup、hold、recovery、removal 时序收敛 |
| [td-github-control](skills/td-github-control/SKILL.md) | 经项目现有 GitHub 客户端提交与跟踪服务器 TD 任务 |
| [pcie-board-bringup](skills/pcie-board-bringup/SKILL.md) | 明确授权后的 RK3576–FPGA PCIe/DMA 板级实验 |
| [vendor-doc-lookup](skills/vendor-doc-lookup/SKILL.md) | 按资料索引核对器件、TD、IP、板卡和 IMX415 参数 |
| [pdf-doc-toolkit](skills/pdf-doc-toolkit/SKILL.md) | 技术 PDF 的检索、提取、渲染和表格核对 |
| [technical-report](skills/technical-report/SKILL.md) | LaTeX 报告、MATLAB 科学作图、Visio 框图及 PDF 检查 |
| [matlab-read-documentation](skills/matlab-read-documentation/SKILL.md) | 查阅 MathWorks 官方文档 |
| [matlab-analyze-data](skills/matlab-analyze-data/SKILL.md) | MATLAB 数组、表格及时间序列分析 |
| [matlab-import-export-data](skills/matlab-import-export-data/SKILL.md) | MATLAB 数据文件导入导出 |
| [matlab-process-images](skills/matlab-process-images/SKILL.md) | MATLAB 图像处理 |
| [matlab-review-fi-object-code](skills/matlab-review-fi-object-code/SKILL.md) | MATLAB `fi` 定点代码检查 |

## 复用方法与依赖

1. 在本仓库中可直接阅读本目录；要作为活动技能使用，将需要的技能子目录合并到目标项目的 `.agents/skills/`，先检查同名文件，保留目标项目已有修改。本次整理未替换活动技能。
2. 项目技能中的相对引用沿用原开发仓库布局，依赖 `AGENTS.md`、`src_fpga/`、`fpga_prj/`、`tools/`、`server/td/`、`docs/` 及 `references/vendor/` 等。这里作为工具资料保存；安装到新的目标项目时，应按实际目录调整引用，并提供对应合同、脚本与厂商资料。两个 FPGA 版本的入口见[项目 README](../README.md)。
3. 本机安装目录按目标机器填写；纯本机环境适配技能 `fpga-windows-toolchain` 已排除。其他技能中对它的可选调用已改成直接核对目标机器环境。
4. `td-github-control` 保留项目已有分支及客户端协议，使用者需自行配置获授权的仓库和凭据。账号路径为占位符，历史服务版本或实测记录不证明新机器、新任务可用。
5. `readable-verilog-generator` 是本工程已安装内容的快照，包含运行代码、资源与检索索引；不附带本机安装回执，也不冒充上游带 `RELEASE_RECEIPT.json` 的正式安装发行包。优先按本工程限定范围使用，其他平台依赖不是本项目的默认构建入口。
6. TD 技能保留历史工具行为与 PH1A60 示例作为参考；示例器件、引脚和工作目录不能直接用于本工程 PH1A90SEG324-2。长时间构建仍按本项目规则交给服务器。

MathWorks 的五项技能来自登记的官方仓库固定提交，已保留原有 Codex frontmatter 兼容调整；它们不是只适配某一台机器的技能。[来源登记](licenses/mathworks-skills.json)和[许可证](licenses/MATHWORKS-LICENSE.md)随包保存，许可证也放入每个 MATLAB 技能目录。

归档的格式和结构检查见 [VALIDATION.md](VALIDATION.md)。MCP 服务需在目标环境安装依赖并配置后使用。
