# 2026-10-15 antenna-distance captures

These immutable Vivado ILA CSV exports were captured while changing the
distance between the transmit and receive antennas. They are retained to tune
and regress the low-amplitude carrier-presence detector.

The trusted inputs for this analysis are the signed Costas I/Q magnitude and
the receiver loop diagnostics. The captured `costas_locked` flag is not a
golden result: it remained asserted even for the weakest, noise-dominated
capture. The 1024-sample files are too short and begin at arbitrary packet
positions, so they must not be repeated and presented as a packet BER test.

Run `matlab/analyze_low_amplitude_gate.m` to reproduce the signal-presence
classification used before changing the RTL.
