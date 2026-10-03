clear; clc;

matlabDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(matlabDir);
outDir = fullfile(repoRoot,'rtl','rx');

%% RFDC vector-to-scalar anti-alias decimator
FsIn  = 245.76e6;
M     = 4;
FsOut = FsIn/M;
Fpass = 8.0e6;
Fstop = FsOut/2;
Apass = 0.10;
Astop = 80;
coeffBits = 18;
qScale = 2^(coeffBits-1);

dp = (10^(Apass/20)-1)/(10^(Apass/20)+1);
ds = 10^(-Astop/20);
[n, fo, ao, w] = firpmord([Fpass Fstop], [1 0], [dp ds], FsIn);
taps = 4*ceil((n+1)/4);
while true
    n = taps-1;
    h = firpm(n, fo, ao, w);
    h = h/sum(h);
    hq = round(h*qScale);

    % Preserve symmetry and force exact unity DC gain in Q1.17.
    delta = qScale-sum(hq);
    if mod(delta,2) ~= 0
        error('Expected an even DC correction for the even-length symmetric FIR.');
    end
    hq(taps/2) = hq(taps/2) + delta/2;
    hq(taps/2+1) = hq(taps/2+1) + delta/2;
    hfix = hq/qScale;

    [H,F] = freqz(hfix,1,131072,FsIn);
    pass = F <= Fpass;
    stop = F >= Fstop;
    passRipple = 20*log10(max(abs(H(pass)))/min(abs(H(pass))));
    stopAtten = -20*log10(max(abs(H(stop))));
    if passRipple <= Apass && stopAtten >= Astop
        break;
    end
    taps = taps+4;
end

writeVector(fullfile(outDir,'rx_decim4_coeffs_q17.txt'),hq);

%% QPSK receive matched RRC at the decimator output rate
symbolRate = 5.12e6;
sps = round(FsOut/symbolRate);
beta = 0.35;
span = 10;
rrc = localRRC(beta,span,sps);
rrc = rrc/sum(rrc);             % unity DC gain for fixed-point headroom
rrcq = round(rrc*qScale);
rrcDelta = qScale-sum(rrcq);
rrcq((numel(rrcq)+1)/2) = rrcq((numel(rrcq)+1)/2)+rrcDelta;
rrcfix = rrcq/qScale;
writeVector(fullfile(outDir,'rx_rrc_coeffs_q17.txt'),rrcq);

fprintf('DECIM_FS_IN_HZ=%0.0f\n',FsIn);
fprintf('DECIM_FS_OUT_HZ=%0.0f\n',FsOut);
fprintf('DECIM_FACTOR=%d\n',M);
fprintf('DECIM_TAPS=%d\n',numel(hq));
fprintf('DECIM_PASS_RIPPLE_DB=%.6f\n',passRipple);
fprintf('DECIM_STOP_ATTEN_DB=%.3f\n',stopAtten);
fprintf('DECIM_QSUM=%d\n',sum(hq));
fprintf('RRC_SYMBOL_RATE_HZ=%0.0f\n',symbolRate);
fprintf('RRC_SPS=%d\n',sps);
fprintf('RRC_TAPS=%d\n',numel(rrcq));
fprintf('RRC_QSUM=%d\n',sum(rrcq));

function writeVector(path,v)
    fid=fopen(path,'w');
    assert(fid>=0,'Cannot open output file');
    cleaner=onCleanup(@() fclose(fid));
    for k=1:numel(v)
        fprintf(fid,'%d\n',v(k));
    end
end

function h = localRRC(beta,span,sps)
    t=(-span*sps/2:span*sps/2)/sps;
    h=zeros(size(t));
    for k=1:numel(t)
        tk=t(k);
        if abs(tk)<1e-12
            h(k)=1+beta*(4/pi-1);
        elseif abs(abs(tk)-1/(4*beta))<1e-10
            h(k)=(beta/sqrt(2))*((1+2/pi)*sin(pi/(4*beta))+(1-2/pi)*cos(pi/(4*beta)));
        else
            h(k)=(sin(pi*tk*(1-beta))+4*beta*tk*cos(pi*tk*(1+beta)))/(pi*tk*(1-(4*beta*tk)^2));
        end
    end
    h=h/sqrt(sum(h.^2));
end
