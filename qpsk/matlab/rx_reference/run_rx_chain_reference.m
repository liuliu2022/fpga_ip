function report = run_rx_chain_reference(profile)
%RUN_RX_CHAIN_REFERENCE Generate RFDC stimulus and bit-accurate RTL references.
% The first run is deliberately impairment-free. Exact agreement at every
% stage is required before enabling CFO, timing offset, AWGN, or gain sweeps.

if nargin < 1, profile = 'baseline'; end
p = rx_reference_params(profile);
assert(p.fs_rfdc/p.samples_per_clock == p.fs_pl, 'RFDC/PL rate mismatch');
assert(p.fs_pl/p.symbol_rate == p.sps_pl, 'PL samples/symbol must be integer');
assert(p.fs_rfdc/p.symbol_rate == p.sps_rfdc, 'RFDC samples/symbol must be integer');

thisDir = fileparts(mfilename('fullpath'));
matlabDir = fileparts(thisDir);
repoRoot = fileparts(matlabDir);
vectorDir = fullfile(repoRoot, 'vectors');
if ~exist(vectorDir, 'dir'), mkdir(vectorDir); end
scenarioDir = fullfile(repoRoot, 'scenario_results', p.profile);
if ~exist(scenarioDir, 'dir'), mkdir(scenarioDir); end

rng(p.seed, 'twister');
nSymbols = p.num_payload_symbols + 2*p.guard_symbols;
txBits = randi([0 1], nSymbols, 2);
[txSymbols, txDecisions] = differential_qpsk_encode(txBits);

txRrc = rrc_impulse(p.rrc_beta, p.rrc_span_symbols, p.sps_rfdc);
upsampled = complex(zeros(nSymbols*p.sps_rfdc, 1));
upsampled(1:p.sps_rfdc:end) = txSymbols;
txWave = filter(txRrc, 1, upsampled);
peak = max([abs(real(txWave)); abs(imag(txWave)); eps]);
txWave = txWave * (p.adc_peak/peak);

n = (0:numel(txWave)-1).';
sampleJitter = p.channel.sample_jitter_rms_rfdc_samples*randn(size(n));
samplePosition = n*(1+p.channel.sample_clock_ppm*1e-6) - ...
    p.channel.fractional_delay_rfdc_samples + sampleJitter;
txWave = interp1(n,txWave,samplePosition,'pchip',0);
txWave = filter(p.channel.multipath_taps,1,txWave);
if p.channel.phase_noise_linewidth_hz > 0
    phaseIncrementRms=sqrt(2*pi*p.channel.phase_noise_linewidth_hz/p.fs_rfdc);
    phaseNoise=cumsum(phaseIncrementRms*randn(size(n)));
else
    phaseNoise=zeros(size(n));
end
rotation = exp(1j*(p.channel.phase_rad + 2*pi*p.channel.cfo_hz*n/p.fs_rfdc + phaseNoise));
fade = 1 + p.channel.fade_depth*sin(2*pi*p.channel.fade_hz*n/p.fs_rfdc);
channelWave = p.channel.gain * fade .* txWave .* rotation;

% Direct-conversion RF impairments: symmetric I/Q gain mismatch, quadrature
% skew, and converter-referred DC offsets.
iqGain=10^(p.channel.iq_gain_imbalance_db/40);
phaseSkew=deg2rad(p.channel.iq_phase_error_deg);
idealI=real(channelWave); idealQ=imag(channelWave);
impairedI=iqGain*idealI;
impairedQ=(idealQ*cos(phaseSkew)+idealI*sin(phaseSkew))/iqGain;
channelWave=complex(impairedI+p.channel.dc_i_codes, ...
    impairedQ+p.channel.dc_q_codes);

if p.channel.cw_relative_rms > 0
    signalRms=sqrt(mean(abs(channelWave).^2));
    channelWave=channelWave + p.channel.cw_relative_rms*signalRms* ...
        exp(1j*2*pi*p.channel.cw_offset_hz*n/p.fs_rfdc);
end
if isfinite(p.channel.snr_db)
    signalPower = mean(abs(channelWave).^2);
    noisePower = signalPower/10^(p.channel.snr_db/10);
    channelWave = channelWave + sqrt(noisePower/2) * ...
        (randn(size(channelWave)) + 1j*randn(size(channelWave)));
end

adcI = sat16(round(min(max(real(channelWave),-p.channel.adc_clip_codes), ...
    p.channel.adc_clip_codes)));
adcQ = sat16(round(min(max(imag(channelWave),-p.channel.adc_clip_codes), ...
    p.channel.adc_clip_codes)));
pad = mod(-numel(adcI), p.samples_per_clock);
adcI = [adcI; zeros(pad,1,'int16')]; %#ok<AGROW>
adcQ = [adcQ; zeros(pad,1,'int16')]; %#ok<AGROW>

hDecim = int64(load_integer_vector(p.decim_coeff_file));
hRrc = int64(load_integer_vector(p.rrc_coeff_file));
assert(numel(hDecim) == 44, 'RTL decimator expects 44 coefficients');
assert(numel(hRrc) == 121, 'RTL receive RRC expects 121 coefficients');

fixed = rtl_fixed_model(adcI, adcQ, hDecim, hRrc, p);
write_all_vectors(vectorDir, adcI, adcQ, fixed, txBits, txDecisions, p);
write_all_vectors(scenarioDir, adcI, adcQ, fixed, txBits, txDecisions, p);
plot_reference_overview(vectorDir, txSymbols, adcI, adcQ, fixed, p.profile);
plot_reference_overview(scenarioDir, txSymbols, adcI, adcQ, fixed, p.profile);

[fixedBer, fixedLag, fixedCompared] = best_pair_ber(txBits, fixed.decoded_bits, 160);
[swappedBer, swappedLag, swappedCompared] = ...
    best_pair_ber(txBits, fixed.decoded_bits(:,[2 1]), 160);
if swappedBer < fixedBer
    resolvedBer=swappedBer; resolvedLag=swappedLag;
    resolvedCompared=swappedCompared; ambiguityMode='swap_iq_bits';
else
    resolvedBer=fixedBer; resolvedLag=fixedLag;
    resolvedCompared=fixedCompared; ambiguityMode='direct';
end
[floatBer, floatPhase, floatLag] = floating_open_loop_reference(...
    adcI, adcQ, hDecim, hRrc, txBits, p, false);
[oracleBer, oraclePhase, oracleLag] = floating_open_loop_reference(...
    adcI, adcQ, hDecim, hRrc, txBits, p, true);

report = struct();
report.profile = p.profile;
report.vector_directory = vectorDir;
report.scenario_directory = scenarioDir;
report.input_clocks = numel(adcI)/4;
report.decimator_outputs = numel(fixed.decim_i);
report.costas_outputs = numel(fixed.costas_i);
report.symbol_outputs = numel(fixed.symbol_i);
report.decoded_outputs = size(fixed.decoded_bits,1);
report.fixed_receiver_ber = fixedBer;
report.fixed_receiver_lag_symbols = fixedLag;
report.fixed_receiver_compared_symbols = fixedCompared;
report.ambiguity_resolved_ber = resolvedBer;
report.ambiguity_resolved_lag_symbols = resolvedLag;
report.ambiguity_resolved_compared_symbols = resolvedCompared;
report.ambiguity_mode = ambiguityMode;
report.floating_open_loop_ber = floatBer;
report.floating_best_sample_phase = floatPhase;
report.floating_lag_symbols = floatLag;
report.floating_oracle_carrier_ber = oracleBer;
report.floating_oracle_best_sample_phase = oraclePhase;
report.floating_oracle_lag_symbols = oracleLag;
tail = max(1,numel(fixed.frequency_word)-255):numel(fixed.frequency_word);
report.mean_tail_frequency_word = mean(double(fixed.frequency_word(tail)));
report.estimated_correction_hz = report.mean_tail_frequency_word*p.fs_pl/2^32;

save(fullfile(scenarioDir,'report.mat'),'report','p');
write_report_text(fullfile(scenarioDir,'report.txt'),report,p);

fprintf('Profile: %s\n',p.profile);
fprintf('Vectors: %s\n', vectorDir);
fprintf('RFDC clocks: %d, decoded symbols: %d\n', ...
    report.input_clocks, report.decoded_outputs);
fprintf('Current fixed RTL model BER: %.6g (lag %d, %d symbols)\n', ...
    fixedBer, fixedLag, fixedCompared);
fprintf('After QPSK quadrant ambiguity resolution: %.6g (%s)\n', ...
    resolvedBer,ambiguityMode);
fprintf('Floating open-loop bound BER: %.6g (phase %d, lag %d)\n', ...
    floatBer, floatPhase, floatLag);
fprintf('Floating oracle-carrier BER: %.6g (phase %d, lag %d)\n', ...
    oracleBer, oraclePhase, oracleLag);
fprintf('Mean tail Costas correction estimate: %.3f Hz\n',report.estimated_correction_hz);
fprintf('Next: run sim/tb_gowinsdr_rx_chain.v and require zero stage mismatches.\n');
end

function plot_reference_overview(vectorDir,txSymbols,adcI,adcQ,r,profile)
f=figure('Visible','off','Color','w','Position',[80 80 1500 850]);
subplot(2,3,1); plot(real(txSymbols),imag(txSymbols),'.'); axis equal; grid on;
xlabel('I');ylabel('Q');title('TX differential-QPSK symbols');
subplot(2,3,2); count=min(400,numel(adcI));
plot(0:count-1,double(adcI(1:count)));hold on;plot(0:count-1,double(adcQ(1:count)));
grid on;xlabel('RFDC sample');ylabel('code');legend('I','Q');title('Quantized RFDC input');
subplot(2,3,3); count=min(300,numel(r.decim_i));
plot(0:count-1,double(r.decim_i(1:count)));hold on;plot(0:count-1,double(r.decim_q(1:count)));
grid on;xlabel('61.44-MSPS sample');ylabel('code');legend('I','Q');title('Polyphase decimator output');
subplot(2,3,4); plot(double(r.rrc_i),double(r.rrc_q),'.','MarkerSize',3);
axis equal;grid on;xlabel('I');ylabel('Q');title('RX RRC sample cloud');
subplot(2,3,5); plot(double(r.costas_i),double(r.costas_q),'.','MarkerSize',3);
axis equal;grid on;xlabel('I');ylabel('Q');title('Costas output sample cloud');
subplot(2,3,6); plot(double(r.symbol_i),double(r.symbol_q),'.');
axis equal;grid on;xlabel('I');ylabel('Q');title('Gardner symbol decisions');
sgtitle(sprintf('RFSoC QPSK MATLAB reference flow: %s',strrep(profile,'_',' ')));
saveas(f,fullfile(vectorDir,'reference_overview.png'));
savefig(f,fullfile(vectorDir,'reference_overview.fig'));
close(f);
end

function write_report_text(path,report,p)
fid=fopen(path,'w'); assert(fid>=0);
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'profile=%s\n',report.profile);
fprintf(fid,'fixed_receiver_ber=%.12g\n',report.fixed_receiver_ber);
fprintf(fid,'ambiguity_resolved_ber=%.12g\nambiguity_mode=%s\n', ...
    report.ambiguity_resolved_ber,report.ambiguity_mode);
fprintf(fid,'floating_open_loop_ber=%.12g\n',report.floating_open_loop_ber);
fprintf(fid,'floating_oracle_carrier_ber=%.12g\n',report.floating_oracle_carrier_ber);
fprintf(fid,'decoded_outputs=%d\n',report.decoded_outputs);
fprintf(fid,'fixed_lag_symbols=%d\n',report.fixed_receiver_lag_symbols);
fprintf(fid,'estimated_correction_hz=%.12g\n',report.estimated_correction_hz);
fprintf(fid,'cfo_hz=%.12g\nphase_rad=%.12g\nsnr_db=%.12g\n', ...
    p.channel.cfo_hz,p.channel.phase_rad,p.channel.snr_db);
fprintf(fid,'fractional_delay_rfdc_samples=%.12g\nsample_clock_ppm=%.12g\n', ...
    p.channel.fractional_delay_rfdc_samples,p.channel.sample_clock_ppm);
fprintf(fid,'sample_jitter_rms_rfdc_samples=%.12g\nphase_noise_linewidth_hz=%.12g\n', ...
    p.channel.sample_jitter_rms_rfdc_samples,p.channel.phase_noise_linewidth_hz);
fprintf(fid,'iq_gain_imbalance_db=%.12g\niq_phase_error_deg=%.12g\n', ...
    p.channel.iq_gain_imbalance_db,p.channel.iq_phase_error_deg);
fprintf(fid,'dc_i_codes=%.12g\ndc_q_codes=%.12g\nadc_clip_codes=%.12g\n', ...
    p.channel.dc_i_codes,p.channel.dc_q_codes,p.channel.adc_clip_codes);
fprintf(fid,'fade_depth=%.12g\nfade_hz=%.12g\ncw_relative_rms=%.12g\ncw_offset_hz=%.12g\n', ...
    p.channel.fade_depth,p.channel.fade_hz,p.channel.cw_relative_rms,p.channel.cw_offset_hz);
fprintf(fid,'multipath_tap_count=%d\n',numel(p.channel.multipath_taps));
end

function [symbols, decisions] = differential_qpsk_encode(bits)
decisions = false(size(bits));
previous = false(1,2);
for k = 1:size(bits,1)
    decisions(k,:) = xor(logical(bits(k,:)), previous);
    previous = decisions(k,:);
end
symbols = complex(2*double(decisions(:,1))-1, 2*double(decisions(:,2))-1);
symbols = symbols/sqrt(2);
end

function h = rrc_impulse(beta, span, sps)
t = (-span*sps/2:span*sps/2).'/sps;
h = zeros(size(t));
for k = 1:numel(t)
    x = t(k);
    if abs(x) < 1e-12
        h(k) = 1 + beta*(4/pi-1);
    elseif beta > 0 && abs(abs(x)-1/(4*beta)) < 1e-12
        h(k) = beta/sqrt(2) * ((1+2/pi)*sin(pi/(4*beta)) + ...
            (1-2/pi)*cos(pi/(4*beta)));
    else
        h(k) = (sin(pi*x*(1-beta)) + 4*beta*x*cos(pi*x*(1+beta))) / ...
            (pi*x*(1-(4*beta*x)^2));
    end
end
h = h/sqrt(sum(h.^2));
end

function v = load_integer_vector(path)
fid = fopen(path, 'r');
assert(fid >= 0, 'Cannot open coefficient file: %s', path);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
v = fscanf(fid, '%d');
end

function out = rtl_fixed_model(adcI, adcQ, hDecim, hRrc, p)
[out.decim_i, out.decim_q] = fixed_decimate4(adcI, adcQ, hDecim, p.coeff_fraction_bits);
[out.rrc_i, out.rrc_q] = fixed_fir(out.decim_i, out.decim_q, hRrc, p.coeff_fraction_bits);
[out.costas_i, out.costas_q, out.frequency_word, out.phase_word] = ...
    fixed_costas(out.rrc_i, out.rrc_q, p);
[out.symbol_i, out.symbol_q, out.timing_step, out.timing_error] = ...
    fixed_gardner(out.costas_i, out.costas_q, p);
[out.decoded_value, out.decoded_bits] = fixed_diff_decode(out.symbol_i, out.symbol_q);
end

function [yi,yq] = fixed_decimate4(xi,xq,h,shift)
nPackets = floor(numel(xi)/4);
yi = zeros(nPackets,1,'int16'); yq = yi;
for packet = 1:nPackets
    newest = 4*packet;
    ai = int64(0); aq = int64(0);
    for tap = 0:numel(h)-1
        index = newest-tap;
        if index >= 1
            ai = ai + int64(xi(index))*h(tap+1);
            aq = aq + int64(xq(index))*h(tap+1);
        end
    end
    yi(packet) = round_shift_sat16(ai,shift);
    yq(packet) = round_shift_sat16(aq,shift);
end
end

function [yi,yq] = fixed_fir(xi,xq,h,shift)
yi = zeros(size(xi),'int16'); yq = yi;
for n = 1:numel(xi)
    ai = int64(0); aq = int64(0);
    for tap = 0:min(numel(h)-1,n-1)
        ai = ai + int64(xi(n-tap))*h(tap+1);
        aq = aq + int64(xq(n-tap))*h(tap+1);
    end
    yi(n) = round_shift_sat16(ai,shift);
    yq(n) = round_shift_sat16(aq,shift);
end
end

function y = round_shift_sat16(x,shift)
half = bitshift(int64(1),shift-1);
if x >= 0, z = bitshift(x+half,-shift);
else, z = bitshift(x+half-1,-shift); end
y = sat16(z);
end

function y = sat16(x)
x = int64(x);
x(x > 32767) = 32767;
x(x < -32768) = -32768;
y = int16(x);
end

function [yoI,yoQ,freqLog,phaseLog] = fixed_costas(xi,xq,p)
n = numel(xi);
yoI = zeros(n,1,'int16'); yoQ = yoI;
freqLog = zeros(n,1,'int32'); phaseLog = zeros(n,1,'uint32');
frequency = int32(0); phase = uint32(0); errorReg=int16(0);
for k = 1:n
    phaseIndex = double(bitshift(phase,-24));
    ncoSin = int64(sin_lut_q15(phaseIndex));
    ncoCos = int64(sin_lut_q15(mod(phaseIndex+64,256)));
    mixIFull = int64(xi(k))*ncoCos + int64(xq(k))*ncoSin;
    mixQFull = int64(xq(k))*ncoCos - int64(xi(k))*ncoSin;
    mixI = sat16(bitshift(mixIFull,-15));
    mixQ = sat16(bitshift(mixQFull,-15));
    yoI(k)=mixI; yoQ(k)=mixQ;

    if mixI < 0, signedQ = -int64(mixQ); else, signedQ = int64(mixQ); end
    if mixQ < 0, signedI = -int64(mixI); else, signedI = int64(mixI); end
    rawError = signedQ-signedI;
    % RTL uses a fixed nominal detector magnitude of 8192.  Since the loop
    % error is Q1.15, this is exactly rawError*2^(15-13) = rawError*4.
    % Avoiding sample-by-sample division keeps the feedback path at one
    % sample/clock and makes the implementation timing-friendly.
    normalizedError=sat16(bitshift(rawError,p.costas.error_fraction_bits-13));
    proportional = wrap_i32(bitshift(int64(errorReg)*int64(p.costas.kp_phase_word), ...
        -p.costas.error_fraction_bits));
    integralDelta = wrap_i32(bitshift(int64(errorReg)*int64(p.costas.ki_phase_word), ...
        -p.costas.error_fraction_bits));

    oldFrequency = frequency;
    frequency = wrap_i32(int64(frequency)+int64(integralDelta));
    phase = wrap_u32(int64(phase)+int64(oldFrequency)+int64(proportional));
    freqLog(k)=frequency; phaseLog(k)=phase;
    errorReg=normalizedError;
end
end

function y = sin_lut_q15(index)
quarter = int16([0 804 1608 2410 3212 4011 4808 5602 6393 7179 7962 8739 9512 10278 11039 11793 12539 13279 14010 14732 15446 16151 16846 17530 18204 18868 19519 20159 20787 21403 22005 22594 23170 23731 24279 24811 25329 25832 26319 26790 27245 27683 28105 28510 28898 29268 29621 29956 30273 30571 30852 31113 31356 31580 31785 31971 32137 32285 32412 32521 32609 32678 32728 32757 32767]);
quadrant = floor(index/64); offset = mod(index,64);
switch quadrant
    case 0, y = quarter(offset+1);
    case 1, y = quarter(65-offset);
    case 2, y = -quarter(offset+1);
    otherwise, y = -quarter(65-offset);
end
end

function [soI,soQ,stepLog,errorLog] = fixed_gardner(xi,xq,p)
phase = uint32(0); step = int32(p.gardner.nominal_half_step);
halfToggle = false; warmup = uint8(0);
earlyI=int16(0); earlyQ=int16(0); middleI=int16(0); middleQ=int16(0);
previousErrorQ15=int16(0);
delayI=zeros(3,1,'int16'); delayQ=zeros(3,1,'int16');
pending=false; pendingMu=uint16(0);
pipeValid=false(4,1); pipeI=zeros(4,1,'int16'); pipeQ=zeros(4,1,'int16');
soI=int16([]); soQ=int16([]); stepLog=int32([]); errorLog=int64([]);
for k=1:numel(xi)
    oldStep=step;
    if pipeValid(1)
        interpI=pipeI(1); interpQ=pipeQ(1);
        deltaI=int64(interpI)-int64(earlyI); deltaQ=int64(interpQ)-int64(earlyQ);
        err=int64(middleI)*deltaI + int64(middleQ)*deltaQ;
        oldWarmup=warmup;
        earlyI=middleI; earlyQ=middleQ; middleI=interpI; middleQ=interpQ;
        if warmup ~= 7, warmup=warmup+1; end
        if ~halfToggle && oldWarmup >= 2
            errorQ15=sat16(bitshift(err,-p.gardner.error_shift));
            proportionalDelta=int64(p.gardner.kp_step_word)* ...
                (int64(errorQ15)-int64(previousErrorQ15));
            integralDelta=int64(p.gardner.ki_step_word)*int64(errorQ15);
            loopDelta=bitshift(proportionalDelta+integralDelta,-15);
            step=wrap_i32(int64(step)+loopDelta);
            previousErrorQ15=errorQ15;
            soI(end+1,1)=interpI; soQ(end+1,1)=interpQ; %#ok<AGROW>
            stepLog(end+1,1)=step; errorLog(end+1,1)=err; %#ok<AGROW>
        end
        halfToggle=~halfToggle;
    end
    pipeValid(1:3)=pipeValid(2:4); pipeValid(4)=false;
    pipeI(1:3)=pipeI(2:4); pipeQ(1:3)=pipeQ(2:4);

    % GoWinSDR uses a cubic Farrow interpolator before the Gardner TED.
    % A request is completed when the following input sample supplies the
    % one future point required by the four-sample polynomial. Four further
    % clocks reproduce the RTL multiplier pipeline plus module-boundary delay.
    if pending
        pipeI(4)=farrow_cubic_q15(xi(k),delayI(1),delayI(2),delayI(3),pendingMu);
        pipeQ(4)=farrow_cubic_q15(xq(k),delayQ(1),delayQ(2),delayQ(3),pendingMu);
        pipeValid(4)=true;
    end

    phaseSum = uint64(phase)+uint64(uint32(oldStep));
    if phaseSum >= uint64(4294967296)
        remaining=uint64(4294967296)-uint64(phase);
        mu=min(uint64(32768),bitshift(remaining*uint64(p.gardner.half_symbol_samples),-17));
        pendingMu=uint16(mu);
        pending=true;
    else
        pending=false;
    end
    phase = uint32(mod(phaseSum,uint64(4294967296)));
    delayI(3)=delayI(2); delayI(2)=delayI(1); delayI(1)=xi(k);
    delayQ(3)=delayQ(2); delayQ(2)=delayQ(1); delayQ(1)=xq(k);
end
% RTL continues clocking after in_valid falls, so drain already-launched
% Farrow results. A pending request without its required future input sample
% is intentionally not launched.
for flush=1:4
    if pipeValid(1)
        interpI=pipeI(1); interpQ=pipeQ(1);
        deltaI=int64(interpI)-int64(earlyI); deltaQ=int64(interpQ)-int64(earlyQ);
        err=int64(middleI)*deltaI + int64(middleQ)*deltaQ;
        oldWarmup=warmup;
        earlyI=middleI; earlyQ=middleQ; middleI=interpI; middleQ=interpQ;
        if warmup ~= 7, warmup=warmup+1; end
        if ~halfToggle && oldWarmup >= 2
            errorQ15=sat16(bitshift(err,-p.gardner.error_shift));
            proportionalDelta=int64(p.gardner.kp_step_word)* ...
                (int64(errorQ15)-int64(previousErrorQ15));
            integralDelta=int64(p.gardner.ki_step_word)*int64(errorQ15);
            step=wrap_i32(int64(step)+bitshift(proportionalDelta+integralDelta,-15));
            previousErrorQ15=errorQ15;
            soI(end+1,1)=interpI; soQ(end+1,1)=interpQ; %#ok<AGROW>
            stepLog(end+1,1)=step; errorLog(end+1,1)=err; %#ok<AGROW>
        end
        halfToggle=~halfToggle;
    end
    pipeValid(1:3)=pipeValid(2:4); pipeValid(4)=false;
    pipeI(1:3)=pipeI(2:4); pipeQ(1:3)=pipeQ(2:4);
end
end

function y=farrow_cubic_q15(x0,x1,x2,x3,mu)
% Bit-accurate form of GoWinSDR interpolate_filter.v, widened to 16-bit I/Q.
x0=int64(x0); x1=int64(x1); x2=int64(x2); x3=int64(x3); mu=int64(mu);
f1=bitshift(x0,-1)-bitshift(x1,-1)-bitshift(x2,-1)+bitshift(x3,-1);
f2=x1+bitshift(x1,-1)-bitshift(x0,-1)-bitshift(x2,-1)-bitshift(x3,-1);
f3=x2;
f1mu=bitshift(f1*mu,-15);
y=sat16(bitshift(f1mu*mu,-15)+bitshift(f2*mu,-15)+f3);
end

function [values,bits] = fixed_diff_decode(si,sq)
previousI=false; previousQ=false;
bits=zeros(numel(si),2); values=zeros(numel(si),1);
for k=1:numel(si)
    decisionI=si(k)>=0; decisionQ=sq(k)>=0;
    bits(k,1)=xor(decisionI,previousI); bits(k,2)=xor(decisionQ,previousQ);
    values(k)=bits(k,1)+2*bits(k,2);
    previousI=decisionI; previousQ=decisionQ;
end
end

function x = wrap_i32(v)
u=mod(double(v),2^32);
if u>=2^31, u=u-2^32; end
x=int32(u);
end

function x = wrap_u32(v)
x=uint32(mod(double(v),2^32));
end

function write_all_vectors(dirPath,adcI,adcQ,r,txBits,txDecisions,p)
stim = zeros(numel(adcI)/4,8);
for lane=0:3
    stim(:,2*lane+1)=double(adcI(lane+1:4:end));
    stim(:,2*lane+2)=double(adcQ(lane+1:4:end));
end
write_decimal(fullfile(dirPath,'rfdc_input_iq.txt'),stim,'%d ');
write_decimal(fullfile(dirPath,'expected_decim4.txt'),[r.decim_i r.decim_q],'%d ');
write_decimal(fullfile(dirPath,'expected_rrc.txt'),[r.rrc_i r.rrc_q],'%d ');

fid=fopen(fullfile(dirPath,'expected_costas.txt'),'w'); assert(fid>=0);
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
for k=1:numel(r.costas_i)
    fprintf(fid,'%d %d %d %08X\n',r.costas_i(k),r.costas_q(k), ...
        r.frequency_word(k),r.phase_word(k));
end
clear c

fid=fopen(fullfile(dirPath,'expected_symbols.txt'),'w'); assert(fid>=0);
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
for k=1:numel(r.symbol_i)
    fprintf(fid,'%d %d %d %d\n',r.symbol_i(k),r.symbol_q(k), ...
        r.timing_step(k),r.timing_error(k));
end
clear c
write_decimal(fullfile(dirPath,'expected_decoded.txt'),r.decoded_value,'%d ');
write_decimal(fullfile(dirPath,'tx_bits.txt'),txBits,'%d ');
write_decimal(fullfile(dirPath,'tx_decisions.txt'),double(txDecisions),'%d ');

fid=fopen(fullfile(dirPath,'manifest.txt'),'w'); assert(fid>=0);
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'seed=%d\n',p.seed);
fprintf(fid,'fs_rfdc_hz=%.0f\nfs_pl_hz=%.0f\nsymbol_rate_hz=%.0f\n', ...
    p.fs_rfdc,p.fs_pl,p.symbol_rate);
fprintf(fid,'samples_per_clock=%d\nsps_pl=%d\nsps_rfdc=%d\n', ...
    p.samples_per_clock,p.sps_pl,p.sps_rfdc);
fprintf(fid,'rrc_beta=%.8g\nrrc_span_symbols=%d\n',p.rrc_beta,p.rrc_span_symbols);
fprintf(fid,'channel_cfo_hz=%.8g\nchannel_phase_rad=%.8g\nchannel_snr_db=%.8g\n', ...
    p.channel.cfo_hz,p.channel.phase_rad,p.channel.snr_db);
fprintf(fid,'fractional_delay_rfdc_samples=%.8g\nsample_clock_ppm=%.8g\n', ...
    p.channel.fractional_delay_rfdc_samples,p.channel.sample_clock_ppm);
fprintf(fid,'profile=%s\n',p.profile);
fprintf(fid,'parameter_provenance=experimental_current_rtl_not_original_gowinsdr\n');
end

function write_decimal(path,matrix,format)
fid=fopen(path,'w'); assert(fid>=0,'Cannot create %s',path);
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
for row=1:size(matrix,1)
    for col=1:size(matrix,2)
        if col==size(matrix,2), fprintf(fid,strtrim(format),matrix(row,col));
        else, fprintf(fid,format,matrix(row,col)); end
    end
    fprintf(fid,'\n');
end
end

function [ber,bestLag,nCompared] = best_pair_ber(tx,rx,maxLag)
ber=Inf; bestLag=0; nCompared=0;
if isempty(rx), return; end
for lag=-maxLag:maxLag
    txStart=max(1,1+lag); rxStart=max(1,1-lag);
    count=min(size(tx,1)-txStart+1,size(rx,1)-rxStart+1);
    if count < 33, continue; end
    % The first aligned differential symbol depends on the decoder state from
    % the unmatched symbol immediately before the overlap. It is not a valid
    % payload comparison, so measure BER from the following symbol onward.
    errors=sum(sum(tx(txStart+1:txStart+count-1,:) ~= rx(rxStart+1:rxStart+count-1,:)));
    candidate=errors/(2*(count-1));
    if candidate<ber, ber=candidate; bestLag=lag; nCompared=count-1; end
end
end

function [bestBer,bestPhase,bestLag] = floating_open_loop_reference(adcI,adcQ,hDec,hRrc,txBits,p,oracleCarrier)
x=double(adcI)+1j*double(adcQ);
if oracleCarrier
    n=(0:numel(x)-1).';
    x=x.*exp(-1j*(p.channel.phase_rad+2*pi*p.channel.cfo_hz*n/p.fs_rfdc));
end
y=filter(double(hDec)/2^p.coeff_fraction_bits,1,x);
y=y(4:4:end);
y=filter(double(hRrc)/2^p.coeff_fraction_bits,1,y);
bestBer=Inf; bestPhase=1; bestLag=0;
for phase=1:p.sps_pl
    s=y(phase:p.sps_pl:end);
    d=[real(s)>=0 imag(s)>=0];
    b=zeros(size(d)); previous=false(1,2);
    for k=1:size(d,1)
        b(k,:)=xor(d(k,:),previous); previous=d(k,:);
    end
    [candidate,lag]=best_pair_ber(txBits,b,160);
    if candidate<bestBer, bestBer=candidate; bestPhase=phase; bestLag=lag; end
end
end
