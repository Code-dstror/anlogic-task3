# Linux零问题提示的警告索引修正 v6.2

build-server已确认安装v6.1，真实极小工程共享综合+四种子完整报告回传通过，见
[实测记录](../evidence/reports-v61-server-20261023.md)。

本轮发现warnings.csv把成功提示
`RUN-0008 : Do critical warning check and 0 issue(s) found.`误记为警告。
原生日志、Clock Tree等报告和构建结果正常。
`2026.10.23-warning-index-v6.2`只修正该完整零问题提示的分类，
保留真实警告、非零检查、suppression提示和原始字节，报告配置仍为timing-diagnostics-v2。
12项日志测试及117份真实Linux日志副本复核通过；没有重跑TD。
本版已由用户安装并获新鲜回执确认，索引及详细报告已实测。
线程取值校验缺口已由[v6.3](THREAD_VALUES_V6_3_20261023.md)修复并由用户安装，见[部署回执](../evidence/v63-deployment-20261023.md)。

将 `td-simple-update-20261023-v6.2.tar.gz` 上传到 `/home/build-user/td_simple/bootstrap/`，执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-update-20261023-v6.2.tar.gz -C /home/build-user/td_simple/bootstrap
bash /home/build-user/td_simple/bootstrap/server/td/simple/apply_update.sh
```

安装器保持原等待空闲及成果保留行为。新任务使用修正索引；已完成任务不被自动改写或重编。
本次下载的旧索引和本地校正索引分别保存，不能把本地修正称为服务器重新回传。
