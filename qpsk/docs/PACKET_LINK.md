# RFSoC QPSK packet/DMA link

The packet link preserves the validated differential-QPSK PHY and the existing
RFDC configuration. It adds a store-and-forward packet layer between a new
full-duplex AXI DMA and the two-bit QPSK symbol interface.

## On-air frame

`55 x 32 | EB 90 CA D3 | 10 | length_be16 | CRC8 | scrambled payload | scrambled CRC32_le`

- Header CRC: CRC-8 polynomial `0x07`, initial value zero.
- Payload FCS: reflected IEEE CRC-32 polynomial `0xEDB88320`, initial and final
  XOR values all ones.
- Scrambler: seven-bit sequence generator `x^7 + x^4 + 1`, initial state
  `0x5D`. Only payload and FCS are scrambled.
- Maximum payload in the first hardware build: 512 bytes. This deliberately
  bounds the first implementation's store-and-forward register footprint;
  larger frames should use a dual-port-BRAM or segmented FIFO revision.

The TX framer buffers one MM2S packet until `TLAST`, so it can put the verified
payload length into the header. The RX deframer buffers one received frame and
only releases it to S2MM after CRC32 passes. The PS therefore programs one MM2S
transfer and one S2MM transfer of the same expected payload size.

## Intended BD structure

`DDR -> axi_dma_qpsk/MM2S -> axis_clock_converter -> axis_tx_framer -> gowinsdr_tx_chain -> axis_broadcaster -> RFDC DAC`

`RFDC ADC -> rfdc_rx_interface -> gowinsdr_rx_chain -> axis_rx_deframer -> axis_clock_converter -> axi_dma_qpsk/S2MM -> DDR`

The original ADC-IQ capture DMA remains present and independent.

## PS software contract

- `axi_dma_qpsk` AXI-Lite base address: `0x80060000`.
- DMA mode: simple mode (no scatter/gather), 32-bit AXI Stream, 128-bit DDR
  memory-mapped ports, 32-bit buffer addresses.
- Place TX and RX buffers in the low DDR address range below 2 GiB. The DMA
  address width intentionally does not map DDR_HIGH or OCM.
- For a loopback test of `N` bytes (`1 <= N <= 512`): prepare the RX buffer,
  start S2MM for exactly `N` bytes, then start MM2S for exactly `N` bytes.
  Starting S2MM first avoids losing the beginning of a good received frame.
- Flush the TX buffer cache before MM2S. Invalidate the RX buffer cache after
  S2MM completion and before comparing the two buffers.
- One MM2S transfer is one radio frame. `TLAST` terminates the payload accepted
  by the TX framer; the RX deframer regenerates `TLAST` on the final verified
  payload byte/word.
- Frames with a bad header, illegal length, or bad CRC32 are discarded and are
  not written to DDR. Software should use a receive timeout as well as the DMA
  completion interrupt.

Interrupt order on the PS PL-to-PS vector:

- bit 0: original raw-IQ DMA S2MM interrupt;
- bit 1: QPSK DMA MM2S interrupt;
- bit 2: QPSK DMA S2MM interrupt.

`qpsk_tx_active` is exported from the BD and currently drives
`dac_status_led`; it indicates that the packet transmitter is actively emitting
the framed waveform.

## Verification status

- AXI packet-only simulation: payload, scrambling, descrambling, header CRC and
  CRC32 agree end to end.
- Full PHY simulation: DMA payload -> frame -> QPSK TX/RX -> deframe -> DMA
  payload passes byte-for-byte.
- Vivado 2022.2 synthesis and implementation for `xczu47dr-ffve1156-2-i`:
  complete with zero errors and zero critical warnings. Routed utilization is
  32,180 LUTs, 30,510 registers, 128.5 BRAM tiles and 346 DSPs for the complete
  project.
- Routed timing passes all specified constraints: WNS `+0.081 ns`, TNS `0`,
  WHS `+0.012 ns`, THS `0`. The CDC bus-skew constraints also pass.
- Bitstream generation completes successfully. The generated file is
  `antsdr_t510_standalone.runs/impl_1/t510_standalone_top.bit`.
