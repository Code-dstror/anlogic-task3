# 连续回传更新 v6.5

本包版本为 `2026.11.10-continuous-upload-v6.5`，用于 build-server 的 `/home/build-user/td_simple`。
本地回归与打包校验完成后交付，由用户在 FinalShell 手动安装。服务器生效状态以安装后的回执确认。

## 改动

- 取消旧版每分钟最多上传 32 MiB 的配额。有积压时每批推送成功后立即继续。
- 每批最多读取 128 MiB 文件内容，每块仍为 8 MiB。这控制批次内存和 Git 对象大小，批次之间无固定休眠。
- 结果推送超时延长到 1800 秒。控制器停止时会终止自己的 Git 操作。
- 保留已有 SHA256 分块清单和成功推送后的游标提交方式。失败后重试同一批，重启后从已确认的块继续。
- 空闲、失败或本轮没有可推进数据时，仍按 60 秒周期检查，避免空循环。
- 安装保留服务器已有 `git_ssh.sh` 身份选择包装器和既有调度设置。

实际上传速率受服务器出口、GitHub、Git 压缩和索引开销影响。新代码移除了人为字节速率限制，
本地验证使用真实本地 Git 仓库与模拟 TD，服务器实际吞吐待部署后实测。

## 本地验证

Python 3.12 下共 86 项测试通过。

- `test_simple_controller.py` 共 51 项，含连续批次清空、40 MiB 报告单批传输、空批退避、
  断网后游标保留、远端已接受但本地超时的幂等重试、长 push 超时范围、控制器退出和 SSH 包装器保留。
- `test_simple_reports.py` 共 8 项，含 45 MiB 报告跨批续传后的完整内容及 SHA256 校验。
- `test_simple_resources.py` 共 27 项，含有运行任务时的安装保护和 Ctrl+C 恢复原暂停状态。

代码使用隔离维护分支 `codex/td-server-upload-20261110`。以上测试在 Windows 本地运行，
Linux 安装与实际网络吞吐由用户部署后验证。更新包生成器逐文件检查归档内容、时间戳和 SHA256 清单。

## FinalShell 操作

将 `td-simple-update-20261110-v6.5.tar.gz` 和对应 `.sha256` 文件上传到
`/home/build-user/td_simple/bootstrap/`。使用 build-user 账户执行以下命令。

```bash
cd /home/build-user/td_simple/bootstrap
sha256sum -c td-simple-update-20261110-v6.5.tar.gz.sha256
```

显示 `OK` 后执行。

```bash
tar -xzf td-simple-update-20261110-v6.5.tar.gz
bash server/td/simple/apply_update.sh
```

安装器会暂停新任务启动，等当前运行的 TD 任务自然结束，再替换控制器程序并恢复原先的调度状态。
出现 `WAITING_FOR_TD_IDLE` 表示正在等待。已有队列、SQLite、上传游标、编译产物和认证配置保留。
在等待阶段按 Ctrl+C 会恢复进入安装前的调度状态。等待期间请保持 FinalShell 会话连接。

正常完成后输出包括以下信息。

```text
Controller: 2026.11.10-continuous-upload-v6.5
Uploads: continuous backlog drain; 128MiB batches; no byte-per-minute limit; idle/retry poll=60s
```

## 生效检查

```bash
grep -E 'controller_version|upload_policy|continuous|rate_limit_bytes_per_second' /home/build-user/td_simple/status.json
tail -n 20 /home/build-user/td_simple/service.log
```

新状态应包含 `upload_policy.mode=continuous`、`rate_limit_bytes_per_second=null`、
`batch_bytes=134217728` 和 `push_timeout_seconds=1800`。
`publish_seconds=60` 表示空闲/失败后的检查间隔，积压数据的后续批次连续推送。
使用多次快照的 `pending_uploads` 和各任务 `artifacts.json` 中的完整性字段观察积压清空进度。
