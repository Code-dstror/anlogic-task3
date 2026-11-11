# TD 自动化控制器源码

本目录提供v6.6控制器、客户端、安装与打包工具，以及配套测试。
当前发行标识为 `2026.11.10-measured-admission-v6.6-sanitized`。
版本与配置摘要见 [SOURCE.json](SOURCE.json)，发行文件清单见
[td-simple-update-manifest.json](td-simple-update-manifest.json)。

## 文件入口

| 路径 | 用途 |
|---|---|
| `server/td/simple/service.py` | 控制器与守护进程，获取工程/命令、调度任务、发布回执与产物 |
| `server/td/simple/resources.py` | CPU/RSS采样、历史峰值和资源准入 |
| `server/td/simple/worker.py`、`flow.py` | 独立任务、TD原生阶段执行和结果判定 |
| `server/td/simple/checkpoints.py`、`run_options.py` | 综合/物理检查点接续与原生Run Properties |
| `server/td/simple/transport.py` | Git传输、分块回传、超时和续传 |
| `server/td/simple/logs.py`、`reports.py` | 阶段日志、警告索引、面积/时序/时钟报告 |
| `server/td/simple/install.py`、`apply_update.sh` | FinalShell安装与升级入口 |
| `server/td/simple/client.py` | 与本版本匹配的本地命令客户端 |
| `server/td/simple/common.py` | 版本、配置、队列存储、请求与资源策略定义 |
| `server/td/simple/network.py`、`git_ssh.sh` | 校园网认证支持与SSH发行模板 |
| `server/td/simple/process_control.py`、`stop_jobs.py` | 任务进程身份检查与定向停止 |
| `server/td/simple/tools/run_td.py` | 服务器TD进程启动与输出保存 |
| `server/td/tests/test_simple*.py` | 与维护提交一致的9份既有测试源码 |
| `server/td/examples/smoke/` | 测试依赖的最小TD工程 |
| `server/td/make_simple_update.py` | 生成带清单及LF格式SHA256侧文件的公开更新包 |
| `server/td/analyze_admission.py` | 从已回传资源CSV复核并发准入与历史负载 |

`simple/` 内的日期文档保留版本演进说明。
本目录内的 `OWNER/REPOSITORY`、`build-user` 和 `portal.example.invalid` 用于说明配置位置。

## 已部署配置

- 单任务原生线程支持1、2、4、8、16、32，总请求线程预算128。
- TD CPU准入目标为有效逻辑CPU的50%，TD RSS预算300 GiB，同时检查整机CPU与可用内存。
- 每20秒采样，每30秒最多启动一个任务。资源不足时保留队列等待。
- 内存按历史峰值×1.25预留，下限12 GiB，无历史任务至少16 GiB。
- 回传按8 MiB分块、128 MiB批次连续发送，`rate_limit_bytes_per_second=null`。
- 工程/命令获取周期60秒，回传空闲/失败时按60秒周期检查，结果push超时1800秒。

服务依赖Python 3.12.9、Git、TD 2026.2及许可证环境。服务和工程默认存放在当前用户主目录下的
`td_simple/` 和 `fpga_projects/`，TD安装目录由 `TD_ROOT` 指定。
源码工程清单由开发分支的 `server/td/projects.json` 提供，示例为
[projects.example.json](server/td/simple/projects.example.json)。

## 校验与维护

在本目录执行Linux校验命令。

```bash
sha256sum -c SHA256SUMS
```

源码包含v6.6资源准入、v6.5连续回传，以及更新包SHA256侧文件的LF修正。
本次整理核对了发行文件与维护源、Python语法、模块依赖和安装器相对路径。
既有测试源码保留，后续修改控制器时可从本目录运行。

```bash
python3 -I -B -m unittest discover -s server/td/tests -p 'test_simple*.py'
```

测试使用临时Git仓库和仿真TD进程，其中控制器/报告测试还需要Python的Tkinter模块。
测试生成的临时文件位于 `server/td/local/`。

使用本机登记的Python运行打包器，输出路径可自行指定。

```bash
python3 -I -B server/td/make_simple_update.py --output dist/td-simple-update-v6.6.tar.gz
```

打包器保留 `server/td/simple/` 安装布局，记录源码提交和各文件SHA256。
实际使用前，设置 `common.py` 中的仓库地址及 `client.py` 中对应的仓库白名单。
`network.py` 中的门户地址与响应主机检查、`install.py` 中的门户检查须在启用门户登录时按目标网络配置。
示例项目清单中的工程路径也需要替换为目标仓库内路径。

## FinalShell更新入口

服务安装使用本目录的 `server/td/simple/apply_update.sh`。完成仓库配置后生成公开包，将包及其
`.sha256` 文件上传至目标用户的 `~/td_simple/bootstrap/`。

```bash
cd ~/td_simple/bootstrap
sha256sum -c td-simple-update-v6.6.tar.gz.sha256
```

校验通过后，设置工具路径并执行。`TD_PYTHON`可指定实际Python路径，默认使用python3。

```bash
tar -xzf td-simple-update-v6.6.tar.gz
export TD_ROOT=/opt/td/TD_Release_2026.2
export TD_SEED_REPO="$HOME/fpga-source"
bash server/td/simple/apply_update.sh
```

安装器等待运行任务自然结束，保留队列、上传进度、DB/bit及服务器既有认证配置。
`git_ssh.sh` 是发行模板，已有服务器身份设置由安装器保留。
本目录为可分享的源码副本，安装参数与认证由目标环境管理。
安装完成后通过项目入口的 `status` 核对实际版本、策略和回传时间。
