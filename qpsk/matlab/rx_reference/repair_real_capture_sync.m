function reports = repair_real_capture_sync
%REPAIR_REAL_CAPTURE_SYNC Floating-point theory repair using real ILA input.
% This stage deliberately changes no RTL.  It establishes amplitude-normalized
% bounded Costas and Gardner behavior before fixed-point implementation.

thisDir=fileparts(mfilename('fullpath'));
matlabDir=fileparts(thisDir);
repoRoot=fileparts(matlabDir);
captureRoot=fullfile(repoRoot,'testdata','ila_board_captures','stimulus');
resultRoot=fullfile(repoRoot,'scenario_results','real_capture_sync_repair');
if ~exist(resultRoot,'dir'), mkdir(resultRoot); end

cfg.fs=61.44e6;
cfg.symbolRate=5.12e6;
cfg.sps=cfg.fs/cfg.symbolRate;
cfg.costasKp=double(19059814)*2*pi/2^32;
cfg.costasKi=double(269587)*2*pi/2^32;
cfg.costasMaxHz=250e3;
cfg.costasMagnitudeFloor=256;
cfg.costasUnlockThreshold=0.42;
cfg.costasUnlockSamples=128;
cfg.costasRecoveryCooldown=512;
cfg.gardnerKp=0.060;
cfg.gardnerKi=0.0008;
cfg.gardnerMinHalfPeriod=5.70;
cfg.gardnerMaxHalfPeriod=6.30;
cfg.repetitions=16;
cfg.discardSymbols=120;

hRrc=double(load(fullfile(repoRoot,'rtl','rx','rx_rrc_coeffs_q17.txt')))/2^17;
cases={ ...
    struct('name','rx_reset','file','rx_decim_iq_s16.txt','initialHz',0,'noiseBurst',false), ...
    struct('name','iladata_reset','file','iladata_decim_iq_s16.txt','initialHz',0,'noiseBurst',false), ...
    struct('name','iladata_recover_from_bad_state','file','iladata_decim_iq_s16.txt', ...
           'initialHz',-11.6e6,'noiseBurst',false), ...
    struct('name','iladata_noise_burst','file','iladata_decim_iq_s16.txt', ...
           'initialHz',0,'noiseBurst',true)};

reports=repmat(struct(),numel(cases),1);
for caseIndex=1:numel(cases)
    c=cases{caseIndex};
    base=load(fullfile(captureRoot,c.file));
    base=complex(base(:,1),base(:,2));
    coherentLength=floor(numel(base)/48)*48;
    z=repmat(base(1:coherentLength),cfg.repetitions,1);
    if c.noiseBurst
        rng(20261014,'twister');
        burstStart=floor(numel(z)*0.35);
        burstStop=burstStart+2400;
        signalRms=sqrt(mean(abs(z).^2));
        z(burstStart:burstStop)=z(burstStart:burstStop)+2.5*signalRms/sqrt(2)* ...
            (randn(burstStop-burstStart+1,1)+1j*randn(burstStop-burstStart+1,1));
    else
        burstStart=0; burstStop=0;
    end

    matched=filter(hRrc,1,z);
    costas=boundedNormalizedCostas(matched,c.initialHz,cfg);
    gardner=boundedNormalizedGardner(costas.samples,cfg);
    decoded=differentialDecode(gardner.symbols);
    usable=decoded(min(numel(decoded)+1,cfg.discardSymbols+1):end);
    [wer,offset]=bestCycleWer(usable,[0 1 2 3]);
    swapped=swapDibitChannels(usable);
    [swappedWer,swappedOffset]=bestCycleWer(swapped,[0 1 2 3]);
    resolvedWer=min(wer,swappedWer);
    tailCount=min(400,numel(decoded));
    tailDecoded=decoded(end-tailCount+1:end);
    [tailDirectWer,~]=bestCycleWer(tailDecoded,[0 1 2 3]);
    [tailSwappedWer,~]=bestCycleWer(swapDibitChannels(tailDecoded),[0 1 2 3]);
    tailResolvedWer=min(tailDirectWer,tailSwappedWer);

    reports(caseIndex).name=c.name;
    reports(caseIndex).decodedCount=numel(decoded);
    reports(caseIndex).cycleWer=wer;
    reports(caseIndex).cycleOffset=offset;
    reports(caseIndex).swappedCycleWer=swappedWer;
    reports(caseIndex).swappedCycleOffset=swappedOffset;
    reports(caseIndex).ambiguityResolvedWer=resolvedWer;
    reports(caseIndex).tailAmbiguityResolvedWer=tailResolvedWer;
    reports(caseIndex).tailFrequencyHz=mean(costas.frequencyHz(max(1,end-1023):end));
    reports(caseIndex).tailHalfPeriod=mean(gardner.halfPeriod(max(1,end-127):end));
    reports(caseIndex).frequencyLimitedFraction=mean(costas.frequencyLimited);
    reports(caseIndex).timingLimitedFraction=mean(gardner.timingLimited);
    reports(caseIndex).costas=costas;
    reports(caseIndex).gardner=gardner;
    reports(caseIndex).decoded=decoded;
    reports(caseIndex).burstStart=burstStart;
    reports(caseIndex).burstStop=burstStop;

    fprintf('%s: symbols=%d WER=%.6g resolved=%.6g offset=%d tail CFO=%.3f Hz half=%.6f samples\n', ...
        c.name,numel(decoded),wer,resolvedWer,offset,reports(caseIndex).tailFrequencyHz, ...
        reports(caseIndex).tailHalfPeriod);
end
save(fullfile(resultRoot,'repair_results.mat'),'reports','cfg');
writeReport(fullfile(resultRoot,'repair_results.txt'),reports,cfg);
plotResults(fullfile(resultRoot,'repair_results.png'),reports,cfg);
fprintf('Results: %s\n',resultRoot);
end

function out=boundedNormalizedCostas(x,initialHz,cfg)
n=numel(x); y=complex(zeros(n,1));
frequency=2*pi*initialHz/cfg.fs;
maxFrequency=2*pi*cfg.costasMaxHz/cfg.fs;
frequency=min(max(frequency,-maxFrequency),maxFrequency);
phase=0; frequencyLog=zeros(n,1); errorLog=zeros(n,1); limited=false(n,1);
lockMetric=0; unlockCount=0; cooldown=0; recoveryPulse=false(n,1);
for k=1:n
    mixed=x(k)*exp(-1j*phase);
    y(k)=mixed;
    magnitude=max(abs(real(mixed))+abs(imag(mixed)),cfg.costasMagnitudeFloor);
    error=(signNonzero(real(mixed))*imag(mixed)- ...
        signNonzero(imag(mixed))*real(mixed))/magnitude;
    candidate=frequency+cfg.costasKi*error;
    limited(k)=candidate>maxFrequency || candidate< -maxFrequency;
    frequency=min(max(candidate,-maxFrequency),maxFrequency);
    phase=mod(phase+frequency+cfg.costasKp*error+pi,2*pi)-pi;
    lockMetric=lockMetric+(abs(error)-lockMetric)/64;
    if cooldown>0, cooldown=cooldown-1; end
    if lockMetric>cfg.costasUnlockThreshold
        unlockCount=unlockCount+1;
    else
        unlockCount=max(0,unlockCount-1);
    end
    if unlockCount>=cfg.costasUnlockSamples && cooldown==0
        % Return to the DDC centre frequency.  Repeated resets during a noise
        % burst are harmless; the first quiet interval starts clean capture.
        frequency=0; phase=0; lockMetric=0; unlockCount=0;
        cooldown=cfg.costasRecoveryCooldown; recoveryPulse(k)=true;
    end
    frequencyLog(k)=frequency*cfg.fs/(2*pi);
    errorLog(k)=error;
end
out.samples=y; out.frequencyHz=frequencyLog; out.error=errorLog;
out.frequencyLimited=limited;
out.recoveryPulse=recoveryPulse;
end

function out=boundedNormalizedGardner(x,cfg)
% Standard early/middle/late Gardner detector with a bounded half-symbol NCO.
n=numel(x); nextTime=4.0; halfPeriod=cfg.sps/2;
events=complex([]); eventTimes=[]; symbols=complex([]);
halfLog=[]; errorLog=[]; limitedLog=[]; previousError=0;
while nextTime <= n-3
    sample=interp1((1:n).',x,nextTime,'pchip');
    events(end+1,1)=sample; %#ok<AGROW>
    eventTimes(end+1,1)=nextTime; %#ok<AGROW>
    eventCount=numel(events);
    if eventCount>=3 && mod(eventCount,2)==1
        early=events(end-2); middle=events(end-1); late=events(end);
        rawError=real(conj(middle)*(late-early));
        energy=max(abs(middle)^2+0.5*(abs(early)^2+abs(late)^2),1);
        error=rawError/energy;
        candidate=halfPeriod+cfg.gardnerKp*(error-previousError)+cfg.gardnerKi*error;
        limited=candidate<cfg.gardnerMinHalfPeriod || candidate>cfg.gardnerMaxHalfPeriod;
        halfPeriod=min(max(candidate,cfg.gardnerMinHalfPeriod),cfg.gardnerMaxHalfPeriod);
        previousError=error;
        symbols(end+1,1)=middle; %#ok<AGROW>
        halfLog(end+1,1)=halfPeriod; %#ok<AGROW>
        errorLog(end+1,1)=error; %#ok<AGROW>
        limitedLog(end+1,1)=limited; %#ok<AGROW>
    end
    nextTime=nextTime+halfPeriod;
end
out.symbols=symbols; out.halfPeriod=halfLog; out.error=errorLog;
out.timingLimited=logical(limitedLog); out.eventTimes=eventTimes;
end

function values=differentialDecode(symbols)
previousI=false; previousQ=false; values=zeros(numel(symbols),1);
for k=1:numel(symbols)
    decisionI=real(symbols(k))>=0; decisionQ=imag(symbols(k))>=0;
    bitI=xor(decisionI,previousI); bitQ=xor(decisionQ,previousQ);
    values(k)=double(bitI)+2*double(bitQ);
    previousI=decisionI; previousQ=decisionQ;
end
end

function swapped=swapDibitChannels(values)
values=uint8(values(:));
swapped=double(bitshift(bitand(values,1),1)+bitshift(bitand(values,2),-1));
end

function [bestError,bestOffset]=bestCycleWer(actual,cycle)
if isempty(actual), bestError=NaN; bestOffset=0; return; end
bestError=Inf; bestOffset=0;
for offset=0:numel(cycle)-1
    expected=cycle(mod((0:numel(actual)-1)+offset,numel(cycle))+1).';
    candidate=mean(actual(:)~=expected(:));
    if candidate<bestError, bestError=candidate; bestOffset=offset; end
end
end

function y=signNonzero(x)
if x<0, y=-1; else, y=1; end
end

function writeReport(path,reports,cfg)
fid=fopen(path,'w'); assert(fid>=0); cleaner=onCleanup(@() fclose(fid));
fprintf(fid,'costas_kp=%.12g\ncostas_ki=%.12g\ncostas_limit_hz=%.12g\n', ...
    cfg.costasKp,cfg.costasKi,cfg.costasMaxHz);
fprintf(fid,'gardner_kp=%.12g\ngardner_ki=%.12g\ngardner_half_period_range=%.6f %.6f\n\n', ...
    cfg.gardnerKp,cfg.gardnerKi,cfg.gardnerMinHalfPeriod,cfg.gardnerMaxHalfPeriod);
for k=1:numel(reports)
    r=reports(k);
    fprintf(fid,'%s\n',r.name);
    fprintf(fid,'  decoded_symbols=%d\n',r.decodedCount);
    fprintf(fid,'  cycle_word_error_rate=%.12g offset=%d\n',r.cycleWer,r.cycleOffset);
    fprintf(fid,'  swapped_cycle_word_error_rate=%.12g offset=%d\n', ...
        r.swappedCycleWer,r.swappedCycleOffset);
    fprintf(fid,'  ambiguity_resolved_word_error_rate=%.12g\n',r.ambiguityResolvedWer);
    fprintf(fid,'  tail_400_ambiguity_resolved_word_error_rate=%.12g\n', ...
        r.tailAmbiguityResolvedWer);
    fprintf(fid,'  costas_recovery_events=%d\n',nnz(r.costas.recoveryPulse));
    fprintf(fid,'  tail_frequency_hz=%.12g\n',r.tailFrequencyHz);
    fprintf(fid,'  tail_half_period_samples=%.12g\n',r.tailHalfPeriod);
    fprintf(fid,'  frequency_limited_fraction=%.12g\n',r.frequencyLimitedFraction);
    fprintf(fid,'  timing_limited_fraction=%.12g\n\n',r.timingLimitedFraction);
end
end

function plotResults(path,reports,cfg)
f=figure('Visible','off','Color','w','Position',[50 40 1700 1200]);
tiledlayout(3,2,'TileSpacing','compact','Padding','compact');
colors=lines(numel(reports));
nexttile;
for k=1:numel(reports), plot(reports(k).costas.frequencyHz/1e3,'Color',colors(k,:)); hold on; end
yline(cfg.costasMaxHz/1e3,'--'); yline(-cfg.costasMaxHz/1e3,'--'); grid on;
xlabel('61.44-MSPS sample'); ylabel('frequency correction (kHz)'); title('Bounded normalized Costas');
legend({reports.name},'Location','best');
nexttile;
for k=1:numel(reports), plot(reports(k).costas.error,'Color',colors(k,:)); hold on; end
grid on; xlabel('sample'); ylabel('normalized phase error'); title('Costas detector error');
nexttile;
for k=1:numel(reports), plot(reports(k).gardner.halfPeriod,'Color',colors(k,:)); hold on; end
yline(6,'--'); grid on; xlabel('symbol'); ylabel('samples / half-symbol'); title('Bounded normalized Gardner');
nexttile;
for k=1:numel(reports), plot(reports(k).gardner.error,'Color',colors(k,:)); hold on; end
grid on; xlabel('symbol'); ylabel('normalized timing error'); title('Gardner detector error');
nexttile;
for k=1:numel(reports)
    z=reports(k).gardner.symbols; start=min(numel(z),121);
    plot(real(z(start:end)),imag(z(start:end)),'.','Color',colors(k,:)); hold on;
end
axis equal; grid on; xlabel('I'); ylabel('Q'); title('Recovered symbols');
nexttile;
for k=1:numel(reports)
    count=min(80,numel(reports(k).decoded));
    stairs(0:count-1,reports(k).decoded(1:count),'Color',colors(k,:)); hold on;
end
ylim([-0.3 3.3]); yticks(0:3); grid on; xlabel('decoded index'); ylabel('dibit');
title('Recovered differential dibits'); legend({reports.name},'Location','best');
sgtitle('MATLAB theory repair on real RFSoC ILA input');
print(f,path,'-dpng','-r180'); close(f);
end
