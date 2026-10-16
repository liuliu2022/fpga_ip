% Validate the proposed Costas signal-presence gate against real ILA data.
% This is intentionally independent of the captured locked flag: the current
% RTL can declare lock on noise because a small phase error is not proof that
% a carrier exists.

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
qpskDir = fileparts(thisDir);
rawDir = fullfile(qpskDir,'testdata','ila_distance_captures','raw');
resultDir = fullfile(qpskDir,'scenario_results','low_amplitude_gate');
if ~exist(resultDir,'dir'), mkdir(resultDir); end

cfg.onMagnitude = 16;       % averaged |I|+|Q|, signed 16-bit codes
cfg.offMagnitude = 10;      % hysteresis prevents chatter near the threshold
cfg.onSamples = 64;
cfg.offSamples = 128;
cfg.averageShift = 5;       % 32-sample one-pole average

files = {'收发天线挨着.csv','收发天线稍远.csv','收发天线远.csv', ...
         '收发数据.csv','接收信号微弱.csv'};
reports = repmat(struct(),numel(files),1);

for fileIndex = 1:numel(files)
    path = fullfile(rawDir,files{fileIndex});
    [sampleI,sampleQ] = readCostasColumns(path);

    % Repeat only for detector-state validation. No BER claim is made across
    % the artificial CSV boundary.
    sampleI = repmat(sampleI,4,1);
    sampleQ = repmat(sampleQ,4,1);
    magnitude = abs(sampleI)+abs(sampleQ);
    [present,averageMagnitude] = fixedSignalGate(magnitude,cfg);

    reports(fileIndex).file = files{fileIndex};
    reports(fileIndex).meanMagnitude = mean(magnitude);
    reports(fileIndex).rmsMagnitude = sqrt(mean(sampleI.^2+sampleQ.^2));
    reports(fileIndex).presentPercent = 100*mean(present);
    firstPresent = find(present,1);
    if isempty(firstPresent), firstPresent = 0; end
    reports(fileIndex).firstPresentSample = firstPresent;
    reports(fileIndex).dropEvents = nnz(diff([false;present])<0);
    reports(fileIndex).tailAverageMagnitude = mean(averageMagnitude(end-255:end));

    fprintf('%-24s meanL1=%7.3f rms=%7.3f present=%6.2f%% first=%4d drops=%d tailAvg=%6.2f\n', ...
        files{fileIndex},reports(fileIndex).meanMagnitude, ...
        reports(fileIndex).rmsMagnitude,reports(fileIndex).presentPercent, ...
        reports(fileIndex).firstPresentSample,reports(fileIndex).dropEvents, ...
        reports(fileIndex).tailAverageMagnitude);
end

save(fullfile(resultDir,'low_amplitude_gate.mat'),'reports','cfg');
fid=fopen(fullfile(resultDir,'low_amplitude_gate.txt'),'w');assert(fid>=0);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'on_magnitude=%d\noff_magnitude=%d\non_samples=%d\noff_samples=%d\naverage_shift=%d\n\n', ...
    cfg.onMagnitude,cfg.offMagnitude,cfg.onSamples,cfg.offSamples,cfg.averageShift);
for k=1:numel(reports)
    r=reports(k);
    fprintf(fid,'%s mean_l1=%.6f rms=%.6f present_pct=%.6f first=%d drops=%d tail_avg=%.6f\n', ...
        r.file,r.meanMagnitude,r.rmsMagnitude,r.presentPercent, ...
        r.firstPresentSample,r.dropEvents,r.tailAverageMagnitude);
end

function [sampleI,sampleQ]=readCostasColumns(path)
fid=fopen(path,'r');assert(fid>=0,'Cannot open %s',path);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
header=strsplit(fgetl(fid),',');
fgetl(fid); % Vivado radix row
format=repmat('%s',1,numel(header));
cells=textscan(fid,format,'Delimiter',',','CollectOutput',true,'EndOfLine','\n');
rows=cells{1};
iColumn=find(contains(header,'gowinsdr_rx_chain_0_costas_i[15:0]'),1);
qColumn=find(contains(header,'gowinsdr_rx_chain_0_costas_q[15:0]'),1);
assert(~isempty(iColumn) && ~isempty(qColumn),'Costas columns missing in %s',path);
sampleI=str2double(rows(:,iColumn));sampleQ=str2double(rows(:,qColumn));
valid=isfinite(sampleI)&isfinite(sampleQ);
sampleI=sampleI(valid);sampleQ=sampleQ(valid);
end

function [present,averageMagnitude]=fixedSignalGate(magnitude,cfg)
accumulator=int64(0); onCount=0; offCount=0; state=false;
present=false(size(magnitude)); averageMagnitude=zeros(size(magnitude));
onThreshold=int64(cfg.onMagnitude)*bitshift(int64(1),cfg.averageShift);
offThreshold=int64(cfg.offMagnitude)*bitshift(int64(1),cfg.averageShift);
for k=1:numel(magnitude)
    accumulator=accumulator-bitshift(accumulator,-cfg.averageShift)+int64(magnitude(k));
    averageMagnitude(k)=double(accumulator)/2^cfg.averageShift;
    if ~state
        offCount=0;
        if accumulator>=onThreshold, onCount=onCount+1; else, onCount=0; end
        if onCount>=cfg.onSamples, state=true; onCount=0; end
    else
        onCount=0;
        if accumulator<=offThreshold, offCount=offCount+1; else, offCount=0; end
        if offCount>=cfg.offSamples, state=false; offCount=0; end
    end
    present(k)=state;
end
end
