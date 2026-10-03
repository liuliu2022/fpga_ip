# RFSoC differential-QPSK transmit chain

## Data path

`2-bit payload -> differential encoder -> QPSK signs -> 48-phase RRC -> four IQ samples/clock -> RFDC DAC AXI stream`

The differential rule and quadrant mapping are the same as GoWinSDR v1:

- `encoded_i[n] = encoded_i[n-1] XOR data[0]`
- `encoded_q[n] = encoded_q[n-1] XOR data[1]`
- encoded zero maps to a negative axis and encoded one maps to a positive axis

The RFSoC interface requires four consecutive complex samples each 61.44-MHz
PL clock. The effective baseband rate is therefore 245.76 MSPS. At 5.12
Msymbol/s this is 48 samples/symbol, or twelve PL clocks/symbol.

## Pulse-shaping filter

The transmit RRC uses the same design point as the validated receive model:

- roll-off `beta = 0.35`
- ten-symbol span
- 48 samples/symbol
- 481 symmetric taps
- coefficient scale `2^16`
- center coefficient 10365 DAC codes
- maximum polyphase absolute sum 14944, within signed 16-bit range

Because QPSK mapper outputs are only `+1/-1`, the RTL uses coefficient
add/subtract instead of general multipliers. `design_tx_rrc.m` is the single
source of truth for the text coefficients and synthesizable Verilog case ROM.

## Source and future payload connection

The board top currently connects `tx_prbs_qpsk_source` for deterministic
standalone testing. To send host data, replace only this source with an AXI or
FIFO adapter and connect its `data[1:0]`, `valid`, and `ready` signals to
`gowinsdr_tx_chain`; no modulator or filter change is required.

If payload valid is absent at a symbol boundary, the differential state is
held. This is equivalent to transmitting data `00` and prevents DAC waveform
discontinuities.

## Verification

MATLAB R2020b generates the coefficients and golden vectors. Vivado xsim then
performs two checks:

1. TX fixed-point comparison: 256 symbols and 12,288 complex samples match
   MATLAB exactly.
2. Complete RTL loopback: TX -> decimator -> RX RRC -> Costas -> Gardner ->
   differential decoder. The checked payload has zero errors at a nine-symbol
   pipeline delay.

Run `sim/run_tx_validation.ps1` to repeat both tests. Run
`synth_tx_chain.tcl` in Vivado batch mode for out-of-context timing/resource
checks.

## Hardware notes

- The existing RFDC sampling, x20 interpolation, mixer, and 1.5-GHz NCO
  settings are untouched.
- All eight DAC AXI streams are broadcast from the same QPSK waveform, as in
  the original standalone DDS design.
- Before radiating, set attenuation or use a cabled loopback with suitable
  attenuation. Verify RFDC overflow and spectrum with ILA/instrumentation.
