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
- The repaired deterministic baseline contains 6912 four-sample RFDC clocks and 543
  decoded symbols. Both the floating reference and current fixed receiver
  produce zero BER after automatic latency alignment.
- Vivado xsim compares decimator, RRC, Costas samples and loop state, Gardner
  samples and loop state, and decoded data. All 6912 sample outputs and all 543
  decoded symbols match the MATLAB fixed-point model exactly.
- `run_matlab_xsim.ps1` regenerates all vectors with MATLAB R2020b and runs the
  complete xsim regression in one command.
- `matlab_ref/generate_channel_scenarios.m` and
  `run_channel_validation.ps1` preserve the eleven earlier channel profiles.
  Regenerate those vectors after synchronization-loop changes; the current
  repair sign-off consists of the bit-exact baseline, two real ILA captures,
  recovery/noise MATLAB cases, and the RTL TX/RX loopback listed below.
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
- At 61.44 MHz, post-synthesis WNS is +5.231 ns and TNS is 0, with no failing
  endpoints. This is synthesized-netlist internal-clock timing; final BD
  implementation still remains the board-level sign-off.
- Standalone receive-chain use is 4205 LUTs, 455 of 4272 DSP48E2 blocks, and
  one block-RAM tile. The Costas NCO uses 256 phase points; its 25-kHz test
  estimate is 25.098 kHz.
- A fresh Vivado session reopens and validates all nine BD connections from
  `rfdc_rx_interface_0` to `gowinsdr_rx_chain_0`.

## Bring-up notes

Real 2026-10-14 board captures are preserved under
`testdata/ila_board_captures`.  Their signed 61.44-MSPS `decim_i/q` columns are
loader-ready stimuli for `rx_matched_rrc` and downstream regression tests.
The original CSV files are retained with SHA-256 hashes.  Do not use the
captured Costas, Gardner, or decoded columns as golden results: they record the
pre-fix loss-of-lock state.  See the capture README for the measured waveform
coherence, EVM, and trust boundary.

The repaired Costas detector is power-of-two normalized from `|I|+|Q|`, so it
does not require the old nominal magnitude of 8192.  Its frequency integrator
is limited to +/-250 kHz, a hysteretic error metric requires 256 good samples
to assert lock and 128 consecutive bad samples to reset, and the lock state is
exported as `costas_locked`.  `costas_recovery` pulses on an automatic reset.
Gardner is held reset until carrier lock, uses a power-of-two normalized
early/middle/late error, and bounds its half-symbol period to 5.70--6.30 input
samples.  This prevents carrier noise from corrupting the timing-loop state.

Packet synchronization now feeds `axis_rx_deframer.sync_found` back to the
receiver as `frame_sync`. Before this pulse Gardner uses the original wide
acquisition bandwidth and 5.70--6.30-sample bounds. At the pulse its rate word
is returned to the nominal six samples per half symbol without resetting the
interpolation phase. For the following 32768 input samples the proportional
gain is divided by eight, the integral gain by sixteen, and the rate is bounded
to +/-1 percent. This prevents a correctly acquired, clock-coherent packet from
developing the observed one-dibit header slip while retaining a bounded clock-
offset tracking capability.

`sim/tb_real_ila_rx_repair.v` repeats the coherent 1008-sample portion of each
real capture 32 times and checks the final 256 differential dibits.  Both
`rx.csv` and `iladata.csv` pass with zero errors.  The fixed MATLAB recovery
tests also finish with zero errors in the final 256-symbol window after an
initial -11.6 MHz state (clamped to the allowed acquisition range) and after a
strong injected noise burst.  The RTL TX/RX PRBS loopback passes with zero
errors in the stable payload region after the acquisition/preamble interval.

The first co-simulation profile is deliberately free of channel impairments.
Enable and validate initial phase, carrier offset, fractional timing offset,
AWGN, and gain variation one at a time. Exact sample agreement is judged
against the fixed-point model; BER/EVM and lock behavior are judged against
the floating-point model.

The Costas PI gains follow the upstream GoWinSDR MATLAB equations with
`zeta=0.707` and `BnTs=0.01`. The decision-directed detector uses a leading-bit
power-of-two normalizer rather than a divider, allowing the two measured board
amplitude ranges and the synthetic transmitter amplitude to share one loop.
An RF AGC is still useful to avoid ADC clipping and preserve SNR, but it is no
longer required merely to hit one exact Costas scale. Timing synchronization uses the standalone
`rx_farrow_interpolator.v`, a Gardner TED, and the GoWin incremental loop-filter
form `w[n+1]=w[n]+Kp(e[n]-e[n-1])+Ki*e[n]`. The +/-500 ppm tests establish the
current simulated tracking range; wider ppm/SNR sweeps can be added after
hardware amplitude and oscillator limits are known.

The current random-vector testbench reports both raw BER and BER after QPSK
quadrant resolution. The physical profiles lock 90 degrees away and therefore
require an I/Q bit-channel swap. Hardware deployment needs a known preamble or
sync word to select this automatically. The packet layer now supplies that rule:
the deframer recognizes the normal and bit-exchanged sync words and exports
`iq_swapped`.

Decoded data and loop diagnostics are exposed as module outputs but are not
routed into the existing DMA, because that DMA remains dedicated to raw
multi-channel capture.  They can next be connected to an ILA or a separate
AXI-Stream packet/DMA path without modifying RFDC configuration.
