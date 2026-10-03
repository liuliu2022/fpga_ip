clear; clc;

thisDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);
vectorDir = fullfile(repoRoot,'vectors');
if ~exist(vectorDir,'dir'), mkdir(vectorDir); end

nSymbols = 256;
sps = 48;
h = int64(load(fullfile(repoRoot,'rtl','tx','tx_rrc_coeffs_q16.txt')));
assert(numel(h)==481);

bits = zeros(nSymbols,2);
lfsr = uint16(hex2dec('1ACE'));
for k=1:nSymbols
    bits(k,1)=bitget(lfsr,1);
    bits(k,2)=bitget(lfsr,2);
    feedback=bitget(lfsr,1);
    lfsr=bitshift(lfsr,-1);
    if feedback, lfsr=bitxor(lfsr,uint16(hex2dec('B400'))); end
end

decisions = zeros(size(bits));
previous = [0 0];
for k=1:nSymbols
    decisions(k,:)=xor(logical(bits(k,:)),logical(previous));
    previous=decisions(k,:);
end

impulseI=zeros(nSymbols*sps,1,'int64');
impulseQ=zeros(nSymbols*sps,1,'int64');
impulseI(1:sps:end)=int64(2*decisions(:,1)-1);
impulseQ(1:sps:end)=int64(2*decisions(:,2)-1);
waveI=int64(filter(double(h),1,double(impulseI)));
waveQ=int64(filter(double(h),1,double(impulseQ)));
waveI=max(min(waveI,32767),-32768);
waveQ=max(min(waveQ,32767),-32768);

inputValues=bits(:,1)+2*bits(:,2);
decisionValues=decisions(:,1)+2*decisions(:,2);
writeRows(fullfile(vectorDir,'tx_input_data.txt'),inputValues);
writeRows(fullfile(vectorDir,'tx_encoded_data.txt'),decisionValues);

packets=numel(waveI)/4;
expected=zeros(packets,8);
for lane=0:3
    expected(:,2*lane+1)=double(waveI(lane+1:4:end));
    expected(:,2*lane+2)=double(waveQ(lane+1:4:end));
end
writeRows(fullfile(vectorDir,'tx_expected_iq.txt'),expected);

fid=fopen(fullfile(vectorDir,'manifest.txt'),'w'); assert(fid>=0);
fprintf(fid,'symbols=%d\n',nSymbols);
fprintf(fid,'symbol_rate_hz=5120000\n');
fprintf(fid,'pl_clock_hz=61440000\n');
fprintf(fid,'parallel_samples=4\n');
fprintf(fid,'sample_rate_hz=245760000\n');
fprintf(fid,'samples_per_symbol=%d\n',sps);
fprintf(fid,'rrc_beta=0.35\nrrc_span_symbols=10\nrrc_taps=%d\n',numel(h));
fclose(fid);

fprintf('Generated %d symbols and %d four-sample packets in %s\n', ...
    nSymbols,packets,vectorDir);

function writeRows(path,m)
fid=fopen(path,'w'); assert(fid>=0); c=onCleanup(@() fclose(fid)); %#ok<NASGU>
for r=1:size(m,1)
    fprintf(fid,'%d',m(r,1));
    for col=2:size(m,2), fprintf(fid,' %d',m(r,col)); end
    fprintf(fid,'\n');
end
end
