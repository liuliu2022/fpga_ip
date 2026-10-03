function results = analyze_costas_gowin()
%ANALYZE_COSTAS_GOWIN Evaluate the GoWinSDR MATLAB loop equations at RFSoC rates.
% This is an analysis model only. It does not alter the active RTL.

chainDir=fileparts(fileparts(mfilename('fullpath')));
profiles={'cfo_only','combined'};
bnValues=[0.002 0.005 0.010 0.020];
zeta=0.707; fs=61.44e6; sps=12;
results=struct([]); resultIndex=0;

for profileIndex=1:numel(profiles)
    profile=profiles{profileIndex};
    profileDir=fullfile(chainDir,'scenario_results',profile);
    rrc=load(fullfile(profileDir,'expected_rrc.txt'));
    txBits=load(fullfile(profileDir,'tx_bits.txt'));
    x=complex(rrc(:,1),rrc(:,2));

    fig=figure('Visible','off','Color','w','Position',[100 100 1400 800]);
    for gainIndex=1:numel(bnValues)
        bnTs=bnValues(gainIndex);
        denominator=1+2*zeta*bnTs+bnTs^2;
        kp=4*zeta*bnTs/denominator;
        ki=4*bnTs^2/denominator;
        [y,frequencyHz,errorLog]=normalized_costas(x,fs,kp,ki);
        [ber,phase,lag]=sample_and_ber(y,txBits,sps);
        tail=max(1,numel(frequencyHz)-255):numel(frequencyHz);

        resultIndex=resultIndex+1;
        results(resultIndex).profile=profile; %#ok<AGROW>
        results(resultIndex).bnTs=bnTs;
        results(resultIndex).kp=kp;
        results(resultIndex).ki=ki;
        results(resultIndex).ber=ber;
        results(resultIndex).best_phase=phase;
        results(resultIndex).lag=lag;
        results(resultIndex).tail_frequency_hz=mean(frequencyHz(tail));

        subplot(2,numel(bnValues),gainIndex);
        plot(real(y),imag(y),'.','MarkerSize',2);axis equal;grid on;
        title(sprintf('BnTs %.3f, BER %.4g',bnTs,ber));xlabel('I');ylabel('Q');
        subplot(2,numel(bnValues),numel(bnValues)+gainIndex);
        plot(frequencyHz);grid on;hold on;yline(25e3,'--r');
        xlabel('61.44-MSPS sample');ylabel('Hz');
        title(sprintf('tail %.1f Hz, e_{rms} %.3g',mean(frequencyHz(tail)),rms(errorLog(tail))));
    end
    sgtitle(sprintf('GoWinSDR normalized PI equations at RFSoC rates: %s',strrep(profile,'_',' ')));
    saveas(fig,fullfile(profileDir,'costas_gowin_gain_sweep.png'));close(fig);
end

fid=fopen(fullfile(chainDir,'scenario_results','COSTAS_GOWIN_SWEEP.txt'),'w');assert(fid>=0);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'profile BnTs Kp Ki BER tail_frequency_hz\n');
for k=1:numel(results)
    fprintf(fid,'%s %.6g %.12g %.12g %.12g %.12g\n',results(k).profile, ...
        results(k).bnTs,results(k).kp,results(k).ki,results(k).ber,results(k).tail_frequency_hz);
end
save(fullfile(chainDir,'scenario_results','costas_gowin_sweep.mat'),'results');
end

function [y,frequencyHz,errorLog]=normalized_costas(x,fs,kp,ki)
y=complex(zeros(size(x)));frequencyHz=zeros(size(x));errorLog=zeros(size(x));
phase=0;integrator=0;
for n=1:numel(x)
    y(n)=x(n)*exp(-1j*phase);
    i=real(y(n));q=imag(y(n));
    denominator=max(abs(i)+abs(q),1);
    error=(sign(i)*q-sign(q)*i)/denominator;
    integrator=integrator+ki*error;
    phase=phase+integrator+kp*error;
    phase=mod(phase+pi,2*pi)-pi;
    frequencyHz(n)=integrator*fs/(2*pi);
    errorLog(n)=error;
end
end

function [bestBer,bestPhase,bestLag]=sample_and_ber(y,txBits,sps)
bestBer=Inf;bestPhase=1;bestLag=0;
for phase=1:sps
    symbols=y(phase:sps:end);
    decisions=[real(symbols)>=0 imag(symbols)>=0];
    bits=zeros(size(decisions));previous=false(1,2);
    for k=1:size(decisions,1)
        bits(k,:)=xor(decisions(k,:),previous);previous=decisions(k,:);
    end
    [ber,lag]=best_pair_ber_local(txBits,bits,160);
    if ber<bestBer,bestBer=ber;bestPhase=phase;bestLag=lag;end
end
end

function [ber,bestLag]=best_pair_ber_local(tx,rx,maxLag)
ber=Inf;bestLag=0;
for lag=-maxLag:maxLag
    txStart=max(1,1+lag);rxStart=max(1,1-lag);
    count=min(size(tx,1)-txStart+1,size(rx,1)-rxStart+1);
    if count<32,continue;end
    candidate=sum(sum(tx(txStart:txStart+count-1,:)~=rx(rxStart:rxStart+count-1,:)))/(2*count);
    if candidate<ber,ber=candidate;bestLag=lag;end
end
end
