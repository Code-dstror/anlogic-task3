---
name: technical-report
description: Prepare and write this project's FPGA competition technical report in LaTeX, generate reproducible MATLAB plots and editable Visio diagrams, and verify the exported PDF. Use for report toolchain setup, scientific figures, report sections, and PDF layout; not for production RTL changes or launching FPGA builds.
---

# 技术报告工具链

最终交付采用 LaTeX → PDF。工作根目录从仓库推导；机器路径以 `ENVIRONMENT.local.md` 为准。
工具源码入口为 [tools/technical_report](../../../tools/technical_report/README.md)，不要把 `work/exp` 当作唯一脚本来源。

## 选择最短有效路径

- **统一图表样式**：全篇报告的新图及改绘图先读 [作图规范](references/figure-style.md)，参数来自 `tools/technical_report/report_style.json`。MATLAB、Visio、TikZ 和仿真波形共用图幅、字体、角色配色与线型约定；保留旧稿原件，整合时统一重导出。
- **正文与排版**：遵循 `work/technical_document/template/technical_document_template.docx` 的内容结构、字数、匿名和版面要求；DOCX 不是最终输出格式。参考样例用于学习论证方式，不复制其技术结论。
- **正文写法**：按用户 2026-10-28 批注，重点讲模块功能、算法原理、实际电路和结果。仿真段交代工具、具体输入及结果图，不写测试日志、检查次数、工程修订版本或“重点观察”等操作提示；源码与证据身份单独保留。简单时钟/复位/I²C 简述，板级接线放 2.2.1。框图保留关键输入输出，删除图底部整行接口备注。采用“每个摄像头、帧调度、图像读出、主机确认、取整”等具体说法。
- **数值、曲线与图像对比**：用 `matlab` MCP 运行保存的 `.m`。普通曲线只需基础 MATLAB。调用工具箱前查 `ver`；目录存在或 `license('test',...)` 为真不证明产品已安装。
- **复杂框图**：用 `report_visio` MCP 生成 VSDX 与 PDF/SVG/PNG；先读本技能的 [图表流程](references/figures.md)。小型流程图可直接用 TikZ。
- **真实波形**：使用项目现有 ModelSim 脚本和已绑定源码的波形/数据。示意时序图必须标为示意，不能作为 RTL 测试通过的证据。
- **综合与时序图表**：读取对应源版本的 TD 原生报告；报告任务本身不授权新构建、烧录或板级操作。

## 已配置工具

项目 `.codex/config.toml` 注册 `matlab` 与 `report_visio`。
MATLAB MCP 默认新建 nodesktop 会话，不接管用户 GUI。用户要求交互模型时再配置官方 desktop/existing 模式；existing 模式需官方会话共享初始化，不能只改名称假定已接入。

MATLAB 工具：`detect_matlab_toolboxes`、`evaluate_matlab_code`、`run_matlab_file`、`check_matlab_code`、`run_matlab_test_file`。
Visio 工具：`visio_status`、`create_diagram`、`inspect_diagram`。
如果当前对话尚未加载新 MCP，可使用 `tools/technical_report/mcp_probe.py` 对已登记服务发送真实调用，不必为普通制图重复安装。

**MATLAB MCP 的 `isError=false` 不足以证明脚本成功。** 必须读取输出、检查成功标记/断言与预期文件。保存脚本及数据后再引用到正文。
当前已安装的官方技能提供 MATLAB 文档、数据分析、导入导出、图像处理和 fi 审查；其中新版本 API 以本机 `help` 为准。

2026-10-26 已补齐并运行验证 Simulink、Fixed-Point Designer、Image Processing、Signal Processing、DSP System、Computer Vision、Symbolic Math 七项产品，MATLAB 保持 R2025b。当前事实仍以 ENVIRONMENT 和实际 `ver` 为准。需要复核产品时用 `tools/technical_report/test_matlab_products.ps1`；安装及明确收尾故障的处理见工具 README，不在普通报告任务中重复安装。

## LaTeX 项目与编译

新建本地文档时，若工具可用，先用 `create_latex_project` 创建独立文件夹与 `main.tex`，再用 `open_in_codex` 打开目录。
现有源文件原位编辑。正式报告放在 `work/technical_document`，试验放在 `work/exp`。

本机可重复导出入口（仓库根目录运行）：

```powershell
./tools/technical_report/build_latex.ps1 -MainFile <项目/main.tex>
# 所需宏包已缓存后：
./tools/technical_report/build_latex.ps1 -MainFile <项目/main.tex> -Offline
```

编译器为项目本地 Tectonic 0.17.0，XeTeX/ctex，输出到主文件旁的 `build/`。
第一次使用新宏包需联网下载。独立编译器与 Codex 内置预览可能使用不同缓存；预览超时不等于源文件有错，以各自编译结果记录。
保留 `build-console.txt`、`.log`、`.aux`、`.bbl` 和 `.synctex.gz` 便于定位问题。
LaTeX 直接引用矢量 PDF；SVG 作为编辑/预览资产保存，不依赖 shell-escape 自动转换。

交付前渲染最终 PDF 并检查所有页面，核对中文字体、坐标单位、题注、交叉引用、图表尺寸、公式和参考文献。内容变化后仅重查受影响环节。
示例与测试入口见 `tools/technical_report/examples/`、`run_smoke.ps1`；不要为了普通正文编辑重跑全部工具链测试。

## 数据与证据

每幅技术结果图至少保存：源脚本或 VSDX、原始数据、生成参数、工具版本、数据与源码身份、导出文件。
区分概念示意、合成测试、软件模型、RTL 仿真、物理实现和实板测量。
图注写测试条件与可支持的结论；未测结果保留 NOT_RUN，旧版本为 STALE，实际依赖阻塞为 BLOCKED。
算法比较需对齐位宽、舍入、溢出、边界处理和握手推进；不能用浮点近似代替 RTL 一致性证据。

换机或确需重装时才执行 `tools/technical_report/bootstrap.ps1`，显式传本机 Python 与 MATLAB 根目录。它保留无关 MCP、审批和沙箱配置。
