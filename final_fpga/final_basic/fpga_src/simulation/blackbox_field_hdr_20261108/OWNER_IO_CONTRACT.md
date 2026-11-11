# 双目 HDR 存储配对公开合同

独立验证以外部握手为依据。仅阅读本合同、自建 testbench 和公开端口日志。生产 RTL、旧 testbench、IP 与厂商模型的实现均为不透明编译输入。基线是 `81404aec1727e16f3df7424a74c5f960ad3d6683` 的生产 `hdr_eye_shared`，改版使用当前工作树同一模块。此短门验证两眼的真实配对、目录、作业交付与 bank 退休，曝光写端以及后级作业消费者是 BFM。

## 公开接口

```verilog
module hdr_eye_shared #(parameter integer WIDTH=1920, HEIGHT=1080)(
    input wire clk,rst_n,stop,transport_fault,input wire [63:0] now_ns,
    input wire config_valid,output wire config_ready,output reg config_error,
    input wire [31:0] cfg_session,cfg_epoch,cfg_delta,cfg_wait,cfg_age,
    input wire [2:0] cfg_ratio,input wire cfg_hdr,
    input wire [767:0] frames,input wire [1:0] begin_valid,member,
    output wire [1:0] begin_ready,accepted,
    output wire [3:0] capture_slots,output wire [31:0] camera0_generation,
    output wire [63:0] camera0_lease,
    input wire [3:0] finish_valid,finish_ok,output wire [3:0] finish_ready,
    output wire [1:0] pair_valid,pair_bank,output wire [127:0] pair_ids,input wire [1:0] pair_take,
    input wire [1:0] release_valid,input wire release_bank,input wire [63:0] release_id,
    input wire read_quiet,ticket_released,input wire [1:0] write_quiet,
    output wire [1:0] release_ready,
    input wire [1:0] ext_req,ext_slot,ext_consume,output wire [1:0] ext_ready,ext_valid,ext_last,
    output wire [63:0] ext_data,output wire [7:0] ext_word,output wire [1:0] empty,output wire fault
);
```

- 全部信号在 DFI `clk` 的正沿采样，`rst_n` 为冷身份异步低有效复位。测试在下降沿释放复位及驱动输入。复位完成后先配置，再输入事务。`now_ns` 单调，真实 DFI 周期约 7.5 ns；短测可用递增的逻辑纳秒模拟长间隔。正常时间戳无需跳变，直接取取证时基内的合法值。
- 生产 1920×1080，短测 16×4。提交非零 session、独立 epoch，`cfg_hdr=1`、`cfg_ratio=4`、`cfg_delta=50_000_000`、`cfg_wait=100_000_000`、`cfg_age=1_000_000_000`，保持到 `config_valid && config_ready`。随后可观察一拍 `config_error`，合法配置为零。短测保持时间推进远小于 `cfg_wait` 来区分正常前进和等过期的假恢复。空闲的新 epoch 允许重新开始本队列；相同 session/epoch 的幂等配置保留已知的序列约束。
- `frames[eye*384+:384]` 为输入描述符，`member[eye]=0/1` 为 LONG/SHORT。每眼一个 BEGIN offer，`frames`、`member` 和 `begin_valid` 保持到该眼 `begin_ready` 的上升沿。`accepted[eye]` 是该握手的结果电平，同拍 `capture_slots[eye*2+:2]={bank,role}` 有效。可以两眼同时提供 BEGIN。每眼的两曝光有独立生产通道，可以以任一角色先送达该层。每个 `(eye,role)` 的真实组号、VC 序号和时间依先后顺序推进。两个摄像头相同的 group/sequence 可并行；两个 VC 的 sequence 不要求相同。生产 group 非零，每眼由真实 LONG FS 按序分配，物理计数器饱和后身份故障。组号不重复。普通环绕测试若采用非生产源，只定义 32 位开半范围内的组先后顺序，跳零。
- 描述符从零开始，设置 `[0]=1`、`[2:1]=1` LONG 或 `2` SHORT、`[3]=1`（物理源）、`[4]=eye`、`[76:45]=session`、`[108:77]=sequence`、`[140:109]=epoch`、`[204:141]=capture_time_ns`、`[220:205]=WIDTH`、`[236:221]=HEIGHT`、`[238:237]=1`、`[270:239]=32'h56a3d02f`、`[302:271]=3200` LONG 或 `200` SHORT、`[334:303]=256`、`[366:335]=group`，其余清零。`capture_time_ns` 必须在 `(now_ns-cfg_age, now_ns]` 内，每 lane 单调。SHORT 时间须大于等于同组 LONG 时间，且两者差值不超过 `cfg_delta`。
- 每个接受的 BEGIN 由真实 writer 在匹配的正/负 SOURCE 和真实 DDR B 排空后完成。测试 BFM 代表此边界，只给已接受成员送 `finish_valid[eye*2+role]`，保持到相应的 `finish_ready` 握手。`finish_ok` 同拍有效；被拒 BEGIN 不产生 FINISH。四个 writer 可独立或同拍完成。负终态不能生成成功配对。
- 一眼两 bank，两个真实曝光都成功 FINISH 才可发布 `pair_valid[eye]`。最老完整配对先获得服务，较新的配对不能抢占仍可合法完成的较老配对。常规工作时 `pair_bank` 与 `pair_ids[eye*64+:64]` 在 `pair_valid` 下保持至 `pair_take`，STOP/换配置/故障可撤销未接受 offer。对照两眼可能重合的 group/sequence 时，使用目录中的 camera、session、epoch、LONG sequence 与 group 判别每个 pair。pair ID 非零、分眼、在正常身份范围内不复用，不能把 ID 差值当作 SOURCE 或作业数。
- 配对消费者一次只能取得一个全局共享后处理作业。取得后通过所获眼的 `ext_req[eye]` 请求 `ext_slot={pair_bank,1'b0}` 读取 LONG 描述符。读请求保持到该眼 `ext_ready`。响应每拍 `ext_valid[eye] && ext_consume[eye]` 取对应 `ext_data[eye*32+:32]`，`ext_word[eye*4+:4]` 为 0 至 15，`ext_last` 仅字 15；反压时有效数据保持。字 0 的 `[4]` 为 camera、`[2:1]` 为角色，字 1 generation，字 2 session，字 3 sequence，字 4 epoch，字 5/6 为时间低/高字，字 7 `{HEIGHT, WIDTH}`，字 11 group，字 12/13 lease 低/高字。以接口定义和激励原身份为期望。
- 停止借用与读完目录后，提供相同 `release_bank`/`release_id` 及 `release_valid[eye]`。保持至该眼 `release_ready` 握手，真实读、产品和票据须已排空，测试置 `read_quiet=1,write_quiet[eye]=1,ticket_released=1` 代表这些义务。取得作业和实际退休是两次握手。另一 bank 的已授予成员可持续持有 FINISH 债务；本模块的 `write_quiet` 代表上层已给定的合法释放门。新配对不能覆盖未退休 bank。错误身份释放应故障，保留原 bank。STOP 期间禁止新正 BEGIN，正常既有写、读取和合法 RELEASE 仍按真实握手排空。未完全写过的组不应产生作业。

## 现场风险及外部期望

观察到稳定 HDR 同一眼约每六个真实 SOURCE 序号仅有相邻两个产品，重新入 HDR 后可能换眼。本短门重点模拟 BEGIN、共享作业消费和 RELEASE 交错，保留两眼可交换性。

1. 合法首对到真实公开终态。两眼各送合法 LONG/SHORT，独立 FINISH；消费每对的真实目录并用相同 ID 退休，继续连续下一对。可交换哪眼先完成、哪眼首成员为 SHORT，以及在另一眼占用共享消费者时本眼完成的顺序。至少一组经有限目录反压。每个完整有效输入仅发布一次，身份逐项匹配。
2. 容量拒收与迟到成员。使本眼有两个未退休 bank，令下一组的首成员收到明确的负 BEGIN，随后合法退休旧 pair，才提交这个被拒组的另一曝光。这个曝光也应得到负 BEGIN，无论此时是否有空 bank，且不可让下一组正常曝光对等到 `cfg_wait`。对两眼角色互换；在具有正常服务余量的后续连续组，全部接受、发布并退休。至少使用一次带有两个连续被拒组且较老 peer 随后才到达的合法 lane 顺序，避免只验证最后一个组。
3. 现有合法组的完成。让本眼有一个未退休配对和另一个仅已接受首成员的组，后一新组首成员因容量被拒后，再提供较老组的对端。已获授予的较老组应接受对端，两个 FINISH 完成后正常发布，不能因新组被拒而误杀。保留两个角色相反的先到顺序与本眼后续恢复。
4. 真实释放与容量检查同时接近。用有限的 BEGIN/合法 RELEASE 相位扫，必须有旧 bank 实际完成退休才可复用。若容量判断与可完成的释放重合，允许短有界重新判断同一 BEGIN；禁止用预计的未来 RELEASE 覆盖已借用 bank。长时满载可显式拒收，继续服务另一眼。本短测不为满幅 DDR/FIFO 吞吐签收。

## 定向用例补充判据

- 合法 RELEASE 握手与新 BEGIN 首次呈现同拍时，除容量外合法的 BEGIN 应得到正答复。若 RELEASE 晚于 BEGIN，已呈现的拒收答复仍成立，且该组对端不能另建 bank。相位扫以公开 RELEASE 握手确认实际退休。
- 若真实负 FINISH 已发生后才呈现同组对端 BEGIN，应拒绝该 BEGIN。已经获得正答复的对端仍须完成 FINISH，坏组回收后允许健康新组进入。
- STOP 期间可暂缓 BEGIN 答复，已经承诺的 writer、目录读取和 RELEASE 正常排空。撤销 STOP 后保持 session 和 epoch，继续提交序号前进的健康组。
- `camera0_generation` 和 `camera0_lease` 在相应的 camera0 BEGIN 正握手采样，随后核对 LONG 目录的同一身份。组号回卷用例在 `0xffffffff` 后跳至 1，VC sequence 独立前进。

## 不透明编译输入

仓库根为 `C:/fpga_workspace/anlogic-task3`。`rtl=refactor/camera_raw_r1/src_fpga/rtl`，`ip=refactor/camera_raw_r1/src_fpga/ip`，`td=D:/App/TD_Release_2026.2.210.850`。编译和仿真使用 `D:/App/modelsim/win64` 的 ModelSim SE-64 2020.4。

- `vlog -work ph1` 编译 `td/sim_release/common/al_phy_glbl.v`、`td/sim_release/ph1/ph1_logic_dram.v`、`td/sim_release/ph1/ph1_logic_eram.v` 和 `td/sim_release/ph1/ph1_phy_eram.v`。
- `vlog -sv +define+PH1 +incdir+<rtl>/include/04_include` 编译 `td/sim_release/ph1/ph1_phy_gsr.v`、`ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v`、`rtl/td_sdp_ram40.v`、`rtl/hdr_pair_directory.v`、`rtl/hdr_eye_shared.v` 和新 testbench。先 `vlib ph1`、`vlib work`，`vsim -c -L ph1 work.PH1_PHY_GSR work.<tb> -do "run -all; quit -f"`。端口声明为可用于基线和改版实例化的共同子集；可不连接改版新增的观测输出。
- 每个用例设置仿真 watchdog 和不超过 60 秒墙钟 watchdog。新建独立目录，保留编译与原始 FAIL/PASS 日志、准确 argv、参数、前后源/模型/TB SHA256。`run.py` 从固定提交不透明导出基线 RTL、IP 与头文件字节，候选版从工作树制作独立编译快照。若编译诊断含实现行，由实现维护者定位。
