# RFSoC 差分 QPSK 接收机移植与验证报告

## 1. 项目目标

本项目在不修改既有 RF Data Converter 配置和原始 RFDC→聚合器→DMA
采集链路的前提下，参考 GoWinSDR v1 的 QPSK 接收结构，在 AntSDR T510
的 RFSoC 工程中增加一条独立数字接收支路。

最终接收链为：

```text
RFDC 四路并行复数采样
    ↓
4 相多相抽取 FIR
    ↓
RRC 匹配滤波
    ↓
Costas 载波同步
    ↓
三阶 Farrow 小数延时插值
    ↓
Gardner 符号定时同步
    ↓
差分 QPSK 判决与解码
```

当前 RTL 已加入 `antsdr_t510_standalone.xpr`，顶层封装
`gowinsdr_rx_chain` 已作为 module reference 实例化到 `T510_design.bd`。
该支路目前是观察和验证支路，原始 DMA 数据通路保持不变。

## 2. 数据率和并行接口的理解

现有 RFDC 配置对应：

- ADC 射频采样率：4.9152 GSPS；
- RFDC 内部抽取：20；
- RFDC 输出复数采样率：245.76 MSPS；
- PL 时钟：61.44 MHz；
- 每个 PL 时钟并行输出 4 个连续复数样本；
- 当前符号率：5.12 Msymbol/s；
- 抽取后采样率：61.44 MSPS，即每符号 12 点。

“一个时钟有 4 个 IQ”表示接口并行度为 4，并不表示 4 路独立信号，也不应
简单丢掉其中 3 个样本。正确处理是把 4 个连续时刻的样本看成 FIR 的 4 个相位，
在一个 PL 时钟内完成一次 4 倍抽取，最终每拍输出 1 个 61.44-MSPS 复数样本。

这也是 `rx_polyphase_decim4.v` 单独存在的原因：它把“高速串行采样问题”转换为
“低速时钟下的并行多相运算问题”。

## 3. 各级数据处理流程

### 3.1 四相多相抽取

抽取器使用 44 阶 Q1.17 系数量化 FIR：

- 输入：每拍 4 个 16-bit I/Q；
- 输出：每拍 1 个 16-bit I/Q；
- 抽取比：4；
- 通带：8 MHz；
- 阻带起点：30.72 MHz；
- 量化后通带纹波约 0.046452 dB；
- 阻带衰减约 82.537 dB。

多相实现与“先用高速 FIR，再每 4 点取 1 点”在数学上等价，但适合当前
61.44-MHz PL 时钟和 4 样本并行接口。

### 3.2 RRC 匹配滤波

匹配滤波器使用：

- 121 taps；
- Q1.17 系数；
- roll-off `beta=0.35`；
- 12 samples/symbol；
- 5.12 Msymbol/s。

发射端和接收端 RRC 组合后形成升余弦响应，用于限制带宽并降低符号间干扰。
抽取 FIR 和 RRC 系数之和均被校正为 131072，因此在右移 17 bit 后具有单位
直流增益，便于分析整个链路的幅度标度。

### 3.3 Costas 载波同步

Costas 环负责消除残余载波频偏和相位偏差。检相器采用 QPSK 判决导向形式：

```text
error = sign(I)·Q - sign(Q)·I
```

环路 PI 参数参考 GoWinSDR MATLAB 模型的设计点：

```text
zeta = 0.707
BnTs = 0.01
```

误差以 `|I|+|Q|≈8192` 为标称幅度，通过饱和左移 2 bit 映射到 Q1.15。
这样避免了在反馈路径上综合出逐样本可变除法器。

NCO 使用 32-bit 相位累加器和 256 相位点 Q1.15 正弦/余弦表。25-kHz 单独
频偏测试的尾段估计值为 25.098 kHz。

### 3.4 Farrow 小数延时插值

GoWinSDR 的 Gardner 路径不是简单选择最近的整数采样点，而是在 TED 前使用
Farrow 插值。移植中保留了其三阶多项式：

```text
f1 = 0.5x(m) - 0.5x(m-1) - 0.5x(m-2) + 0.5x(m-3)
f2 =-0.5x(m) + 1.5x(m-1) - 0.5x(m-2) - 0.5x(m-3)
f3 = x(m-2)
y  = f1·mu² + f2·mu + f3
```

`mu` 是 Q1.15 小数间隔。插值器被实现为独立模块
`rx_farrow_interpolator.v`，乘法链进行了流水化，能够保持每拍接收一个复数样本。

### 3.5 Gardner 定时同步

定时同步采用半符号 NCO，每个符号产生“中点”和“最佳判决点”两次插值事件。
Gardner TED 为：

```text
e(k) = I(k-1/2)[I(k)-I(k-1)]
     + Q(k-1/2)[Q(k)-Q(k-1)]
```

环路滤波形式沿用 GoWinSDR 的增量结构：

```text
w(k+1) = w(k) + Kp[e(k)-e(k-1)] + Ki·e(k)
```

但不能照搬 GoWin 工程中的 NCO 初值和位移常数，因为其注释对应约
200 samples/symbol，而本工程是 12 samples/symbol。当前名义半符号 NCO 步进为：

```text
2^32 / 6 = 715827883
```

PI 系数也重新换算到本工程的相位字域。

### 3.6 差分解码

判决器根据同步后的 I/Q 正负得到两个状态 bit，再与上一个符号状态异或得到
差分数据。`symbol_valid` 是唯一的数据有效条件，因此 FPGA 内部不需要另外恢复
一根物理“位时钟”。

需要注意：QPSK Costas 环天然存在 0°、90°、180°、270°四象限模糊。
当前 I/Q 两路分别差分的编码可以自动抵消 180°反相，但 90°锁定会交换 I/Q
两个解码 bit 通道。真实通信帧必须用已知前导码或同步字确定是否需要交换通道。

## 4. MATLAB 与 RTL 联合验证方法

验证流程不是只看最终波形“像不像”，而是建立了可执行的端到端基线：

```text
随机差分QPSK数据
  → 发射RRC
  → 物理/理想信道
  → 16-bit ADC量化
  → 每拍4复数样本打包
  → MATLAB逐位宽定点接收机
  → 生成每一级expected向量
  → xsim运行同一输入
  → 每一级逐样本比较
```

xsim 同时检查：

- 多相抽取输出；
- RRC 输出；
- Costas I/Q、频率字和相位字；
- Gardner/Farrow 符号、误差和 NCO 步进；
- 差分解码输出。

这比只检查 BER 更重要。若最终 BER 错误，逐级比较可以快速区分：

1. MATLAB 算法本身不能恢复；
2. 定点量化或溢出有问题；
3. Verilog 与 MATLAB 运算次序不同；
4. valid/流水延迟错位；
5. 算法正确但综合时序不满足。

## 5. 移植中遇到的问题和解决办法

### 5.1 把并行度误认为抽取

最初最容易产生的误解是“一个时钟 4 个 IQ，是否抽掉 3 个变成每拍 1 个”。
直接抽点会在抽取前产生混叠。解决办法是使用 4 相多相 FIR，让 4 个输入样本都
参与滤波和抽取。

经验：先写清楚采样率、时钟率、并行度和符号率，四者不能混用。

### 5.2 GoWin HDL 与 MATLAB 参数并不完全一致

GoWinSDR 提供了成熟的结构，但部分 HDL 注释、位宽和 MATLAB 参数之间并非完全
一致。例如 Costas HDL 使用原始幅度域误差，而 MATLAB 使用归一化环路设计；
Gardner NCO 常数又与本项目的 12 SPS 不匹配。

解决办法是：

- 继承已经验证过的算法结构；
- 从 MATLAB 公式重新推导本项目的定点参数；
- 不直接复制与采样率、幅度和位宽绑定的常数；
- 用端到端向量证明重新换算后的结果。

经验：参考开源项目时，要区分“结构可复用”和“数值可照搬”。

### 5.3 Costas 能仿真但不能满足时序

第一版为了让环路增益不随幅度变化，使用：

```text
raw_error·2^15 / (|I|+|Q|)
```

功能仿真完全正确，但 Vivado 综合出的可变除法器位于反馈路径，最差 WNS 约
`-16.071 ns`，远不能工作在 61.44 MHz。

根据实际 RRC 输出幅度统计，`|I|+|Q|` 中位数约为 8k～10k，因此改用 8192
作为标称幅度，把除法化为饱和左移 2 bit。结果：

- MATLAB/RTL 仍逐级一致；
- CFO 和综合损伤 BER 为 0；
- WNS 恢复为正值；
- LUT 数量下降。

经验：行为仿真通过不代表硬件结构合理。反馈环中的除法、长乘加和变量移位必须
尽早综合检查。

### 5.4 64 点 Costas NCO 在短帧中隐藏了问题

64 点正弦表在 512 符号测试中可以得到 BER 0，但现实物理损伤和 2048 符号长帧
暴露出残余频率估计偏差。将 NCO 提高到 256 相位点后，25-kHz 测试估计改善到
25.098 kHz，并由 Vivado 自动映射为一个 BRAM tile。

经验：短帧可能掩盖很小的频偏，因为相位误差尚未积累到判决边界。同步环必须用
长帧验证。

### 5.5 初版 Gardner 只在短测试中“看起来能用”

初版定时环只选择整数采样点，并按误差正负对 NCO 步进执行固定 `±256` 调整。
短帧、100 ppm 测试可以通过，但在 2048 符号、±500 ppm 时 BER 接近随机。

解决过程：

1. 对照 GoWinSDR，确认应为 Farrow→TED→环路滤波→NCO；
2. 把 Farrow 单独实现并建立 bit-exact MATLAB 模型；
3. 用正规增量 PI 取代 bang-bang 调整；
4. 分别测试 +500 ppm 和 -500 ppm，检查环路方向；
5. 加入流水线排空建模，解决最后一个符号的仿真差异。

最终正负 500 ppm 长帧均为 BER 0。

经验：时钟偏差是持续积累量。只有初始小数偏移的短帧测试，不能证明定时环能跟踪
真实采样时钟误差。

### 5.6 MATLAB 和 RTL 只在最后一个符号不同

Farrow 乘法链流水化后，RTL 在 `in_valid` 拉低后仍会输出已经进入流水线的数据，
而 MATLAB 最初在输入数组结束时立即停止，造成最后一个符号不一致。

解决办法是在 MATLAB 定点模型中显式排空已经启动的 4 级流水线，同时禁止在没有
未来输入样本时启动新的插值请求。

经验：定点参考模型不但要模拟算术，还要模拟寄存器更新顺序、valid 延迟和流水线
排空行为。

### 5.7 现实信道下出现约 48% BER

加入多径、相位噪声、IQ不平衡等现实因素后，星座图已经形成清晰四簇，但直接 BER
约为 0.483779。逐级观察发现载波和定时环均已锁定。进一步测试 I/Q bit 通道交换后
BER 变为 0，证明问题是 Costas 的 90°象限模糊，不是接收失败。

经验：看到 50% BER 不应立刻调整环路增益。先看星座、频率字、定时步进和符号数量，
再检查相位模糊、bit 映射、通道交换和帧对齐。

### 5.8 xsim 快照被 GUI 锁定

GUI 打开时，`xelab` 无法覆盖同名 snapshot。开发中曾因此出现
`xsim.type for writing` 错误。解决方法是关闭 GUI，或使用新的独立 snapshot 名称。
最终脚本使用 `rx_chain_snapshot_timingfix`。

经验：仿真失败不一定是 RTL 错误，应先区分编译错误、快照锁定、向量错误和运行期
比较错误。

## 6. 现实物理信道注入结果

新增两组可重复的 2048 payload-symbol 场景。

`physical_lab` 包括：

- 18 kHz CFO、0.55 rad 初相；
- 18 dB SNR、35 ppm；
- 0.02 RFDC sample RMS 抖动；
- 20 Hz Wiener 相位噪声线宽；
- 0.7 dB IQ增益不平衡、2°正交误差；
- I/Q DC偏置 +120/-90 codes；
- 4%慢衰落、4% RMS带内CW；
- 三径信道和 ±9500 codes ADC削顶。

`physical_stress` 将条件加重到：

- 40 kHz CFO、1 rad 初相；
- 12 dB SNR、200 ppm；
- 0.05 sample RMS 抖动、80 Hz相位噪声；
- 1.5 dB IQ不平衡、5°正交误差；
- 更强多径、衰落、CW和 ±8000 codes削顶。

两组结果均为：

- MATLAB 定点模型和 RTL 所有检查级零差异；
- 25344 个 RFDC 输入时钟；
- 约 2111 个解码符号；
- 原始 BER 约 0.483779（90°锁定导致通道交换）；
- I/Q象限消歧后 BER 0。

## 7. 最终验证和资源结果

十一组场景均通过 MATLAB/RTL bit-exact 回归：

- baseline；
- phase_only；
- cfo_only；
- timing_offset；
- clock_offset；
- awgn_20db；
- combined；
- timing_ppm_plus500；
- timing_ppm_minus500；
- physical_lab；
- physical_stress。

最终独立综合结果：

| 项目 | 结果 |
|---|---:|
| 目标器件 | xczu47dr-ffve1156-2-i |
| 目标时钟 | 61.44 MHz |
| WNS | +7.870 ns |
| TNS | 0 |
| Setup failing endpoints | 0 |
| LUT | 3449 |
| Registers | 7760 |
| DSP48E2 | 458 / 4272 |
| Block RAM | 1 tile（2×RAMB18E2） |

这些是独立接收链的综合后内部时钟结果。完整 BD 的 place-and-route 时序仍需在最终
implementation 后签核。

## 8. FPGA/DSP 学习经验总结

### 8.1 先统一“时间”的定义

设计前应明确：哪个量按 ADC sample 更新、哪个按 PL clock 更新、哪个按 symbol
更新。并行接口很容易让采样序号和时钟序号混淆。

### 8.2 先建可执行参考，再写 RTL

MATLAB 不只是画理想曲线，而应明确模拟：

- 位宽；
- 符号扩展；
- 舍入或截断；
- 饱和或回绕；
- 寄存器旧值/新值关系；
- valid 和流水线延迟。

只有这样的模型才能作为 RTL 的真正 golden reference。

### 8.3 每一级都留下可观测状态

同步环不能只看最终 bit。至少应观察：

- Costas `frequency_word`、`phase_word`；
- Farrow `mu` 和插值输出；
- Gardner `timing_error`、`timing_step`；
- 每帧输出符号数量。

这些信号在仿真中用于定位问题，板上则应接入 ILA。

### 8.4 算法参数和硬件幅度标度不可分离

同一个 Kp/Ki 在浮点单位幅度模型中稳定，不代表直接乘在 16-bit ADC code 上也稳定。
必须明确误差的 Q 格式和标称幅度，再把环路系数换算到相位字或步进字域。

### 8.5 功能验证和时序验证必须并行推进

本项目的可变除法器说明：完全 bit-exact 的功能实现仍可能是不可用的硬件。
每加入反馈运算、级联乘法或大查找表，都应立即综合查看 WNS、DSP和BRAM映射。

### 8.6 测试要从单因素到组合因素

推荐顺序：

```text
无损基线
→ 单独相偏
→ 单独频偏
→ 单独定时偏移
→ 单独ppm
→ 单独噪声
→ 组合场景
→ 长帧
→ 多径/IQ/相噪/干扰/削顶等现实场景
```

这样一旦失败，可以知道是哪一类环路或标度引起，而不是在所有因素同时存在时盲目
调参。

### 8.7 “解调成功”和“通信系统完整”不是同一件事

当前链路已经能够恢复物理层符号，但真实系统仍需要：

- 已知前导码；
- 帧同步；
- 自动象限消歧；
- 可能的 AGC；
- 多径较强时的自适应均衡；
- CRC/丢帧判断；
- AXI-Stream 或 DMA 输出协议。

## 9. 后续建议

建议按以下顺序继续：

1. 定义发送帧格式和已知前导码；
2. 增加帧相关器和自动 0/90/180/270°象限判断；
3. 将 Costas、Gardner、相关峰和解码数据接入 ILA；
4. 运行完整 BD synthesis、implementation 和 timing sign-off；
5. 生成 bitstream，在板上回放 MATLAB 生成的 DAC/ADC 测试波形；
6. 根据板上输入幅度确定 AGC目标值和 Costas检相器标度；
7. 如果真实多径超过当前测试范围，再加入 CMA/判决导向均衡器。

## 10. 主要文件

- `rx_polyphase_decim4.v`：4 相抽取；
- `rx_matched_rrc.v`：匹配滤波；
- `rx_costas_loop.v`：载波同步和 256 点 NCO；
- `rx_farrow_interpolator.v`：独立三阶 Farrow 插值器；
- `rx_gardner_timing.v`：定时 NCO、Gardner TED 和 PI；
- `rx_qpsk_diff_decode.v`：差分判决；
- `gowinsdr_rx_chain.v`：完整接收链封装；
- `matlab_ref/run_rx_chain_reference.m`：发射、信道和 bit-exact 接收模型；
- `scenario_results/VALIDATION_SUMMARY.md`：十一场景结果；
- `scenario_results/PHYSICAL_CHANNEL_RESULTS.md`：物理信道参数；
- `sim/open_xsim_gui.ps1`：打开最终 xsim 波形；
- `synth_physical_channel.log`：最终独立综合报告。
