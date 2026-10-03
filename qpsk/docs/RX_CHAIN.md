# RFSoC GoWinSDR receive chain

> Status: experimental RFSoC implementation under MATLAB/RTL verification.
> The architecture was motivated by GoWinSDR v1, but the present FIR, Costas,
> and Gardner numeric parameters are not claimed to be an unchanged port of
> GoWinSDR. The upstream RX RRC is bypassed and its Gardner output is not used
> by the final decoder, so those missing specifications must be resolved by
> measurement and an executable reference model rather than assumption.

## Signal path

`RFDC (245.76 MSPS, four samples/clock)` -> `rx_polyphase_decim4` ->
`rx_matched_rrc` -> `rx_costas_loop` -> `rx_farrow_interpolator` +
`rx_gardner_timing` ->
`rx_qpsk_diff_decode`.

The complete path is wrapped by `gowinsdr_rx_chain.v` and instantiated in
`T510_design.bd` as `gowinsdr_rx_chain_0`.  It is a parallel observation path;
the original RFDC-to-aggregator/DMA path is unchanged.

## Rates and filters

- RFDC sampling rate: 4.9152 GSPS with the existing RFDC x20 decimation.
- PL complex sample rate: 245.76 MSPS, four signed 16-bit samples per 61.44 MHz clock.
- Polyphase decimation: x4, producing one 61.44 MSPS complex sample per clock.
- Anti-alias FIR: 44 taps, Q1.17, 8 MHz passband, 30.72 MHz stopband.
- Quantized response: 0.046452 dB passband ripple and 82.537 dB stopband attenuation.
- RRC: 121 taps, Q1.17, beta 0.35, 12 samples/symbol, 5.12 Msymbol/s.

`design_rx_filters.m` regenerates and checks both coefficient sets with MATLAB
R2020b.  The coefficient sums are exactly 131072, so both filters have unity
DC gain after the Q1.17 shift.

## Verification completed

- MATLAB and RTL agree exactly for 160 random complex decimator vectors.
- `matlab_ref/run_rx_chain_reference.m` now generates a complete differential-
  QPSK transmitter, channel, 16-bit RFDC quantizer, four-sample packing, a
  floating open-loop reference, and a bit-accurate model of every RTL stage.
- The deterministic baseline contains 6912 four-sample RFDC clocks and 575
  decoded symbols. Both the floating reference and current fixed receiver
  produce zero BER after automatic latency alignment.
- Vivado xsim compares decimator, RRC, Costas samples and loop state, Gardner
  samples and loop state, and decoded data. All 6912 sample outputs and all 575
  decoded symbols match the MATLAB fixed-point model exactly.
- `run_matlab_xsim.ps1` regenerates all vectors with MATLAB R2020b and runs the
  complete xsim regression in one command.
- `matlab_ref/generate_channel_scenarios.m` and
  `run_channel_validation.ps1` preserve and verify eleven channel profiles.
  All profiles are bit-exact between MATLAB fixed point and RTL. The corrected
  Costas loop produces zero BER for both the 25-kHz-CFO profile and the
  combined CFO/phase/timing/clock/AWGN/gain profile. See
  `scenario_results/VALIDATION_SUMMARY.md`.
- The timing path is adapted from GoWinSDR v1's separate Farrow/TED/NCO
  architecture. The cubic interpolation polynomial is preserved; the nominal
  NCO word and incremental PI gains are recalculated for 12 samples/symbol.
  Long 2048-symbol tests at both +500 ppm and -500 ppm produce zero BER and
  match RTL exactly at every checked symbol and loop-state output.
- Two deterministic physical-channel profiles additionally inject multipath,
  sampling jitter, Wiener phase noise, I/Q gain and quadrature imbalance, DC
  offset, slow fading, a CW interferer, AWGN, ADC clipping, CFO, and clock ppm.
  Both recover with zero BER after resolving the normal QPSK quadrant ambiguity.
- Standalone Vivado synthesis for `xczu47dr-ffve1156-2-i` completes with no
  errors or critical warnings.
- At 61.44 MHz, post-synthesis WNS is +7.870 ns and TNS is 0, with no failing
  endpoints. This is synthesized-netlist internal-clock timing; final BD
  implementation still remains the board-level sign-off.
- Standalone receive-chain use is 3449 LUTs, 458 of 4272 DSP48E2 blocks, and
  one block-RAM tile. The Costas NCO uses 256 phase points; its 25-kHz test
  estimate is 25.098 kHz.
- A fresh Vivado session reopens and validates all nine BD connections from
  `rfdc_rx_interface_0` to `gowinsdr_rx_chain_0`.

## Bring-up notes

The first co-simulation profile is deliberately free of channel impairments.
Enable and validate initial phase, carrier offset, fractional timing offset,
AWGN, and gain variation one at a time. Exact sample agreement is judged
against the fixed-point model; BER/EVM and lock behavior are judged against
the floating-point model.

The Costas PI gains follow the upstream GoWinSDR MATLAB equations with
`zeta=0.707` and `BnTs=0.01`. The decision-directed detector uses a fixed
8192 nominal magnitude, implemented as a saturating left shift rather than a
variable divider; this change moved standalone WNS from -16.071 ns to
+10.001 ns. Hardware amplitude outside the validated range should be covered
by AGC or by retuning this scale. Timing synchronization now uses the standalone
`rx_farrow_interpolator.v`, a Gardner TED, and the GoWin incremental loop-filter
form `w[n+1]=w[n]+Kp(e[n]-e[n-1])+Ki*e[n]`. The +/-500 ppm tests establish the
current simulated tracking range; wider ppm/SNR sweeps can be added after
hardware amplitude and oscillator limits are known.

The current random-vector testbench reports both raw BER and BER after QPSK
quadrant resolution. The physical profiles lock 90 degrees away and therefore
require an I/Q bit-channel swap. Hardware deployment needs a known preamble or
sync word to select this automatically; that framing rule is not defined yet.

Decoded data and loop diagnostics are exposed as module outputs but are not
routed into the existing DMA, because that DMA remains dedicated to raw
multi-channel capture.  They can next be connected to an ILA or a separate
AXI-Stream packet/DMA path without modifying RFDC configuration.
