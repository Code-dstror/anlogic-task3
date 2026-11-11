# RK SDK 参数黑盒短测

从仓库根目录运行以下命令。Python 路径取自本机 `ENVIRONMENT.local.md`，候选 SDK 排在仓库根目录之前。

```powershell
$repoRoot = (Resolve-Path .).Path
$sdkRoot = Join-Path $repoRoot 'refactor/camera_raw_r2/rk_sdk'
$env:PYTHONPATH = "$sdkRoot;$repoRoot"
Push-Location (Join-Path $sdkRoot 'tests/blackbox_parameters_20261110')
try {
    & 'python' -X utf8 -B -c 'import subprocess, sys; sys.exit(subprocess.run([sys.executable, "-X", "utf8", "-B", "-m", "unittest", "-v", "test_parameters"], timeout=30).returncode)'
} finally {
    Pop-Location
}
```

测试使用真实 `SharedControls`、`validate_profile` 和 `ConfigTransactions`。寄存器模型独立提供 READY 和 APPLIED 回执，预期扩展字按公开线协议计算。覆盖单目与双目参数发现、完整事务与 ACTIVE 局部补齐、29 个非法请求零 BAR 写入，以及 APPLIED 后末尾扩展字损坏时拒绝提交结果。29 项中包含从 schema 0 切到 schema 2 时省略普通 SDR 字段 `dehaze_lut_generation` 的反例。

Python 3.12.9 实测 6/6 通过，0.027 秒。输入哈希、运行目录与失败归类见 [VALIDATION.json](VALIDATION.json)。本次资格限于公开 Python API 和寄存器模型，实际 shell 会话、FPGA 及板级为 `NOT_RUN`。
