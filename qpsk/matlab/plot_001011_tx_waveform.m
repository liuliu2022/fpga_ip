clear; clc;

% Visualize the exact mapping and Q1.16 RRC coefficients used by the RTL TX.
% data_in is written in the normal Verilog order data_in[1:0].
thisDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(thisDir);
coefficientPath = fullfile(repoRoot,'rtl','tx','tx_rrc_coeffs_q16.txt');
outputPath = fullfile(thisDir,'qpsk_001011_tx_waveform.png');

inputWords = uint8([0; 1; 2; 3]);       % 00, 01, 10, 11 on data_in[1:0]
inputLabels = {'00'; '01'; '10'; '11'};

% Match tx_qpsk_diff_encode.v exactly:
% encoded_i = previous_i XOR data_in[0]
% encoded_q = previous_q XOR data_in[1]
dataI = logical(bitget(inputWords,1));
dataQ = logical(bitget(inputWords,2));
encodedI = false(size(dataI));
encodedQ = false(size(dataQ));
previousI = false;
previousQ = false;
for k = 1:numel(inputWords)
    encodedI(k) = xor(previousI,dataI(k));
    encodedQ(k) = xor(previousQ,dataQ(k));
    previousI = encodedI(k);
    previousQ = encodedQ(k);
end

symbolI = 2*double(encodedI)-1;
symbolQ = 2*double(encodedQ)-1;

% Match tx_rrc_interp48x4.v and generate_tx_vectors.m exactly.
sps = 48;
symbolRate = 5.12e6;
sampleRate = symbolRate*sps;
h = int64(load(coefficientPath));
assert(numel(h)==481,'Expected the RTL 481-tap TX RRC coefficient file.');

numberOfSamples = (numel(inputWords)-1)*sps + numel(h);
impulseI = zeros(numberOfSamples,1,'int64');
impulseQ = zeros(numberOfSamples,1,'int64');
symbolInputIndex = 1 + (0:numel(inputWords)-1)*sps;
impulseI(symbolInputIndex) = int64(symbolI);
impulseQ(symbolInputIndex) = int64(symbolQ);

waveI = int64(round(filter(double(h),1,double(impulseI))));
waveQ = int64(round(filter(double(h),1,double(impulseQ))));
waveI = max(min(waveI,int64(32767)),int64(-32768));
waveQ = max(min(waveQ,int64(32767)),int64(-32768));

groupDelay = (numel(h)-1)/2;
timeSymbols = ((0:numberOfSamples-1).'-groupDelay)/sps;
timeMicroseconds = timeSymbols/symbolRate*1e6;
symbolCenterIndex = groupDelay + 1 + (0:numel(inputWords)-1)*sps;

fprintf('data_in[1:0]  encoded(I,Q)  constellation(I,Q)\n');
for k = 1:numel(inputWords)
    fprintf('     %s           %d%d             (%+d,%+d)\n', ...
        inputLabels{k},encodedI(k),encodedQ(k),symbolI(k),symbolQ(k));
end
fprintf('RRC: beta=0.35, span=10 symbols, sps=%d, Fs=%.2f MSPS\n', ...
    sps,sampleRate/1e6);
fprintf('Saved figure: %s\n',outputPath);

f = figure('Visible','off','Color','w','Position',[80 60 1500 1050]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');

nexttile;
stairs(0:3,double(inputWords),'LineWidth',1.5,'Color',[0.15 0.15 0.15]);
hold on;
plot(0:3,double(inputWords),'o','MarkerSize',7,'LineWidth',1.3, ...
    'Color',[0.15 0.15 0.15],'MarkerFaceColor','w');
for k = 1:4
    text(k-1,double(inputWords(k))+0.22,inputLabels{k}, ...
        'HorizontalAlignment','center','FontWeight','bold');
end
xlim([-0.35 3.35]); ylim([-0.5 3.7]); yticks(0:3); grid on;
ylabel('word value');
title('Input dibits on data\_in[1:0]: 00, 01, 10, 11');

nexttile;
stairs(0:3,symbolI,'-o','LineWidth',1.5,'MarkerSize',6); hold on;
stairs(0:3,symbolQ,'-s','LineWidth',1.5,'MarkerSize',6);
for k = 0:3, xline(k,':','Color',[0.65 0.65 0.65]); end
xlim([-0.35 3.35]); ylim([-1.45 1.45]); yticks([-1 0 1]); grid on;
ylabel('symbol sign');
legend('Differential I','Differential Q','Location','eastoutside');
title('Differentially encoded constellation components');

nexttile([2 1]);
plot(timeSymbols,double(waveI),'LineWidth',1.25); hold on;
plot(timeSymbols,double(waveQ),'LineWidth',1.25);
plot(0:3,double(waveI(symbolCenterIndex)),'o','MarkerSize',7,'LineWidth',1.3);
plot(0:3,double(waveQ(symbolCenterIndex)),'s','MarkerSize',7,'LineWidth',1.3);
for k = 0:3
    xline(k,':','Color',[0.55 0.55 0.55]);
    text(k,31500,inputLabels{k+1},'HorizontalAlignment','center','FontWeight','bold');
end
xlim([-5 8]); ylim([-34000 34000]); grid on;
xlabel('Time relative to RRC group delay (symbol periods)');
ylabel('signed 16-bit code');
legend('Shaped I(t)','Shaped Q(t)','I at symbol center','Q at symbol center', ...
    'Location','eastoutside');
title(sprintf('RTL-equivalent TX RRC waveform: 481 taps, 48 samples/symbol, %.2f MSPS', ...
    sampleRate/1e6));

sgtitle('QPSK sequence 00 01 10 11: differential encoding and pulse shaping');
print(f,outputPath,'-dpng','-r180');
close(f);
