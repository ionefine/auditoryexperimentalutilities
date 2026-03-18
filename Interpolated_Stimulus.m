% DemoStimulus.m

stim = struct();
stim.Fs_i = 100;   % temporal sampling rate for spectrograph

% single chord with harmonics F0, 2*F0, 3*F0,...
% default parameters:
stim.F0 = 256;    %  fundamental frequency (f0 = 256, which is missing)
stim.ntones = 6;   %  number of harmonics (including F0)
stim.amp =[1 1 1 1 1 1 ];    %  volume of each tone
stim.dur = .75;    %  chord duration  (.5 sec)
stim.rampDur= .1;%  cosine ramp duration (.1 sec)
stim.t0 = 0;      %   starting time (0 sec)
stim.condition = 'HI';
stim.jitterAmount = .5; % maximum frequency shift (mulitiplied by freq, 1 would be a full octave)

stim.type = 'inharmonic_transition';
d = stimulus.defaults;
stim = stimulus.addFields(stim,d);

baseFreq = stim.F0*(1:stim.ntones); % Base harmonic frequencies
randOffsets = 2*(rand(size(baseFreq))-.5) % Fixed random offsets (VERY IMPORTANT: only generate once)

t = 0:1/stim.Fs:stim.dur-1/stim.Fs; % Time vector
dt = t(2)-t(1);
nT = numel(t);
nT_noramp = numel(t)-ceil((2*stim.rampDur)/dt);

% define order of frequency shift [1,2] means H -> I, [1,1] means H -> H
switch upper(stim.condition)
    case 'HH'
        id = [1,1];
    case 'II'
        id = [2,2];
    case 'IH'
        id = [2,1];
    case 'HI'
        id = [1,2];
    otherwise
        error('condition must be HH, II, IH, or HI')
end

y = zeros(1,nT);     % Build waveform

yramp = ones(1,ceil(stim.rampDur./dt));

for k = 1:stim.ntones
    % Option 1 - offsets are scaled by frequency, so maximum is frequency
    % doubling or halving:
    %  f = [baseFreq(k),baseFreq(k)*2^(randOffsets(k)*stim.jitterAmount)];

    % Option 2 - offsets are not scaled, so that maximum is going up or down F0. Frequencies will not cross
    f = [baseFreq(k),baseFreq(k)+ stim.F0*randOffsets(k)*stim.jitterAmount];

    f_t = [f(id(1))*yramp, linspace(f(id(1)),f(id(2)),nT_noramp),f(id(2))*yramp];

    % integrate frequency to get phase
    phase = 2*pi * cumsum(f_t) * dt;

    % generate tone
    y = y+ sin(phase);
end
y = stimulus.raisedCosineWindow(y, stim.Fs, stim.rampDur); % Apply raised cosine window ONCE, avoiding click
y = y ./ max(abs(y));  % Normalize
stim.y = y(:)';
stim = stimulus.add_off_period(stim); % Add off period if requested
stim = stimulus.spectrogram(stim);

figure(7)
tid = 1;
clf
t = (1:length(stim.y))/stim.Fs;


ylim = [50,4000];
figure(1)
clf
imagesc(t,stim.fft.freq,stim.fft.amp);
set(gca,'YLim',ylim)
set(gca,'YDir','normal')
%set(gca,'YLim',log([50,8000]));
colormap(bone(256).^.5)
set(gca,'YTick',0:500:8000)
xlabel('Time (s)')
ylabel('Frequency (Hz)')


hold on
h=plot([0,0],ylim,'r-','LineWidth',2);
% drawnow


%%
tic
y = stim.y/max(abs(stim.y));
sound(stim.y, stim.Fs);

return
dur = length(stim.y)/stim.Fs;
dt = .2;
while toc<dur+dt
    x = toc-dt;
    set(h,'XData',[x,x]);
    drawnow
end

delete(h)
%logy2raw(2)