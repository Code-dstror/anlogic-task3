# build-server 的 FPGA 目录清理

依据用户 2026-10-22 提供的 `/home/build-user` 清单整理。这里只给分类和只读检查，不自动删除。
先安装新服务，确认新状态、编译和回传，再清理旧程序；本地测试/源码发布不能替代服务器验收。

建议最终只在 home 顶层保留三类 FPGA 入口：

```text
/home/build-user/TD_Release_2026.2_NL/       TD 安装
/home/build-user/fpga_projects/             工程、每次编译的 Runs 和需保留的旧产物
/home/build-user/td_simple/                 新自动化程序、状态、认证和缓存
```

当前 `fpga-source` 是已拉取的手动编译工程，应保留。
用户可以在 TD 关闭且没有该工程进程时，将它移到 `fpga_projects/manual/hdr_jpeg`；
工程采用相对依赖路径，重开 AL 后 TD 会更新本机 Path。若本地配置还记录 seed_repo，更新该路径。
本次安装和清理脚本不移动它，不覆盖已有 Runs。

## 明确保留

| 名称 | 原因 |
|---|---|
| `TD_Release_2026.2_NL` | 当前 TD 软件 |
| `fpga-source` | 当前手动 HDR/JPEG 工程，可能已有用户编译结果 |
| `fpga_projects`、`td_simple` | 新版工程/自动化入口，安装后创建 |
| `opt` | 实际 Python 3.12.9 在其中，新服务依赖；不要整目录删除 |
| SSH 配置、私钥和实际许可证 | Git 拉取/推送和 TD 授权依赖，目录清理不迁移或删除它们 |

## 新版验收后可删除的独立安装/修复文件

这些文件不属于新服务运行依赖；前提是安装和必要的恢复已经完成，用户不再需要离线安装包。

- `TD_Release_2026.2_NL.zip`（保留已解压安装目录）。
- `cpython-3.12.9+20250212-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz` 及其 `.sha256`。
- `install_python312.sh`（保留 `opt` 中实际 Python）。
- `ha_cache_recovery_v2.py`、`ha_cache_recovery_v3.py`、`ha_cache_repair_20261020.py`。
- 本次的 `td-simple-private-20261022.tar.gz`：确认安装成功且认证配置已在 td_simple 内保存后，
  可删除 td_simple/bootstrap 内这份含凭据的交付包；不要删除实际 network-auth.json。

## 旧目录先核对产物与引用

| 名称 | 更新后的处理 |
|---|---|
| `td_operator` | 旧 guardian/HA/operator 停用后，确认不再有旧进程和自启动引用；保留必要密钥/登记和唯一日志后清程序 |
| `td_farm` | 含旧任务、原生 Runs、DB、bit 和回传缓存；先等旧 worker 结束，把需要的历史产物归入 `fpga_projects/legacy`，再清已退役内容 |
| `td_runs` | 可能包含历史 bitstream、手工工程和 VCS 结果；不能按临时目录整删，先保留唯一产物 |
| `td_control` | 旧源码/部署材料；确认未承担唯一 Git checkout、SSH/许可证路径或历史证据后再清 |
| `td_security_v2_dynamic` | 旧 V2 交付目录；确认没有仍需保存的登记/密钥或唯一材料后再清 |
| `td_automation_repair_20261013`、`td_automation_rollback_repair_20261013`、`td_runtime_recovery_20261014`、`td_git18_hotfix` | 旧安装/修复材料；新服务不依赖，确认没有唯一源/证据或被引用的配置后可清 |
| `vcs_pilot` | 历史 VCS 试验；结果若需要保留则归档到项目历史，再清退役副本 |

旧队列不自动迁移；已运行的任务继续到自身完成。旧数据库仍显示 RUNNING 时，应以实际 lease/进程
是否仍在持有判断，不删除锁文件来制造“空闲”。历史 bitstream 不因这次清理删除或覆盖。

## 目前无法按名称判断

- `license_for_website`、`license_for_website.zip`：可能与 TD/VCS 授权、说明或离线交付有关；查实际引用后再定。
- `Project`、`da`：不知道内容和所有权，保留待核对。
- `anlogic_ai_experiments`、`anlogic_yolo26`、`anlogic_yolop`、`anlogic_yolov5`、`anlogic_yolov8`、
  `datasets`、数据集压缩包及标准用户目录：不属于本次 FPGA 自动化清理范围。

## 一次只读清点

```bash
/home/build-user/opt/python-3.12.9/bin/python3.12 -I -B /home/build-user/td_simple/app/cleanup_inventory.py --home /home/build-user
```

它只检查上述明确列出的 FPGA 名称、实际程序引用、旧 worker、当前新服务和本账户 crontab，
统计 bit/DB/报告日志并列少量样例；不读取私钥或校园网密码，不删除、移动或重启任何内容。
将输出交回后即可把“可能退役”进一步收敛成逐项确认的清理清单。
