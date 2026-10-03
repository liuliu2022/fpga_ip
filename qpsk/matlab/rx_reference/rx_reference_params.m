function p = rx_reference_params(profile)
%RX_REFERENCE_PARAMS Single source of truth for MATLAB/RTL verification.
% Values marked RFSoC come from the existing RFDC/PL interface. Values marked
% experimental describe the current RTL and must not be presented as original
% GoWinSDR v1 parameters.

if nargin < 1, profile = 'baseline'; end
p.profile = char(profile);
p.seed = 20260930;
p.num_payload_symbols = 512;
p.guard_symbols = 32;

p.fs_rfdc = 245.76e6;            % RFSoC: four samples per PL clock
p.samples_per_clock = 4;         % RFSoC
p.fs_pl = 61.44e6;               % RFSoC PL clock / post-decimator rate

p.symbol_rate = 5.12e6;          % experimental current RTL
p.sps_pl = 12;                   % fs_pl / symbol_rate
p.sps_rfdc = 48;                 % fs_rfdc / symbol_rate
p.rrc_beta = 0.35;               % experimental current RTL
p.rrc_span_symbols = 10;         % experimental current RTL

% Baseline is intentionally impairment-free. Add one impairment at a time only
% after exact RTL agreement is established.
p.channel.gain = 0.70;
p.channel.cfo_hz = 0;
p.channel.phase_rad = 0;
p.channel.snr_db = Inf;
p.channel.fractional_delay_rfdc_samples = 0;
p.channel.sample_clock_ppm = 0;
p.channel.sample_jitter_rms_rfdc_samples = 0;
p.channel.multipath_taps = 1;
p.channel.phase_noise_linewidth_hz = 0;
p.channel.iq_gain_imbalance_db = 0;
p.channel.iq_phase_error_deg = 0;
p.channel.dc_i_codes = 0;
p.channel.dc_q_codes = 0;
p.channel.fade_depth = 0;
p.channel.fade_hz = 0;
p.channel.cw_relative_rms = 0;
p.channel.cw_offset_hz = 0;
p.channel.adc_clip_codes = 32767;
p.adc_peak = 12000;

switch lower(p.profile)
    case 'baseline'
        % No impairment: establishes deterministic bit-exact equivalence.
    case 'phase_only'
        p.channel.phase_rad = 0.70;
    case 'cfo_only'
        p.channel.phase_rad = 0.25;
        p.channel.cfo_hz = 25e3;
    case 'timing_offset'
        % 1.40 RFDC samples = 0.35 sample at the 61.44-MSPS loop input.
        p.channel.fractional_delay_rfdc_samples = 1.40;
    case 'clock_offset'
        p.channel.fractional_delay_rfdc_samples = 0.80;
        p.channel.sample_clock_ppm = 100;
    case 'awgn_20db'
        p.channel.snr_db = 20;
    case 'combined'
        p.channel.phase_rad = 0.45;
        p.channel.cfo_hz = 25e3;
        p.channel.fractional_delay_rfdc_samples = 1.40;
        p.channel.sample_clock_ppm = 100;
        p.channel.snr_db = 20;
        p.channel.gain = 0.60;
    case 'timing_ppm_plus500'
        p.num_payload_symbols = 2048;
        p.channel.fractional_delay_rfdc_samples = 1.40;
        p.channel.sample_clock_ppm = 500;
    case 'timing_ppm_minus500'
        p.num_payload_symbols = 2048;
        p.channel.fractional_delay_rfdc_samples = 2.60;
        p.channel.sample_clock_ppm = -500;
    case 'physical_lab'
        % Representative bench impairments: modest multipath and RF/clock
        % errors, finite ADC headroom, a weak in-band CW interferer, and AWGN.
        p.num_payload_symbols = 2048;
        p.channel.gain = 0.65;
        p.channel.cfo_hz = 18e3;
        p.channel.phase_rad = 0.55;
        p.channel.snr_db = 18;
        p.channel.fractional_delay_rfdc_samples = 1.90;
        p.channel.sample_clock_ppm = 35;
        p.channel.sample_jitter_rms_rfdc_samples = 0.02;
        p.channel.phase_noise_linewidth_hz = 20;
        p.channel.iq_gain_imbalance_db = 0.7;
        p.channel.iq_phase_error_deg = 2.0;
        p.channel.dc_i_codes = 120;
        p.channel.dc_q_codes = -90;
        p.channel.fade_depth = 0.04;
        p.channel.fade_hz = 2e3;
        p.channel.cw_relative_rms = 0.04;
        p.channel.cw_offset_hz = 2.0e6;
        p.channel.adc_clip_codes = 9500;
        h=zeros(17,1); h(1)=1;
        h(6)=0.12*exp(1j*0.60); h(17)=0.06*exp(-1j*0.90);
        p.channel.multipath_taps = h;
    case 'physical_stress'
        % Deliberately severe non-idealities used to expose the boundary of
        % a carrier/timing receiver that has no adaptive equalizer yet.
        p.num_payload_symbols = 2048;
        p.channel.gain = 0.65;
        p.channel.cfo_hz = 40e3;
        p.channel.phase_rad = 1.0;
        p.channel.snr_db = 12;
        p.channel.fractional_delay_rfdc_samples = 2.70;
        p.channel.sample_clock_ppm = 200;
        p.channel.sample_jitter_rms_rfdc_samples = 0.05;
        p.channel.phase_noise_linewidth_hz = 80;
        p.channel.iq_gain_imbalance_db = 1.5;
        p.channel.iq_phase_error_deg = 5.0;
        p.channel.dc_i_codes = 300;
        p.channel.dc_q_codes = -240;
        p.channel.fade_depth = 0.12;
        p.channel.fade_hz = 5e3;
        p.channel.cw_relative_rms = 0.12;
        p.channel.cw_offset_hz = 1.5e6;
        p.channel.adc_clip_codes = 8000;
        h=zeros(23,1); h(1)=1;
        h(9)=0.28*exp(1j*0.85); h(23)=0.12*exp(-1j*1.10);
        p.channel.multipath_taps = h;
    otherwise
        error('Unknown validation profile: %s', p.profile);
end

matlabDir = fileparts(fileparts(mfilename('fullpath')));
repoRoot = fileparts(matlabDir);
p.decim_coeff_file = fullfile(repoRoot,'rtl','rx','rx_decim4_coeffs_q17.txt');
p.rrc_coeff_file = fullfile(repoRoot,'rtl','rx','rx_rrc_coeffs_q17.txt');
p.coeff_fraction_bits = 17;

p.costas.phase_bits = 32;
p.costas.lut_bits = 8;
% GoWinSDR Matlab/costas.m: zeta=0.707 and BnTs=0.01. These are the
% corresponding coefficients in a 32-bit phase domain for Q1.15 error.
p.costas.zeta = 0.707;
p.costas.bnTs = 0.01;
p.costas.kp_phase_word = int32(19059814);
p.costas.ki_phase_word = int32(269587);
p.costas.error_fraction_bits = 15;
p.costas.nominal_magnitude_bits = 13; % |I|+|Q| ~= 8192; RTL implements <<2

p.gardner.nominal_half_step = uint32(715827883); % 2^32/6
p.gardner.half_symbol_samples = uint32(p.sps_pl/2);
% GoWinSDR loop-filter form: w[n+1]=w[n]+Kp*(e[n]-e[n-1])+Ki*e[n].
% Gains use the same zeta/BnTs design point as the carrier loop, converted
% into half-symbol NCO phase-word units. Detector error is signed Q1.15.
p.gardner.error_shift = 11;       % raw amplitude^2 error -> Q1.15
p.gardner.kp_step_word = int32(19959391);
p.gardner.ki_step_word = int32(282311);
end
