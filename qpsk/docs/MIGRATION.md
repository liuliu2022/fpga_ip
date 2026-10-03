# GoWinSDR to T510 migration

## Imported reference

The GoWinSDR `v1` branch is stored as a sparse Git checkout at:

`third_party/GoWinSDR-v1`

Initial pinned commit: `0e6ab03`.

Only the top-level RTL files, constraints, AD936x firmware sources and Python
host sources are checked out.  Gowin-generated IP netlists are intentionally
excluded because they cannot be reused in Vivado.

## First integration module

`rfdc_rx_interface.v` adapts RFDC channel 0 to the migration data path:

- `m00_axis` -> `s_axis_i`
- `m01_axis` -> `s_axis_q`
- `m_axis_i` -> the original aggregator I input
- `m_axis_q` -> the original aggregator Q input
- `sample_i0..3`, `sample_q0..3`, `sample_valid` -> future decimation filter

The module does not modify RFDC configuration, filter data, or change sample
rate.  It preserves the raw capture path and keeps I/Q AXI transfers aligned.

The adapter is inserted in `T510_design.bd` between RFDC channel 0 and the
existing `iq_array_aggregator_0` capture path.  Its clock is
`clk_wiz_0/clk_out1`; its active-low reset is driven by `clk_wiz_0/locked`,
matching the existing aggregator clock domain.  No RFDC IP settings or legacy
IP versions were changed.

Run `add_gowinsdr_port_sources.tcl` from Vivado to register the RTL and both
testbenches in a fresh copy of the project.

## Simulation status

ModelSim SE-64 10.6d passes both focused RTL simulations:

- `tb_rfdc_rx_interface`: AXI I/Q pairing, backpressure, four-lane signed
  unpacking, and sticky valid-mismatch detection.
- `tb_rfdc_rx_bd_path`: RFDC-shaped I/Q traffic through the adapter into
  `iq_array_aggregator`, including the channel-0 1024-bit packing positions.

Vivado 2022.2 also reopens and validates the saved BD with
`rfdc_rx_interface_0`.  Full vendor-IP simulation is intentionally not
regenerated because the original Vivado 2019.1 IP instances are locked in
2022.2 and the RFDC configuration must remain unchanged.

## Complete receive chain

`gowinsdr_rx_chain_0` is now connected to all four complex sample lanes from
`rfdc_rx_interface_0`.  The chain contains the independent four-phase
decimator, receive RRC filter, portable Costas loop, Gardner timing detector,
and QPSK differential decoder.  See `rx_chain/RX_CHAIN.md` for rate, filter,
simulation, synthesis, and bring-up details.

## Complete transmit chain

The original top-level DDS stimulus has been replaced by a portable
differential-QPSK transmitter in `tx_chain/`: a deterministic PRBS source,
GoWinSDR-compatible differential encoder, QPSK mapper, and a 481-tap RRC
interpolator that emits four consecutive IQ samples per PL clock.

The RFDC remains at 4.9152 GSPS with x20 interpolation and its existing NCO.
The 61.44-MHz transmitter interface supplies an effective 245.76-MSPS complex
stream in the original `{Q3,I3,...,Q0,I0}` order. MATLAB/RTL sample comparison
and full RTL TX-to-RX loopback both pass; see `tx_chain/TX_CHAIN.md`.
