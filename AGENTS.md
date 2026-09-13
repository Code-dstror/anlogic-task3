# 长期协作规则

## 资料与目录边界

- `local_refs/official_package` 是严格只读的官方资料。
- 不得修改、移动、删除、解压 `local_refs/official_package` 中的任何内容，也不得在其中编译。
- 遇到 Word 文档且附近有同名 PDF 时，优先读取 PDF。
- Linux 代码放在 `linux/`。
- FPGA 代码放在 `fpga/`；未经明确要求，不要修改其中内容。
- Linux 与 FPGA 双方共同维护的接口文档放在 `interface/`。

## 设备与系统操作

- 不得假定 `/dev/video73` 或 `/dev/video22` 永远固定；应在运行时发现、配置或明确记录实际设备节点。
- 未经明确批准，不得执行 `sudo`、安装软件、加载内核模块、修改设备树、烧录、重启，或配置开机自启动。

## Parallel work boundaries

- 工作流所有权见 [docs/coordination/workstream-ownership.md](docs/coordination/workstream-ownership.md)。
- 任务开始前声明属于 Linux transport、AI/application、FPGA 或 shared contract；默认不得修改其他工作流私有模块。
- 必须修改 shared contract 时，将合同修改与功能实现拆成独立提交。
- 新测试放入对应模块的独立测试文件；不得写入 `local_refs` 或 `official_package`。
