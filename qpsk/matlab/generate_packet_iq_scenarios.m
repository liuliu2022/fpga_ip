% Generate complete framed QPSK waveforms for RTL receiver regression.
% The vectors enter gowinsdr_rx_chain directly as four RFDC-rate I/Q samples
% per PL clock, so neither RFDC DDC nor AXI DMA participates in the test.

clear; clc;
rng(20261014, 'twister');

thisDir = fileparts(mfilename('fullpath'));
qpskDir = fileparts(thisDir);
outRoot = fullfile(qpskDir, 'testdata', 'packet_iq_scenarios');
if ~exist(outRoot, 'dir'), mkdir(outRoot); end

fs = 245.76e6;
sps = 48;
payload = uint8(mod((0:63)*57 + 23, 256));
header = uint8([hex2dec('10') 0 numel(payload)]);
header = [header crc8_bytes(header)]; %#ok<AGROW>
fcs = crc32_bytes(payload);

preamble = repmat(uint8(hex2dec('55')), 1, 32);
sync = uint8([hex2dec('EB') hex2dec('90') hex2dec('CA') hex2dec('D3')]);
plainBody = [payload uint8(bitand(fcs,255)) ...
    uint8(bitand(bitshift(fcs,-8),255)) ...
    uint8(bitand(bitshift(fcs,-16),255)) ...
    uint8(bitand(bitshift(fcs,-24),255))];

airDibits = [bytes_to_dibits(preamble) bytes_to_dibits(sync) ...
    bytes_to_dibits(header) scramble_dibits(bytes_to_dibits(plainBody))];
% A zero dibit holds the previous differential constellation point, matching
% the idle behavior of tx_qpsk_diff_encode before and after an AXI frame.
dibits = [zeros(1,400,'uint8') airDibits zeros(1,400,'uint8')];
symbols = differential_symbols(dibits);

h = rrc_impulse(0.35, 10, sps);
upsampled = complex(zeros(numel(symbols)*sps,1));
upsampled(1:sps:end) = symbols;
baseWave = filter(h,1,upsampled);
baseWave = baseWave * (12000/max([abs(real(baseWave));abs(imag(baseWave));eps]));

profiles = struct( ...
    'name', {'baseline','phase90','combined','low_amp_20'}, ...
    'phase', {0,pi/2,0.55,0.31}, ...
    'cfo', {0,0,18e3,0}, ...
    'delay', {0,0,1.9,0}, ...
    'ppm', {0,0,35,0}, ...
    'snr', {Inf,Inf,20,Inf}, ...
    'amplitude', {1,1,1,20/14314});

n = (0:numel(baseWave)-1).';
for k = 1:numel(profiles)
    p = profiles(k);
    samplePosition = n*(1+p.ppm*1e-6)-p.delay;
    wave = interp1(n,baseWave,samplePosition,'pchip',0);
    wave = p.amplitude*wave .* exp(1j*(p.phase+2*pi*p.cfo*n/fs));
    if isfinite(p.snr)
        signalPower = mean(abs(wave).^2);
        noisePower = signalPower/10^(p.snr/10);
        wave = wave + sqrt(noisePower/2)*(randn(size(wave))+1j*randn(size(wave)));
    end
    adcI = int16(min(max(round(real(wave)),-32768),32767));
    adcQ = int16(min(max(round(imag(wave)),-32768),32767));
    pad = mod(-numel(adcI),4);
    adcI = [adcI;zeros(pad,1,'int16')]; %#ok<AGROW>
    adcQ = [adcQ;zeros(pad,1,'int16')]; %#ok<AGROW>
    lanes = zeros(numel(adcI)/4,8);
    for lane=0:3
        lanes(:,2*lane+1)=double(adcI(lane+1:4:end));
        lanes(:,2*lane+2)=double(adcQ(lane+1:4:end));
    end
    caseDir = fullfile(outRoot,p.name);
    if ~exist(caseDir,'dir'),mkdir(caseDir);end
    write_matrix(fullfile(caseDir,'iq_s16x4.txt'),lanes,'%d');
    fid=fopen(fullfile(caseDir,'manifest.txt'),'w');assert(fid>=0);
    fprintf(fid,'profile=%s\nphase_rad=%.12g\ncfo_hz=%.12g\n',p.name,p.phase,p.cfo);
    fprintf(fid,'amplitude_scale=%.12g\n',p.amplitude);
    fprintf(fid,'fractional_delay_samples=%.12g\nsample_clock_ppm=%.12g\nsnr_db=%.12g\n',p.delay,p.ppm,p.snr);
    fprintf(fid,'payload_bytes=%d\ninput_clocks=%d\n',numel(payload),size(lanes,1));
    fclose(fid);
end
write_matrix(fullfile(outRoot,'expected_payload.txt'),double(payload(:)),'%d');
fprintf('Generated packet I/Q scenarios in %s\n',outRoot);

function dibits=bytes_to_dibits(bytes)
dibits=zeros(1,4*numel(bytes),'uint8');
for k=1:numel(bytes)
    for d=0:3
        dibits(4*(k-1)+d+1)=uint8(bitand(bitshift(bytes(k),-(6-2*d)),3));
    end
end
end

function out=scramble_dibits(in)
state=uint8(hex2dec('5D'));out=zeros(size(in),'uint8');
for k=1:numel(in)
    feedback=bitxor(bitget(state,7),bitget(state,4));
    b1=bitxor(bitget(in(k),2),feedback);
    state=bitand(bitshift(state,1),127)+uint8(feedback);
    feedback=bitxor(bitget(state,7),bitget(state,4));
    b0=bitxor(bitget(in(k),1),feedback);
    state=bitand(bitshift(state,1),127)+uint8(feedback);
    out(k)=uint8(2*b1+b0);
end
end

function symbols=differential_symbols(dibits)
piState=false;pqState=false;symbols=complex(zeros(numel(dibits),1));
for k=1:numel(dibits)
    piState=xor(piState,bitget(dibits(k),1)~=0);
    pqState=xor(pqState,bitget(dibits(k),2)~=0);
    symbols(k)=complex(2*double(piState)-1,2*double(pqState)-1)/sqrt(2);
end
end

function crc=crc8_bytes(bytes)
crc=uint8(0);
for x=bytes
    crc=bitxor(crc,x);
    for b=1:8
        if bitget(crc,8),crc=bitxor(bitshift(crc,1),uint8(7));
        else,crc=bitshift(crc,1);end
    end
end
end

function crc=crc32_bytes(bytes)
crc=uint32(hex2dec('FFFFFFFF'));
poly=uint32(hex2dec('EDB88320'));
for x=bytes
    crc=bitxor(crc,uint32(x));
    for b=1:8
        if bitget(crc,1),crc=bitxor(bitshift(crc,-1),poly);
        else,crc=bitshift(crc,-1);end
    end
end
crc=bitcmp(crc);
end

function h=rrc_impulse(beta,span,sps)
t=(-span*sps/2:span*sps/2).'/sps;h=zeros(size(t));
for k=1:numel(t)
    x=t(k);
    if abs(x)<1e-12,h(k)=1+beta*(4/pi-1);
    elseif abs(abs(x)-1/(4*beta))<1e-12
        h(k)=beta/sqrt(2)*((1+2/pi)*sin(pi/(4*beta))+(1-2/pi)*cos(pi/(4*beta)));
    else
        h(k)=(sin(pi*x*(1-beta))+4*beta*x*cos(pi*x*(1+beta)))/(pi*x*(1-(4*beta*x)^2));
    end
end
h=h/sqrt(sum(h.^2));
end

function write_matrix(path,m,fmt)
fid=fopen(path,'w');assert(fid>=0,'Cannot create %s',path);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
for r=1:size(m,1)
    for col=1:size(m,2)
        if col>1,fprintf(fid,' ');end
        fprintf(fid,fmt,m(r,col));
    end
    fprintf(fid,'\n');
end
end
