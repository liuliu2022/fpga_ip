# RFSoC board ILA captures

These files preserve real RFSoC board captures for regression testing of the
QPSK receiver.  The transmitter repeatedly sent the dibit sequence
`00 01 10 11`.

## Contents

- `raw/rx.csv`: original Vivado ILA export captured on 2026-10-14.
- `raw/iladata.csv`: original Vivado ILA export captured later on 2026-10-14;
  this capture records the reported post-noise loss-of-lock state.
- `stimulus/rx_decim_iq_s16.txt`: signed decimal `I Q` samples extracted from
  `gowinsdr_rx_chain_0_decim_i/q` in `rx.csv`.
- `stimulus/iladata_decim_iq_s16.txt`: the equivalent extracted samples from
  `iladata.csv`.
- `SHA256SUMS`: hashes of the immutable original CSV files.

Each stimulus contains 1024 complex samples at 61.44 MSPS.  With the current
5.12-Msymbol/s waveform this is 12 samples/symbol and 48 samples per repeated
four-symbol cycle.

## Trust boundary

The `decim_i/q` columns are preserved as trusted, real-board input stimuli for
testing `rx_matched_rrc` and all downstream modules.  MATLAB comparison with
the current differential encoder, TX RRC, and RX decimator found:

| Capture | 48-sample coherence | Ideal-waveform EVM | IQ polarity | Clipping |
| --- | ---: | ---: | --- | ---: |
| `rx.csv` | 0.999998976 | 2.4031% | normal | 0 |
| `iladata.csv` | 0.999996892 | 1.9751% | normal | 0 |

The captured Costas, Gardner, and decoded columns are diagnostic observations,
not golden expected outputs.  In particular, `iladata.csv` contains a Costas
frequency word corresponding to approximately -11.6 MHz and a Gardner
half-symbol interval of approximately 24 samples; both indicate loop-state
windup.  A future corrected receiver should be judged against the known
transmitted dibit cycle and lock/range assertions, not by reproducing those
faulty downstream values.

Run `matlab/import_ila_capture_vectors.m` to regenerate the two compact
stimulus files from the original CSV exports.
