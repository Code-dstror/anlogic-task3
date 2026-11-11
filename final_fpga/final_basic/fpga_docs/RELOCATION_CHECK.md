# 目录迁移检查（2026-11-11）

以下记录初始目录迁移时的验证结果。当前文件哈希见 `SOURCE_BINDING.json`；其中39份生产文件随后只调整了生成注释，有效代码内容保持，可用文末脚本复核。

固定源camera_raw_r2 / 1a5603c1，全部生产输入405项、冻结IP158项逐文件SHA相同。
完整本候选RTL/IP/仿真源及协议、SDK和工具参考1353项按固定Git导出，复制身份检查通过。
TD .al仅将源码/include/约束路径改为新目录相对路径；宏、器件、顶层、注册顺序和运行策略未改。
所有253项文件注册与5条include路径均存在，且全部落在final_basic内部。

原生TD2026.2 read_design完成，导出非空elaborate DB，0个新error marker，随后关闭并重新打开同一个.al成功。
原生wait_run为37.256秒；这是read_design检查，不是完整综合或功能仿真。源检查、命令和日志在relocation_evidence。
TD保存时写入绝对Project Path；已核对除根路径/换行外无其他变化，再恢复交付的Path="."。
新生成的可重建Runs/TD临时日志移至仓库tmp/final_basic_20261111/native_preserved保留，final_basic内不携带已完成综合或布局布线状态。

已有seed25 bit及其四类STA资格来自原1a5603c1服务器任务，不由本次read_design重新产生；bit SHA一致。
未进行新的综合、P&R、bitgen、功能仿真或板级操作。原调试包全部149份制品已验哈希；本目录只附关键时序/资源报告和运行日志，完整归档仍保留在原deliverables和server下载目录。
原始GitHub索引的pending状态属于历史回传，9项已经用户手动包补齐，详见MANUAL_RECEIPT。

可在任意位置运行 `python fpga_prj/al/tools/verify_sources.py` 复核生产输入、所有源码副本、独立路径及唯一bit。
