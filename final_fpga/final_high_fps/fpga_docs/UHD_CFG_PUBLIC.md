# 冷态单目 UHD 配置接口

`mono_config_service_v2` 保留 `PROFILE=1, MAX_WIDTH=1920, MAX_HEIGHT=1080` 的 HD 基准。整机打开 `UHD_COLOR_ENABLE=1, UHD_PREPROCESS_ENABLE=1`，连接 `i_uhd_mode_user` 和 `i_uhd_mode_pixel`。两个输入分别在 USER 和 PIX 本域有效，表示已经应用的冷档。旧调用默认关闭 UHD 扩展；只打开前者仍保留上一版 COLOR-only 合同。配置 FIFO 和 1184 位请求/ACK 元组沿用现有布局。尺寸由本域选择冻结到采集和产品描述符。

冷档控制端只在 APP/C2H 启动前、CFG 事务空闲且当前 ACTIVE 是基础 COLOR SDR 时切换。USER 与 PIX 应用期间阻止 CFG 写入，直到两域对同一冷档完成应用。一次 CFG 从 PREPARE 到终态期间保持两个输入稳定。PIX 整包 ACK 仍由真实远端捕获/DFI owner 在满足旧工作排空后返回。运行期 APPLIED 以目标档位首个实际接受的 CAM0 帧为边界。停流配置只可使用原合同明确允许的实际传感器边界。等待新首帧时，新的共享处理工作可以已开始。

| USER 回读 | UHD 选中 |
| --- | --- |
| `CFG_COMPILED_PROFILE` | `MONO3840=3` |
| `CFG_CAMERA_PRESENT` | `1`（CAM0） |
| `CFG_MAX_WIDTH`, `CFG_MAX_HEIGHT` | `3840`, `2160` |
| `CFG_FEATURES` | 生产 `0x7f`，含共享 Y、native RAW14 ISP 和画质 bit 6。关闭 `QUALITY_CONTROL_ENABLE` 时为 `0x3f`，关闭预处理则相应减去 `0x30` |
| `CFG_EXT_SUPPORTED`, `CFG_EXT_STRIPS`, `CFG_EXT_COMBINATIONS` | `0`, `0`, `0` |
| `CFG_EXT_SCHEMAS`, `CFG_EXT_V2_MODES`, `CFG_EXT_V2_ENABLES` | `4`（schema2），`1`（SDR），`0x0d`（GRAY、GAUSSIAN_IMAGE、HISTOGRAM）；COLOR-only 参数档 enables 为 `0` |

UHD 接受 `PREPARE` 的基础 COLOR、GRAY、GAUSSIAN、HISTOGRAM（模式码 0–3）。GAUSSIAN 保持旧协议的灰度高斯语义，HISTOGRAM 保持原色 HE。`PREPARE_EXT` 接受 schema2 SDR，base mode 必须 COLOR，处理使能为 `0x0d` 的任意子集。扩展 word0 为 `2 | (enables << 10)`。默认 W1/W12 为零，开启手动 WB 时按 [画质字段合同](RK_QUALITY_CONTROLS.md) 填写，Tone 与 fusion 仍为零。其他扩展字为零。顺序为 WB/ISP 后灰度选择、Gaussian、时域 HE。未选灰度时 Gaussian 保留原色。RAW 仍为未处理的传感器数据，在线 CFG 用于 JPEG 路径。

质量、adaptive/minimum、预算、restart 和 host capability 的字段范围与原 ABI 一致。非 SDR 产品模式、dehaze/multiscale/lane 使能或旧扩展 feature 返回 `CFG_ERROR_UNSUPPORTED=5`，结束 BUSY 并保留旧 ACTIVE、epoch 和首帧序号；相同会话随后可提交合法请求。无效 session、请求标量和保留字段按相应原错误处理。COLOR-only 参数档继续拒绝非 COLOR 或非零 enables。现有 RAW 导出期间的 CFG 写资格由顶层仲裁。

恢复范围补充：PREPARE阶段的UNSUPPORTED/字段拒绝可以在同一会话改为合法请求后继续。
匹配远端整包ACK为负，或ACK后等待首帧期间出现适用source fault，则返回RESET=6，并隔离数据/配置应用，
要求协调cohort reset和重新BOOT后恢复；它不承诺同一会话继续提交成功。远端可能已经部分改变物理状态，
不能只清一个本地错误位就重用该会话。最初交接曾错误地把这两种恢复范围合并，相关短测FAIL保留为合同修正证据。

独立短测使用 [CFG FIFO 公开接口](../../camera_raw_r2/docs/fieldfix_20261109/CFG_TRANSITION_PUBLIC.md) 的生产 HD 参数，再打开两个 UHD 参数。以真实 BAR→FIFO→PIX→FIFO→BAR 完成四种 scalar 和全部八种合法 schema2 enables，验证真实整包 ACK 之前及实际首帧之前 ACTIVE 不变，ACK 后首帧与 pipeline busy 同拍仍正确 APPLIED。对 HDR、去雾、lane、multiscale、legacy HDR、非法保留字与错/旧/负 ACK 注入；检查拒绝/隔离与各自恢复边界。cold 档只在 transaction idle 且 ACTIVE 基础 COLOR 时改变，回读 HD 双目能力并至少完成一个原 HD 事务。该控制测试不代替像素数学和整条产品链。
