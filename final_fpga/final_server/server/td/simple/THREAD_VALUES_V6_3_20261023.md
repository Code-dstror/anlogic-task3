# TD原生线程取值与生效检查 v6.3

用户已手动安装 `2026.10.23-native-threads-v6.3`，新鲜GitHub状态已确认版本、
native_thread_values和thread_parameter_readback=true，见[部署回执](../evidence/v63-deployment-20261023.md)。

## 本轮发现

用户确认GUI提供1/2/4/8/16/32/auto；实际TD 6.2.3.210850也只接受这些原生选项。
旧控制器把1–32误当作连续整数，接受12/20/24后，TD给出PRJ-6303并退回auto。
请求预算仍按12/20/24记账，无法证明实际TD线程受相同限制；这不是有效的64线程验证。
v6.2的警告修正正常保留了这些真实警告，没有把它们误过滤。

本机分别对syn_1/phy_1枚举1–32并读取原生参数，接受集合均为1/2/4/8/16/32。
GUI的auto本身合法，但它没有固定的线程预留，所以受控构建继续使用明确数字。

## 修正

- 客户端、项目配置和服务器请求入口只接受1/2/4/8/16/32，覆盖threads、synth_threads、seed_threads。
  非法值直接拒绝，不静默取整，也不改成auto；工作进程再次校验历史队列中的旧配置。
- 设置线程后、任何launch_runs之前，用TD自己的report_run_param读回。
  回读值与请求不一致就失败，不继续编译。记录写入job根目录的
  thread-syn_1.params / thread-phy_1.params及TD_SIMPLE_THREADS日志，正常分块回传。
- capabilities公布native_thread_values与thread_parameter_readback。
  任意合法组合仍按请求直接求和<=64，最多8任务/8综合槽；不是固定支持某一个组合。
  300GiB RSS、宿主负载/内存检查和既有队列/成果保留行为不变。

## 验证范围

133项简版控制器测试通过，包括非法值不发送、配置拒绝、模拟TD退回auto时读回失败、
合法组合64线程准入以及原有传输/接续/日志/资源行为。
真实服务器合法补测为4+4+8+16+32=64，6任务全部DONE，792文件校验通过，详见
[v6.2服务器复测](../evidence/reports-v62-server-20261023.md)。这是v6.2的合法值流程验证，
不能当作v6.3新作业读回保护的服务器实测；v6.3部署已由后续回执单独确认。

本机新脚本实际TD读回成功，综合、布局、布线完成；首次bitgen虽生成bit和完成标记，
但子进程异常退出并报PRJ-8806，整轮如实保留FAILED。
随后从同源routed DB复制到独立任务，参数读回、bitgen、报告和原生重开均DONE，退出0、报告COMPLETE。
未覆盖失败任务或把继承阶段写成新DONE。记录在server/td/local/reports-v63-validation/。

## 安装时机

**本版已由用户安装，确认时全部受控任务已终态。后续维护仍先等活动任务结束。**
16是原生合法值，本次发现不要求改变正式任务的参数。
此前等待正式任务期间没有为测试或更新而暂停、取消或重启该批任务。

将td-simple-update-20261023-v6.3.tar.gz上传到/home/build-user/td_simple/bootstrap/后，空闲时执行：

```bash
tar -xzf /home/build-user/td_simple/bootstrap/td-simple-update-20261023-v6.3.tar.gz -C /home/build-user/td_simple/bootstrap
bash /home/build-user/td_simple/bootstrap/server/td/simple/apply_update.sh
```

安装后核对版本、native_thread_values和新鲜状态。用户本次已手动部署v6.3；本次查询和文档同步没有追加服务器试跑或改写旧结果。
