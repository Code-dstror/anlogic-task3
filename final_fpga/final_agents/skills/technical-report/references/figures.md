# 数值图与 Visio 框图

## MATLAB

将 `.m` 保存后交给 `run_matlab_file(script_path=绝对路径)`。实时探索可用 `evaluate_matlab_code`，正式结果仍落盘为脚本与数据。
当前安装为 R2025b；先查询实际 `ver`，缺少工具箱则使用基础 MATLAB 等价计算或准确报告缺口，不自动生成假结果。

R2025b 会受用户暗色主题影响。报告曲线必须显式指定白色 figure/axes、黑色坐标与标题，并在 `exportgraphics` 指定 `BackgroundColor='white'`。字体、配色和线宽遵循 [统一作图规范](figure-style.md)；默认关闭网格，读数确需时才加浅灰主网格。
只设置 figure 的 `Color='w'` 不够。参考 `tools/technical_report/examples/report_smoke.m`。

典型输出：矢量 PDF、SVG、300 dpi PNG、FIG、CSV/MAT。保留坐标轴单位、随机种子和全部参数。

Simulink 模型图可用 `print(['-s' model],'-dpdf',outputPath)` 导出，先 `open_system(model)`，结束后只关闭本次创建的模型。`save_system` 改变文件基名时也可能改变模型名；保存、打开和打印必须使用一致的名称。已运行示例见 `tools/technical_report/examples/products_smoke.m`。
图表按最终正文宽度制作，模板正文宽约 14.65 cm；确保缩放后文字可读，具体排版服从用户选定模板。

## Visio MCP

创建一份 JSON spec，文件位于 `work/exp` 或 `work/technical_document`。示例：

```json
{
  "width": 5.5, "height": 2,
  "nodes": [
    {"id":"a","text":"输入","x":0.3,"y":0.6,"w":1.4,"h":0.7},
    {"id":"b","text":"输出","x":3.7,"y":0.6,"w":1.4,"h":0.7}
  ],
  "edges": [{"from":"a","to":"b","text":"数据"}]
}
```

坐标单位英寸，`x/y` 是左下角，Y 向上。节点 kind 支持 rectangle/ellipse/text；fill 为 `#RRGGBB`。
执行 `create_diagram(spec_path, output_vsdx, overwrite=false)`，同时得到 VSDX、PDF、SVG、PNG。
再用 `inspect_diagram(vsdx_path)` 读回页和形状，并查看 PNG/PDF 布局。自动布局仍需人工视觉检查交叉线与标签。
本地适配器每次创建独立隐藏 Visio 实例，只关闭自己创建的实例；不修改用户已打开文档。
调整框图时修改 JSON 后重新生成，或由用户编辑 VSDX。若用户已手动编辑 VSDX，不以旧 JSON 覆盖其修改。

## 当前对话未热加载 MCP 时

将调用保存为 JSON 数组，如 `[{"name":"visio_status","arguments":{}}]`，然后从仓库根运行：

```powershell
./tools/technical_report/local/venv/Scripts/python.exe ./tools/technical_report/mcp_probe.py report_visio --calls <calls.json> --output <result.json>
```

MATLAB 脚本调用可加 `expect_text` 字段检查明确成功标记。协议调用成功和具体实验成功分别核对。
