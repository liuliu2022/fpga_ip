# RFSoC 差分 QPSK 收发机

本目录是从 GoWinSDR v1 的成熟 QPSK 结构出发、面向 RFSoC 四复样本/时钟接口实现的可综合 Verilog 收发机。

## 数据通路

发射：

`2-bit 数据 -> 差分编码 -> QPSK 映射 -> 48 相 RRC -> 每拍 4 个 IQ -> RFDC DAC`

接收：

`RFDC 每拍 4 个 IQ -> 四相抽取 -> RX RRC -> Costas -> Farrow -> Gardner -> 差分解码`

完整数据包链路：

`PS DDR -> AXI DMA MM2S -> 成帧/扰码/CRC -> QPSK TX -> RFDC -> QPSK RX -> 解扰/CRC/解帧 -> AXI DMA S2MM -> PS DDR`

默认参数：

- RFDC ADC/DAC：4.9152 GSPS
- RFDC 插值/抽取：20
- PL 时钟：61.44 MHz
- PL 并行度：4 complex samples/clock
- 有效基带采样率：245.76 MSPS
- 符号率：5.12 Msymbol/s
- TX：48 samples/symbol
- RX 抽取后：12 samples/symbol
- RRC：`beta=0.35`，10-symbol span

RFDC 的采样率、插值/抽取和 NCO 设置不需要修改。

## 目录

- `rtl/tx`：差分编码、PRBS 测试源、四路并行 RRC 和 TX wrapper
- `rtl/rx`：多相抽取、匹配滤波、Costas、Farrow、Gardner 和解码器
- `rtl/interface`：RFDC RX AXI-Stream 适配器
- `rtl/packet`：AXI Stream 成帧器、解帧器、扰码、CRC8/CRC32
- `matlab`：滤波器设计、定点参考模型和物理信道场景
- `sim`：TX 位精确测试与完整 TX→RX 回环测试
- `scripts`：xsim 自动验证及 TX OOC 综合
- `examples`：T510 顶层接入示例
- `docs`：移植说明、数据流程和中文总结报告

## 已完成验证

- MATLAB 与 TX RTL：256 symbols、12,288 complex samples 逐样本完全一致。
- RTL TX→RTL RX：最佳流水线延迟 9 symbols，比较区间 0 error。
- TX OOC 综合：Vivado 2022.2，xczu47dr-ffve1156-2-i，61.44 MHz 下 WNS `+8.163 ns`。
- TX 资源：约 5.4k LUT、197 FF、0 DSP、0 BRAM。
- RX 的 MATLAB/RTL 分级验证和现实信道结果见 `docs/`。
- DMA payload → 帧层 → 完整 QPSK TX/RX → 解帧 → DMA payload 回环逐字节一致。
- 完整 T510 工程已完成综合、布局布线和 bitstream：0 error、0 critical warning。
- Routed timing：WNS `+0.081 ns`，WHS `+0.012 ns`，TNS/THS 均为 0。

## 运行验证

PowerShell：

```powershell
cd qpsk/sim
../scripts/run_tx_validation.ps1 `
  -MatlabExe 'C:\MATLAB\R2020b\bin\matlab.exe' `
  -VivadoBin 'C:\Xilinx\Vivado\2022.2\bin'
```

脚本会重新生成 TX 系数和黄金向量，随后运行 TX 位精确仿真以及 TX→RX 回环。

Vivado 2022.2 的 OOC 综合在部分 Windows 中文路径下可能以
`TclStackFree: incorrect freePtr` 异常退出；综合/实现时请把仓库放在纯
ASCII 路径中。相同代码在 ASCII 路径下已完成综合与时序验证。

## 上板接口

`gowinsdr_tx_chain` 使用 2-bit `data/valid/ready` 输入和 128-bit RFDC AXI-Stream 输出。当前 T510 示例已经改为全双工 AXI DMA 数据路径，原始 ADC IQ 采集 DMA 仍然独立保留。

数据包格式、DMA 地址、中断映射和 PS 软件调用顺序见
[`docs/PACKET_LINK.md`](docs/PACKET_LINK.md)。默认最大 payload 为 512 字节。

在已有 T510 工程中插入模块化 BD 链路：

```powershell
vivado.bat -mode batch `
  -source qpsk/scripts/integrate_packet_dma_bd.tcl `
  -tclargs F:/antsdr_t510_standalone1_ori
```

脚本参数是 T510 工程根目录；仓库脚本不绑定本机绝对路径。

注意：上板发射前请使用合适的衰减、屏蔽或有线环回，并遵守当地射频法规。

## 来源说明

差分编码、QPSK 象限约定及载波/定时同步结构参考 [ConstStrings/GoWinSDR v1](https://github.com/ConstStrings/GoWinSDR/tree/v1)。RFSoC 并行化、定点化、Farrow 定时恢复和验证框架为本移植实现。
