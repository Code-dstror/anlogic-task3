# 调试套件脱板检查输出

保存本轮实际执行的原始日志：

- [final_component_checks.log](final_component_checks.log)：调试目录及独立driver目录合计92项检查，
  0失败、0跳过。使用真实Windows native LZ库、实际共享C helper与注入的MMIO/MPP/显示对象。
- [assertion_checks.log](assertion_checks.log)：随后针对计数器拼写校验的3项检查，全部通过。
  其中1个新方法使当前源码测试清单为93项；没有宣称随后重新整套运行了93项。

源码、依赖、实际CLI检查及限制统一记录在[VALIDATION.json](../VALIDATION.json)。
这两份日志不证明实际内核模块编译、设备DMA、物理HDMI、HDR传感器或板级恢复。
局部属性保持原始输出字节；没有将未保存日志的先前代理执行回执补造成原始日志。
