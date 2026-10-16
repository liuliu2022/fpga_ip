clear; clc;

thisDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);
captureRoot = fullfile(repoRoot,'testdata','ila_board_captures');
rawDir = fullfile(captureRoot,'raw');
stimulusDir = fullfile(captureRoot,'stimulus');
if ~exist(stimulusDir,'dir'), mkdir(stimulusDir); end

captures = {'rx','iladata'};
for captureIndex = 1:numel(captures)
    name = captures{captureIndex};
    inputPath = fullfile(rawDir,[name '.csv']);
    outputPath = fullfile(stimulusDir,[name '_decim_iq_s16.txt']);
    [sampleI,sampleQ] = readDecimatorColumns(inputPath);
    assert(numel(sampleI)==1024,'Expected 1024 ILA samples in %s',inputPath);
    assert(all(sampleI>=-32768 & sampleI<=32767));
    assert(all(sampleQ>=-32768 & sampleQ<=32767));

    fid = fopen(outputPath,'w'); assert(fid>=0,'Cannot create %s',outputPath);
    cleaner = onCleanup(@() fclose(fid));
    for sampleIndex = 1:numel(sampleI)
        fprintf(fid,'%d %d\n',sampleI(sampleIndex),sampleQ(sampleIndex));
    end
    clear cleaner
    fprintf('Wrote %d complex samples to %s\n',numel(sampleI),outputPath);
end
function [sampleI,sampleQ] = readDecimatorColumns(path)
fid=fopen(path,'r'); assert(fid>=0,'Cannot open %s',path);
cleaner=onCleanup(@() fclose(fid));
header=strsplit(fgetl(fid),',');
fgetl(fid); % Vivado radix row
columnCount=numel(header);
format=repmat('%s',1,columnCount);
cells=textscan(fid,format,'Delimiter',',','CollectOutput',true,'EndOfLine','\n');
rows=cells{1};

iColumn=find(contains(header,'gowinsdr_rx_chain_0_decim_i[15:0]'),1);
qColumn=find(contains(header,'gowinsdr_rx_chain_0_decim_q[15:0]'),1);
assert(~isempty(iColumn) && ~isempty(qColumn),'Decimator I/Q columns not found');
sampleI=str2double(rows(:,iColumn));
sampleQ=str2double(rows(:,qColumn));
assert(all(isfinite(sampleI)) && all(isfinite(sampleQ)),'Invalid signed samples');
end
