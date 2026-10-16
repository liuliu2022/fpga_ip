function reports=repair_real_capture_fixed
%REPAIR_REAL_CAPTURE_FIXED Bit-oriented candidate for the RTL repair.

thisDir=fileparts(mfilename('fullpath')); matlabDir=fileparts(thisDir);
repoRoot=fileparts(matlabDir);
captureRoot=fullfile(repoRoot,'testdata','ila_board_captures','stimulus');
resultRoot=fullfile(repoRoot,'scenario_results','real_capture_sync_repair_fixed');
if ~exist(resultRoot,'dir'), mkdir(resultRoot); end

p.fs=61.44e6;
p.costasKp=int32(19059814); p.costasKi=int32(269587);
p.costasLimit=int32(round(250e3*2^32/p.fs));
p.costasMagnitudeFloor=16;
p.signalOnMagnitude=16; p.signalOffMagnitude=10;
p.signalOnSamples=64; p.signalOffSamples=128; p.signalAverageShift=5;
p.unlockThreshold=int32(round(0.28*32768));
p.unlockSamples=128; p.recoveryCooldown=512;
p.lockThreshold=int32(round(0.24*32768));
p.lockSamples=256;
p.nominalStep=int32(715827883);
p.minStep=int32(floor(2^32/6.30));
p.maxStep=int32(ceil(2^32/5.70));
% Convert the reference half-period loop gains to the NCO step-word domain.
% The accumulator/Farrow event convention reverses the detector polarity,
% cancelling d(step)/d(halfPeriod)'s minus sign.
p.gardnerKp=int32(round((2^32/36)*0.060));
p.gardnerKi=int32(round((2^32/36)*0.0008));
p.magnitudeFloor=16;
p.repetitions=32; p.discardSymbols=120;

hRrc=int64(load(fullfile(repoRoot,'rtl','rx','rx_rrc_coeffs_q17.txt')));
cases={ ...
 struct('name','rx_reset','file','rx_decim_iq_s16.txt','initialHz',0,'noiseBurst',false,'targetRrcL1',[]), ...
 struct('name','iladata_reset','file','iladata_decim_iq_s16.txt','initialHz',0,'noiseBurst',false,'targetRrcL1',[]), ...
 struct('name','iladata_recover_from_bad_state','file','iladata_decim_iq_s16.txt','initialHz',-11.6e6,'noiseBurst',false,'targetRrcL1',[]), ...
 struct('name','iladata_noise_burst','file','iladata_decim_iq_s16.txt','initialHz',0,'noiseBurst',true,'targetRrcL1',[]), ...
 struct('name','rx_low_l1_20','file','rx_decim_iq_s16.txt','initialHz',0,'noiseBurst',false,'targetRrcL1',20), ...
 struct('name','rx_below_gate_l1_6','file','rx_decim_iq_s16.txt','initialHz',0,'noiseBurst',false,'targetRrcL1',6)};

reports=repmat(struct(),numel(cases),1);
for caseIndex=1:numel(cases)
    c=cases{caseIndex}; base=load(fullfile(captureRoot,c.file));
    coherentLength=floor(size(base,1)/48)*48;
    base=base(1:coherentLength,:);
    if ~isempty(c.targetRrcL1)
        [baseRrcI,baseRrcQ]=fixedFir(int16(base(:,1)),int16(base(:,2)),hRrc,17);
        referenceMagnitude=mean(abs(double(baseRrcI(200:end)))+abs(double(baseRrcQ(200:end))));
        scale=c.targetRrcL1/referenceMagnitude;
        base(:,1)=double(sat16(int64(round(double(base(:,1))*scale))));
        base(:,2)=double(sat16(int64(round(double(base(:,2))*scale))));
    end
    xi=repmat(int16(base(:,1)),p.repetitions,1);
    xq=repmat(int16(base(:,2)),p.repetitions,1);
    if c.noiseBurst
        rng(20261014,'twister'); first=floor(numel(xi)*0.35); last=first+2400;
        signalRms=sqrt(mean(double(xi).^2+double(xq).^2));
        xi(first:last)=sat16(int64(xi(first:last))+int64(round(2.5*signalRms/sqrt(2)*randn(last-first+1,1))));
        xq(first:last)=sat16(int64(xq(first:last))+int64(round(2.5*signalRms/sqrt(2)*randn(last-first+1,1))));
    end
    [rrcI,rrcQ]=fixedFir(xi,xq,hRrc,17);
    initialWord=int64(round(c.initialHz*2^32/p.fs));
    [costasI,costasQ,freqLog,recoveryLog,costasError,lockMetric,lockedLog,signalLog]=fixedCostasCandidate(rrcI,rrcQ,initialWord,p);
    [symbolI,symbolQ,stepLog,gardnerError]=fixedGardnerCandidate(costasI,costasQ,lockedLog,p);
    decoded=fixedDiffDecode(symbolI,symbolQ);
    usable=decoded(min(numel(decoded)+1,p.discardSymbols+1):end);
    [directWer,directOffset]=bestCycleWer(usable,[0 1 2 3]);
    [swappedWer,swappedOffset]=bestCycleWer(swapDibitChannels(usable),[0 1 2 3]);
    % Exclude the deliberately induced reacquisition transient.  The final
    % 256 decisions are the stable post-lock validation window.
    tailCount=min(256,numel(decoded)); tail=decoded(end-tailCount+1:end);
    tailWer=min(bestCycleWer(tail,[0 1 2 3]),bestCycleWer(swapDibitChannels(tail),[0 1 2 3]));

    reports(caseIndex).name=c.name;
    reports(caseIndex).decodedCount=numel(decoded);
    reports(caseIndex).directWer=directWer;
    reports(caseIndex).directOffset=directOffset;
    reports(caseIndex).swappedWer=swappedWer;
    reports(caseIndex).swappedOffset=swappedOffset;
    reports(caseIndex).resolvedWer=min(directWer,swappedWer);
    reports(caseIndex).tailResolvedWer=tailWer;
    reports(caseIndex).tailFrequencyHz=mean(double(freqLog(max(1,end-1023):end)))*p.fs/2^32;
    reports(caseIndex).tailHalfPeriod=mean(2^32./double(stepLog(max(1,end-127):end)));
    reports(caseIndex).recoveryEvents=nnz(recoveryLog);
    reports(caseIndex).frequencyWord=freqLog;
    reports(caseIndex).costasError=costasError;
    reports(caseIndex).lockMetric=lockMetric;
    reports(caseIndex).costasLocked=lockedLog;
    reports(caseIndex).signalPresent=signalLog;
    reports(caseIndex).meanCostasL1=mean(abs(double(costasI(end-1023:end)))+abs(double(costasQ(end-1023:end))));
    reports(caseIndex).timingStep=stepLog;
    reports(caseIndex).gardnerError=gardnerError;
    reports(caseIndex).symbolI=symbolI; reports(caseIndex).symbolQ=symbolQ;
    reports(caseIndex).decoded=decoded;
    fprintf('%s: N=%d direct=%.6g swapped=%.6g tail=%.6g CFO=%.2fHz half=%.6f recover=%d signal=%.1f%% L1=%.2f\n', ...
        c.name,numel(decoded),directWer,swappedWer,tailWer, ...
        reports(caseIndex).tailFrequencyHz,reports(caseIndex).tailHalfPeriod, ...
        reports(caseIndex).recoveryEvents,100*mean(signalLog),reports(caseIndex).meanCostasL1);
end
lowReport=reports(strcmp({reports.name},'rx_low_l1_20'));
weakReport=reports(strcmp({reports.name},'rx_below_gate_l1_6'));
assert(lowReport.tailResolvedWer==0 && any(lowReport.costasLocked), ...
    'Amplitude-20 waveform did not decode cleanly');
assert(weakReport.decodedCount==0 && ~any(weakReport.signalPresent), ...
    'Below-threshold waveform was not rejected');
save(fullfile(resultRoot,'fixed_repair_results.mat'),'reports','p');
writeFixedReport(fullfile(resultRoot,'fixed_repair_results.txt'),reports,p);
end
function [yi,yq]=fixedFir(xi,xq,h,shift)
ai=filter(double(h),1,double(xi)); aq=filter(double(h),1,double(xq));
yi=roundShiftSat16Vector(ai,shift); yq=roundShiftSat16Vector(aq,shift);
end

function y=roundShiftSat16Vector(x,shift)
half=2^(shift-1); z=zeros(size(x)); positive=x>=0;
z(positive)=floor((x(positive)+half)/2^shift);
z(~positive)=floor((x(~positive)+half-1)/2^shift);
y=int16(max(min(z,32767),-32768));
end

function [yoI,yoQ,freqLog,recoveryLog,errorLog,metricLog,lockedLog,signalLog]=fixedCostasCandidate(xi,xq,initialWord,p)
n=numel(xi); yoI=zeros(n,1,'int16'); yoQ=yoI;
freqLog=zeros(n,1,'int32'); recoveryLog=false(n,1);
errorLog=zeros(n,1,'int16'); metricLog=zeros(n,1,'int32');
lockedLog=false(n,1);
signalLog=false(n,1);
frequency=int32(min(max(initialWord,-int64(p.costasLimit)),int64(p.costasLimit)));
phase=uint32(0); errorReg=int16(0); metric=int32(0);
unlockCount=0; cooldown=0; lockGoodCount=0; locked=false;
signalAccumulator=int64(0); signalOnCount=0; signalOffCount=0; signalPresent=false;
signalOnThreshold=int64(p.signalOnMagnitude)*bitshift(int64(1),p.signalAverageShift);
signalOffThreshold=int64(p.signalOffMagnitude)*bitshift(int64(1),p.signalAverageShift);
for k=1:n
    phaseIndex=double(bitshift(phase,-24));
    ncoSin=int64(sinLutQ15(phaseIndex));
    ncoCos=int64(sinLutQ15(mod(phaseIndex+64,256)));
    mixI=sat16(bitshift(int64(xi(k))*ncoCos+int64(xq(k))*ncoSin,-15));
    mixQ=sat16(bitshift(int64(xq(k))*ncoCos-int64(xi(k))*ncoSin,-15));
    yoI(k)=mixI; yoQ(k)=mixQ;
    if mixI<0, signedQ=-int64(mixQ); else, signedQ=int64(mixQ); end
    if mixQ<0, signedI=-int64(mixI); else, signedI=int64(mixI); end
    rawError=signedQ-signedI;
    magnitude=abs(int64(mixI))+abs(int64(mixQ));
    signalAccumulator=signalAccumulator-bitshift(signalAccumulator,-p.signalAverageShift)+magnitude;
    if ~signalPresent
        signalOffCount=0;
        if signalAccumulator>=signalOnThreshold, signalOnCount=signalOnCount+1;
        else, signalOnCount=0; end
        if signalOnCount>=p.signalOnSamples
            signalPresent=true; signalOnCount=0;
        end
    else
        signalOnCount=0;
        if signalAccumulator<=signalOffThreshold, signalOffCount=signalOffCount+1;
        else, signalOffCount=0; end
        if signalOffCount>=p.signalOffSamples
            signalPresent=false; signalOffCount=0;
        end
    end
    signalLog(k)=signalPresent;
    if ~signalPresent
        frequency=int32(0); phase=uint32(0); errorReg=int16(0); metric=int32(0);
        unlockCount=0; cooldown=0; lockGoodCount=0; locked=false;
        freqLog(k)=frequency; errorLog(k)=errorReg; metricLog(k)=metric;
        lockedLog(k)=false;
        continue;
    end
    exponent=nextpow2(max(double(magnitude),p.costasMagnitudeFloor));
    shift=15-exponent;
    if shift>=0, scaled=bitshift(rawError,shift); else, scaled=bitshift(rawError,shift); end
    normalized=sat16(scaled);

    proportional=wrapI32(bitshift(int64(errorReg)*int64(p.costasKp),-15));
    integral=bitshift(int64(errorReg)*int64(p.costasKi),-15);
    candidate=int64(frequency)+integral;
    candidate=min(max(candidate,-int64(p.costasLimit)),int64(p.costasLimit));
    oldFrequency=frequency; frequency=int32(candidate);
    phase=wrapU32(int64(phase)+int64(oldFrequency)+int64(proportional));

    absError=abs(int64(errorReg));
    metric=int32(int64(metric)+bitshift(absError-int64(metric),-6));
    if cooldown>0, cooldown=cooldown-1; end
    if metric>p.unlockThreshold, unlockCount=unlockCount+1;
    else, unlockCount=max(0,unlockCount-1); end
    if unlockCount>=p.unlockSamples && cooldown==0
        frequency=int32(0); phase=uint32(0); metric=int32(0); unlockCount=0;
        cooldown=p.recoveryCooldown; recoveryLog(k)=true;
        lockGoodCount=0; locked=false;
    end
    if metric<p.lockThreshold && cooldown==0
        lockGoodCount=min(p.lockSamples,lockGoodCount+1);
    else
        lockGoodCount=0;
    end
    if recoveryLog(k)
        locked=false;
    elseif lockGoodCount>=p.lockSamples
        locked=true;
    end
    lockedLog(k)=locked;
    freqLog(k)=frequency; errorReg=normalized;
    errorLog(k)=errorReg; metricLog(k)=metric;
end
end

function [soI,soQ,stepLog,errorLog]=fixedGardnerCandidate(xi,xq,costasLocked,p)
phase=uint32(0); step=p.nominalStep; halfToggle=false; warmup=uint8(0);
earlyI=int16(0); earlyQ=int16(0); middleI=int16(0); middleQ=int16(0);
previousError=int16(0); delayI=zeros(3,1,'int16'); delayQ=delayI;
pending=false; pendingMu=uint16(0); pipeValid=false(4,1);
pipeI=zeros(4,1,'int16'); pipeQ=pipeI;
soI=int16([]); soQ=int16([]); stepLog=int32([]); errorLog=int16([]);
for k=1:numel(xi)
    if ~costasLocked(k)
        phase=uint32(0); step=p.nominalStep; halfToggle=false; warmup=uint8(0);
        earlyI=0; earlyQ=0; middleI=0; middleQ=0; previousError=0;
        delayI(:)=0; delayQ(:)=0; pending=false; pendingMu=uint16(0);
        pipeValid(:)=false; pipeI(:)=0; pipeQ(:)=0;
        continue;
    end
    oldStep=step;
    if pipeValid(1)
        interpI=pipeI(1); interpQ=pipeQ(1);
        err=int64(middleI)*(int64(interpI)-int64(earlyI))+ ...
            int64(middleQ)*(int64(interpQ)-int64(earlyQ));
        magnitude=max([abs(int64(earlyI))+abs(int64(earlyQ)), ...
            abs(int64(middleI))+abs(int64(middleQ)), ...
            abs(int64(interpI))+abs(int64(interpQ))]);
        oldWarmup=warmup; earlyI=middleI; earlyQ=middleQ;
        middleI=interpI; middleQ=interpQ;
        if warmup~=7, warmup=warmup+1; end
        if ~halfToggle && oldWarmup>=2
            exponent=nextpow2(max(double(magnitude),p.magnitudeFloor));
            % The Gardner product can reach roughly twice magnitude^2.
            % One guard bit prevents high-amplitude board captures from
            % saturating the Q1.15 detector.
            shift=2*exponent-14;
            errorQ15=sat16(bitshift(err,-shift));
            prop=int64(p.gardnerKp)*(int64(errorQ15)-int64(previousError));
            integ=int64(p.gardnerKi)*int64(errorQ15);
            candidate=int64(step)+bitshift(prop+integ,-15);
            candidate=min(max(candidate,int64(p.minStep)),int64(p.maxStep));
            step=int32(candidate); previousError=errorQ15;
            soI(end+1,1)=interpI; soQ(end+1,1)=interpQ; stepLog(end+1,1)=step; errorLog(end+1,1)=errorQ15; %#ok<AGROW>
        end
        halfToggle=~halfToggle;
    end
    pipeValid(1:3)=pipeValid(2:4); pipeValid(4)=false;
    pipeI(1:3)=pipeI(2:4); pipeQ(1:3)=pipeQ(2:4);
    if pending
        pipeI(4)=farrowQ15(xi(k),delayI(1),delayI(2),delayI(3),pendingMu);
        pipeQ(4)=farrowQ15(xq(k),delayQ(1),delayQ(2),delayQ(3),pendingMu);
        pipeValid(4)=true;
    end
    phaseSum=uint64(phase)+uint64(uint32(oldStep));
    if phaseSum>=uint64(4294967296)
        remaining=uint64(4294967296)-uint64(phase);
        pendingMu=uint16(min(uint64(32768),bitshift(remaining*uint64(6),-17)));
        pending=true;
    else, pending=false; end
    phase=uint32(mod(phaseSum,uint64(4294967296)));
    delayI(3)=delayI(2); delayI(2)=delayI(1); delayI(1)=xi(k);
    delayQ(3)=delayQ(2); delayQ(2)=delayQ(1); delayQ(1)=xq(k);
end
end

function y=farrowQ15(x0,x1,x2,x3,mu)
x0=int64(x0); x1=int64(x1); x2=int64(x2); x3=int64(x3); mu=int64(mu);
f1=bitshift(x0,-1)-bitshift(x1,-1)-bitshift(x2,-1)+bitshift(x3,-1);
f2=x1+bitshift(x1,-1)-bitshift(x0,-1)-bitshift(x2,-1)-bitshift(x3,-1);
y=sat16(bitshift(bitshift(f1*mu,-15)*mu,-15)+bitshift(f2*mu,-15)+x2);
end

function values=fixedDiffDecode(si,sq)
pi=false; pq=false; values=zeros(numel(si),1);
for k=1:numel(si)
    di=si(k)>=0; dq=sq(k)>=0;
    values(k)=double(xor(di,pi))+2*double(xor(dq,pq)); pi=di; pq=dq;
end
end

function swapped=swapDibitChannels(values)
values=uint8(values(:));
swapped=double(bitshift(bitand(values,1),1)+bitshift(bitand(values,2),-1));
end

function varargout=bestCycleWer(actual,cycle)
if isempty(actual), best=NaN; offset=0;
else
    best=Inf; offset=0;
    for q=0:numel(cycle)-1
        expected=cycle(mod((0:numel(actual)-1)+q,numel(cycle))+1).';
        candidate=mean(actual(:)~=expected(:));
        if candidate<best, best=candidate; offset=q; end
    end
end
varargout{1}=best; if nargout>1, varargout{2}=offset; end
end

function y=sinLutQ15(index)
quarter=int16([0 804 1608 2410 3212 4011 4808 5602 6393 7179 7962 8739 9512 10278 11039 11793 12539 13279 14010 14732 15446 16151 16846 17530 18204 18868 19519 20159 20787 21403 22005 22594 23170 23731 24279 24811 25329 25832 26319 26790 27245 27683 28105 28510 28898 29268 29621 29956 30273 30571 30852 31113 31356 31580 31785 31971 32137 32285 32412 32521 32609 32678 32728 32757 32767]);
quadrant=floor(index/64); offset=mod(index,64);
switch quadrant
 case 0, y=quarter(offset+1); case 1, y=quarter(65-offset);
 case 2, y=-quarter(offset+1); otherwise, y=-quarter(65-offset); end
end

function y=sat16(x)
x=int64(x); x(x>32767)=32767; x(x< -32768)=-32768; y=int16(x);
end
function x=wrapI32(v)
u=mod(double(v),2^32); if u>=2^31, u=u-2^32; end; x=int32(u);
end
function x=wrapU32(v), x=uint32(mod(double(v),2^32)); end

function writeFixedReport(path,reports,p)
fid=fopen(path,'w'); assert(fid>=0); cleaner=onCleanup(@() fclose(fid));
fprintf(fid,'costas_limit_word=%d\ncostas_limit_hz=%.6f\n',p.costasLimit,double(p.costasLimit)*p.fs/2^32);
fprintf(fid,'timing_step_min=%d timing_step_nominal=%d timing_step_max=%d\n\n',p.minStep,p.nominalStep,p.maxStep);
for k=1:numel(reports)
 r=reports(k); fprintf(fid,'%s\n',r.name);
 fprintf(fid,' decoded=%d direct_wer=%.12g swapped_wer=%.12g resolved_wer=%.12g\n',r.decodedCount,r.directWer,r.swappedWer,r.resolvedWer);
 fprintf(fid,' tail256_resolved_wer=%.12g tail_frequency_hz=%.12g tail_half_period=%.12g recoveries=%d\n\n',r.tailResolvedWer,r.tailFrequencyHz,r.tailHalfPeriod,r.recoveryEvents);
end
end
