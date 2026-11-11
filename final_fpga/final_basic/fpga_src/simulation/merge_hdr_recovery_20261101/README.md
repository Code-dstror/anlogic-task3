# HDR完整仿真的一次夹具恢复

原`merge_integration_20261101`及测试锁7054、失败run和原STATE保持只读；SDR已PASS，不重跑。
旧HDR完整run实际完成8good/重叠、SOURCE10、RAW14/ISP、JPEG、USER_LAST、SAFE/ACK、
PAIR_RELEASE与QUIET后，失败于新增夹具错误的`raw_commits==2`。旧FAIL不改成PASS。

实际`full_raw_store.v:483` legacy `o_commit_valid`只观察LONG/member0写完成。
SHORT使用独立的`finish_valid1 && hdr_finish1_ready && finish_ok1`，owner双端口分别退休。
新断言要求两个真实member finish各成功1次、每项descriptor的role/session/epoch/sequence/group
与输入SOURCE一致、pair acquire前两者均完成、legacy LONG commit1次及pair acquire1次。
原始完整RAW/RAW14/T96/独立JPEG逐字节/解码/v4/SAFE-ACK/回SDR检查全部保留。

`contract`使用实际小尺寸full_raw_store、双成员真实ingress/FIFO/writer/owner，仅AXI写响应为
边界模型；实际观察finish1/1、legacy1、pair acquire1、AW2/B2，禁止force成功。
新完整长测独立run为`tmp/extended_hdr_recovery_20261101/hdr_recovery_r1_full`。
新测试锁为`docs/EXTENDED_SIMULATION_20261101.hdr_recovery.lock.json`，仍固定生产seal9f1be。

Hidden Preflight通过后才Hidden Launch；最多1并行，只启动HDR一次，case含oracle最多10800秒，
且不得超过原总截止epoch1793534251.7473004，即2026-11-01 19:57:31.747300+08。
没有可用真实checkpoint，因此完整重跑8次retained-good预热，不能伪造从成功阶段恢复。
新的唯一活动状态`tmp/extended_hdr_recovery_20261101/STATE.json`交原15分钟任务监督。
旧控制器、旧STATE、原SDR自动任务、服务器和板卡均不操作。
