# Quant→Entropy 同钟FIFO原型合同

2026-10-30；**已接入R4候选并通过实际生产Quant A/B功能短测；综合、P&R、STA、板级NOT_RUN。**
仅替换 `jpeg_quant_stream.u_token_fifo` 这个同PIX时钟、同private_rst_n的实例，不替换真实跨域FIFO。

## 数据、容量和清理

- token147bit：`{user[1:0],last,keep[15:0],payload[127:0]}`；HEADER user1，系数批user0，
  每块HEADER+8批，最后一批last1。helper不解释或缩减任何字段，均按握手保存。
- 四个既有 `td_sdp_ram40`，每个40×512；无新IP或RAM初始化。物理RAM注册读输出就是held输出，
  没有147bit source/输出payload FF，也不reset RAM内容。双9bit指针、10bit resident、1bit output_valid、
  3bit reset_release合计32bit显式控制。
- **总resident容量512词，包含held RAM读输出。** 正常满队列包含511个未读RAM词和1个held输出。
  满时允许同拍pop/push，同时读写不同RAM地址；测试覆盖环回。没有合法词时不发布m_valid。
  初次push经RAM写、预取后发布，允许启动延迟；稳定连续流每拍1词，满队列替换也每拍1词。
- s_valid/s_data在未握手时由上游保持；m_valid/m_data在stall时保持。实际push/pop只在valid&&ready。
  允许有限任意长度sink stall，满后真实背压Quant。s_ready在满时组合依赖m_ready以完成同拍替换，
  该新READY→写CE路径必须在后续综合/物理时序检查；这里不宣称时序闭合。
- i_rst_n断言异步屏蔽两个公开握手口并清release链；即使时钟停止也立即隔离。释放后必须经过3个
  真实本地时钟，指针/计数/valid在隔离窗口同步清理。旧RAM值只有在新写入后被新valid发布。
- cancel沿实际encoder接线：`private_rst_n=i_rst_n&&!aborting` 清Quant/FIFO；Entropy另用i_abort。
  encoder在aborting时强制Entropy的byte-ready=1，排空已暴露的旧字节。这条原有清理规则不变。

旧axis wrapper在其512深官方FIFO外还存在source_pending1词、read_buffer2词。原型保留宣称的512容量，
按本轮授权删除额外三词弹性；ready、初次valid和reset_done时刻并非逐拍等价。A/B比较接受的token顺序、
数值、取消后帧隔离和Entropy字节，不用相同时刻ready冒充等价。

## 专属短测与证据

命令（本机已登记Python/ModelSim/TD，TD路径显式传入）：

```powershell
& 'python' -B `
  refactor/hdr_lane_sparse/src_fpga/simulation/jpeg_sync_fifo/run.py `
  --td-root 'D:/App/TD_Release_2026.2.210.850' `
  --modelsim-bin 'D:/App/modelsim/win64' --name final_r8
```

run name必须新建，历史结果不覆盖。上述final_r8是最初原型证据名；生产接线后的复验使用新的actual_r4名。
沙箱启动ModelSim出现WinError623，已授权提升执行短测。
所有RAM、FIFO、DSP使用该TD根官方模型；仿真ROM端口适配来自候选冻结assets并按本地MIF生成run内初始化。
最初原型runner只在独立run生成改名Quant副本，生产jpeg_quant_stream.v保持原SHA。
采用后runner已经固定旧路为Git `928b426c07ecf0bc0f94c0aef708f9696541aa1e` 的Quant字节，SHA256
`9daf6876d4f7da0f03aeb35f98b3bdf274c4a02d6f52e296a39aaaa159ffa317`，仅改module名为
`jpeg_quant_stream_async_reference`；新路编译真正生产Quant。若生产未含新FIFO实例，runner拒绝运行，
避免两路都编成新FIFO。独立整数/Huffman参考仍保留。

- 叶测PASS：6198词全147bit逐词比对、总resident=512、2000拍满+pop/push II=1、empty、随机有限stall、
  1000拍末词stall、正常reset与停钟reset/cancel、地址回绕和零同址双口碰撞。
- 真Quant→Entropy A/B PASS：四帧各128块；quality75/37/1/100；restart0/1/3/2；两路各4608个
  token逐字等于独立整数除法/zigzag参考；Entropy分别4907/3459/2213/13002B，逐字等于独立Huffman参考。
  7000拍字节stall真实填满512、最后字节stall、实际private abort后从新帧完整恢复。
- 这是Entropy输出级验证，没有执行新JPEG formatter/完整MAIN、外部持续CSI或DDR竞争试验；不证明整机60fps。
- 证据：`refactor/hdr_lane_sparse/tmp/jpeg_sync_fifo/final_r8/RESULTS.json`，同目录两个tb日志。
  全部执行输入SHA运行前后相同；已知官方INIT_FILE字符串越界和未用ECC注入端口宽度告警保留，
  runner拒绝其他告警/错误。r1…r6是保留的准备/刺激修正失败；最终依据final_r8，不伪造旧轮成功。

原型helper SHA为`0ffe51b70f15209cfb5c1edd6af0aa5e409f26530bdb5e5b8c664608c0ae8a31`；
采用时仅将首行“Prototype only”改成“Production candidate”，当前SHA为
`aff514b88eeccbfe76a4f9a10a3ab2c1ceb121f5493272b2a4bc5f31a9bc9d09`。
这是comment-only变化，不改写旧资格；实际生产接线后另跑必要A/B并绑定新输入SHA。

实际生产接线复验 **actual_r4 PASS**：固定928b旧路与实际生产新路重复通过上述叶测、4608 token/路、
四帧23581B Entropy/路以及private abort恢复。140次告警全部属于上述两类已知官方模型告警，无其他告警或错误。
证据：`refactor/hdr_lane_sparse/tmp/jpeg_sync_fifo/actual_r4/RESULTS.json`，SHA256
`7df3b68c2dbb1d843b1eb9c7c6cc2214e088e61926a771c1e56badc1b31f6ad5`。
本次真实生产Quant SHA256为`07874868a40df0bd1fffd7db64b43118228777089901caf21c7293a7d56f9682`，
helper仍为上述`aff514…`；执行输入哈希在运行前后保持一致。生产接线/AL/清单由主代理完成，本代理未修改。

## 资源预期、接线与SDC

compact-r1旧实例层级u_token_fifo为85逻辑LUT、412FF、4ERAM。新helper显式控制32bit、同样4ERAM；
可实际移除source_word147bit、read_buffer294bit、source_pending/读缓冲指针、双域release/peer握手及
官方异步FIFO指针/复位控制。声明位宽不等于映射FF；旧实例已经常量裁剪，**净FF/LUT/Slice收益未综合**。

主代理决定接入后，仅需将原FIFO实例替换为：

```verilog
jpeg_quant_sync_fifo u_token_fifo (
    .i_clk(i_clk), .i_rst_n(i_rst_n),
    .s_data(token), .s_valid(i_rst_n && token_valid), .s_ready(fifo_ready),
    .m_data(o_token_data), .m_valid(o_token_valid), .m_ready(i_token_ready),
    .o_reset_done(), .o_resident());
```

再在该候选生产清单/实际AL登记新helper；保留td_sdp_ram40及其现成官方RAM注册。
其他仍使用axis_frame_fifo_ip的真CDC实例及官方FIFO源/IP不能因此删除。

当前实际SDC没有 `u_jpeg/stream$u_quant/u_token_fifo` 专属对象，因此没有对应专属例外要删除。
`u_jpeg_to_ddr/u_token_fifo/fifo/*` 是PIX→DFI真CDC：stream_cdc.sdc第255–257、302、474–477等
路径均属于该桥，必须保留。其他`source_reset_release_pipe`不能按名字通配删除。
新helper的普通同钟RAM数据、计数、READY路径正常计时；不添加false path或假同步器。
