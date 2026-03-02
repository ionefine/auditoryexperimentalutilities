function results = LoudnessMatch_InterleavedStaircases(targetFreqsHz, varargin)
% LOUDNESSMATCH_INTERLEAVEDSTAIRCASES
% Interleaved 1-up/1-down staircases to match loudness of each target frequency
% to a 1000 Hz reference tone.
%
% Key properties:
%   - Input is a LIST of target frequencies (vector).
%   - Separate staircase state per frequency.
%   - Trial-by-trial, the presented target frequency varies (random interleaving).
%   - SAME burstseq for reference and target within a trial, but burstseq varies across trials.
%   - Linear amplitude staircase (NOT dB), with bounded amplitudes.
%   - Step size is halved after TWO reversals (per staircase), repeatable, with a floor.
%   - History logs BOTH amp_present and amp_updated (post-staircase update) explicitly.
%     (No backward-compat "hist.targetAmp" field.)
%
% RESPONSE:
%   Press '1' if interval 1 louder, '2' if interval 2 louder. ESC aborts.
%
% DEPENDENCY:
%   taper.m

%% ---------------- Parse inputs ----------------
p = inputParser;
p.addRequired('targetFreqsHz', @(x)isnumeric(x)&&isvector(x)&&all(x>0));

p.addParameter('RefFreq', 1000, @(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('Fs', 44100, @(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('BlockLength', 2.0, @(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('NBursts', 8, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
p.addParameter('PulseDur', [0.05 0.2], @(x)isnumeric(x)&&numel(x)==2);
p.addParameter('OffDur', 0.05, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
p.addParameter('TaperFrac', 0.2, @(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<=1);

p.addParameter('RefAmp', 0.25, @(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('StartAmp', 0.5, @(x)isnumeric(x)&&isscalar(x)&&x>0);
p.addParameter('StepAmp', 0.1, @(x)isnumeric(x)&&isscalar(x)&&x>0);

% Minimum step size (linear amplitude)
% If half StepAmp, then it'll only drop the step size once (after two reversals)
p.addParameter('MinStepAmp', 0.05, @(x)isnumeric(x)&&isscalar(x)&&x>0);

% Bounds (linear amplitude)
p.addParameter('AmpMin', 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
p.addParameter('AmpMax', 0.95, @(x)isnumeric(x)&&isscalar(x)&&x>0);

% Stopping
p.addParameter('MaxTrials', 500, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
p.addParameter('MaxReversalsPerFreq', 10, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
p.addParameter('MinReversalsToFinish', 6, @(x)isnumeric(x)&&isscalar(x)&&x>=1); % per freq (unused as hard stop here)

% Interleaving policy
p.addParameter('PickPolicy', 'random_active', @(s)ischar(s)||isstring(s));
% 'random_active' = choose randomly among staircases not yet finished
% 'round_robin'   = cycle through active staircases

p.addParameter('ISI', 0.25, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
p.addParameter('Verbose', true, @(x)islogical(x)&&isscalar(x));
p.addParameter('SaveFile', '', @(x)ischar(x)||isstring(x));

p.parse(targetFreqsHz, varargin{:});
opt = p.Results;

targetFreqsHz = targetFreqsHz(:)';
nF = numel(targetFreqsHz);

setup.n_bursts   = opt.NBursts;
setup.pulse_dur  = opt.PulseDur;
setup.off_dur    = opt.OffDur;

fs = opt.Fs;
PEAK_MAX = 0.95;

AMP_MIN = opt.AmpMin;
AMP_MAX = opt.AmpMax;

refFreq = opt.RefFreq;
refAmp  = opt.RefAmp;

%% ---------------- Initialize per-frequency staircases ----------------
S = repmat(struct(), 1, nF);
for i = 1:nF
    S(i).freqHz = targetFreqsHz(i);

    S(i).targetAmp = opt.StartAmp;
    S(i).stepAmp   = opt.StepAmp;

    S(i).nRev      = 0;
    S(i).lastDir   = 0;

    % reversals since last halving (per frequency)
    S(i).revSinceHalve = 0;

    S(i).finished  = false;

    % History for this frequency:
    h = struct();
    h.amp_present   = [];
    h.amp_updated   = [];
    h.step_present  = [];
    h.step_updated  = [];
    h.targetFirst   = [];
    h.choice        = [];
    h.targetLouder  = [];
    h.dir           = [];
    h.reversal      = [];
    h.amp_dBeq      = []; % analysis only, computed from PRESENTED amp
    S(i).hist = h;
end

% Global trial log (presented vs updated)
G = struct();
G.freqIndex     = [];
G.freqHz        = [];
G.amp_present   = [];
G.amp_updated   = [];
G.step_present  = [];
G.step_updated  = [];
G.targetFirst   = [];
G.choice        = [];
G.targetLouder  = [];
G.dir           = [];
G.reversal      = [];

if opt.Verbose
    fprintf('\n--- Interleaved loudness match ---\n');
    fprintf('Reference: %.1f Hz @ refAmp=%.6f (linear)\n', refFreq, refAmp);
    fprintf('Targets (%d): %s\n', nF, mat2str(targetFreqsHz));
    fprintf('Bounds: [%.6f, %.6f]\n', AMP_MIN, AMP_MAX);
    fprintf('Step: start=%.6f, min=%.6f; halve after 2 reversals (per freq)\n', opt.StepAmp, opt.MinStepAmp);
    fprintf('Stop per freq: %d reversals, or global maxTrials=%d\n', opt.MaxReversalsPerFreq, opt.MaxTrials);
    fprintf('Keys: 1=interval1 louder, 2=interval2 louder, ESC=abort\n\n');
end

%% ---------------- Interleaved trial loop ----------------
trial = 0;
rr_ptr = 0;

while trial < opt.MaxTrials && ~all([S.finished])
    trial = trial + 1;

    % Choose which staircase to run this trial:
    activeIdx = find(~[S.finished]);
    if isempty(activeIdx), break; end

    switch string(opt.PickPolicy)
        case "round_robin"
            rr_ptr = rr_ptr + 1;
            pick = activeIdx(mod(rr_ptr-1, numel(activeIdx)) + 1);
        otherwise % "random_active"
            pick = activeIdx(randi(numel(activeIdx)));
    end

    fTarget = S(pick).freqHz;

    % Values PRESENTED on this trial
    amp_present  = S(pick).targetAmp;
    step_present = S(pick).stepAmp;

    % Randomize which interval is target:
    targetFirst = rand < 0.5;

    % Same burstseq for ref & target within a trial:
    burstseq = makeBurstSeq(setup.n_bursts);

    % Build blocks:
    refBlock  = makeToneBlock(refFreq, refAmp,     setup, opt.BlockLength, fs, opt.TaperFrac, burstseq);
    targBlock = makeToneBlock(fTarget, amp_present, setup, opt.BlockLength, fs, opt.TaperFrac, burstseq);

    % Peak safety (audio waveform only; does NOT change amp_present variable):
    refBlock  = enforcePeak(refBlock,  PEAK_MAX);
    targBlock = enforcePeak(targBlock, PEAK_MAX);

    % Assemble intervals:
    if targetFirst
        A = [targBlock(:), targBlock(:)];
        B = [refBlock(:),  refBlock(:)];
    else
        A = [refBlock(:),  refBlock(:)];
        B = [targBlock(:), targBlock(:)];
    end

    % Play A then B:
    sound(A, fs);
    pause(opt.BlockLength + opt.ISI);
    sound(B, fs);
    pause(opt.BlockLength + 0.05);

    choice = getChoice12();
    if choice == 0
        if opt.Verbose, disp('Aborted.'); end
        break;
    end

    % Was TARGET judged louder?
    if targetFirst
        targetWasChosenLouder = (choice == 1);
    else
        targetWasChosenLouder = (choice == 2);
    end

    % 1-up/1-down direction:
    if targetWasChosenLouder
        dir = -1;
    else
        dir = +1;
    end

    % Reversal detection (per staircase):
    isRev = false;
    if S(pick).lastDir ~= 0 && dir ~= S(pick).lastDir
        S(pick).nRev = S(pick).nRev + 1;
        S(pick).revSinceHalve = S(pick).revSinceHalve + 1;
        isRev = true;

        % Halve step size after TWO reversals (repeatable), with floor
        if S(pick).revSinceHalve >= 2
            S(pick).stepAmp = max(opt.MinStepAmp, S(pick).stepAmp / 2);
            S(pick).revSinceHalve = 0;
        end
    end

    % Update amplitude with bounds (uses possibly-updated stepAmp):
    S(pick).targetAmp = S(pick).targetAmp + dir * S(pick).stepAmp;
    S(pick).targetAmp = min(max(S(pick).targetAmp, AMP_MIN), AMP_MAX);
    S(pick).lastDir   = dir;

    % Values AFTER update (for logging/debugging)
    amp_updated  = S(pick).targetAmp;
    step_updated = S(pick).stepAmp;

    % Log per-frequency
    hi = S(pick).hist;
    hi.amp_present(end+1,1)  = amp_present;
    hi.amp_updated(end+1,1)  = amp_updated;
    hi.step_present(end+1,1) = step_present;
    hi.step_updated(end+1,1) = step_updated;
    hi.targetFirst(end+1,1)  = targetFirst;
    hi.choice(end+1,1)       = choice;
    hi.targetLouder(end+1,1) = targetWasChosenLouder;
    hi.dir(end+1,1)          = dir;
    hi.reversal(end+1,1)     = isRev;
    hi.amp_dBeq(end+1,1)     = 20*log10(max(amp_present,1e-12)/refAmp);
    S(pick).hist = hi;

    % Log global
    G.freqIndex(end+1,1)    = pick;
    G.freqHz(end+1,1)       = fTarget;
    G.amp_present(end+1,1)  = amp_present;
    G.amp_updated(end+1,1)  = amp_updated;
    G.step_present(end+1,1) = step_present;
    G.step_updated(end+1,1) = step_updated;
    G.targetFirst(end+1,1)  = targetFirst;
    G.choice(end+1,1)       = choice;
    G.targetLouder(end+1,1) = targetWasChosenLouder;
    G.dir(end+1,1)          = dir;
    G.reversal(end+1,1)     = isRev;

    % Check finish condition for this frequency:
    if S(pick).nRev >= opt.MaxReversalsPerFreq
        S(pick).finished = true;
    end

    if opt.Verbose
        fprintf(['T%03d | f=%.1fHz (i=%d) | choice=%d | targetLouder=%d | dir=%+d | ' ...
            'amp(present)=%.6f -> amp(new)=%.6f | step(present)=%.6f -> step(new)=%.6f | ' ...
            'rev=%d | nRev=%d\n'], ...
            trial, fTarget, pick, choice, targetWasChosenLouder, dir, ...
            amp_present, amp_updated, step_present, step_updated, isRev, S(pick).nRev);
    end
end

%% ---------------- Estimate per-frequency matches ----------------
results = struct();
results.refFreqHz = refFreq;
results.refAmp    = refAmp;
results.ampBounds = [AMP_MIN AMP_MAX];
results.global    = G;
results.opt       = opt;

results.perFreq = repmat(struct(), 1, nF);

for i = 1:nF
    h = S(i).hist;

    % Use PRESENTED amps at reversals
    revIdx = find(h.reversal);
    nUse = min(6, numel(revIdx));

    if nUse >= 2
        useIdx = revIdx(end-nUse+1:end);
        estAmp = mean(h.amp_present(useIdx));
    else
        estAmp = median(h.amp_present);
    end

    results.perFreq(i).freqHz       = S(i).freqHz;
    results.perFreq(i).estTargetAmp = estAmp;
    results.perFreq(i).nReversals   = S(i).nRev;
    results.perFreq(i).nTrials      = numel(h.amp_present);
    results.perFreq(i).hist         = h;
end

if opt.Verbose
    fprintf('\n--- Estimates (linear amps) ---\n');
    for i = 1:nF
        fprintf('%.1f Hz: estAmp=%.6f (nRev=%d, nTrials=%d)\n', ...
            results.perFreq(i).freqHz, results.perFreq(i).estTargetAmp, ...
            results.perFreq(i).nReversals, results.perFreq(i).nTrials);
    end
    fprintf('\n');
end

if strlength(string(opt.SaveFile)) > 0
    save(opt.SaveFile, 'results', 'opt', 'S');
    if opt.Verbose
        fprintf('Saved: %s\n', opt.SaveFile);
    end
end

end % main function


%% =====================================================================
function x = makeToneBlock(freqHz, amp, setup, blockLength_s, fs, taperFrac, burstseq)
seq = [];
for s = 1:setup.n_bursts
    dur = setup.pulse_dur(burstseq(s));

    % Safer timebase (no duplicated endpoint sample):
    nSamp = max(1, round(dur*fs));
    t = (0:nSamp-1)/fs;

    burst = sin(2*pi*freqHz*t) * amp;
    burst = taper(burst, taperFrac);

    offN = round(setup.off_dur*fs);
    seq  = [seq, burst, zeros(1, offN)]; %#ok<AGROW>
end

maxLen = round(blockLength_s*fs) - 4000; % matches your tonotopy buffer convention
x = padOrTrim(seq, maxLen);
end


function burstseq = makeBurstSeq(n_bursts)
valid = false;
while ~valid
    burstseq = randi([1 2], 1, n_bursts);
    switches = sum(burstseq(1:end-1) ~= burstseq(2:end));
    valid = (switches >= 4);
end
end


function x = padOrTrim(x, targetLen)
x = x(:)'; % row
if numel(x) < targetLen
    x(end+1:targetLen) = 0;
else
    x = x(1:targetLen);
end
end


function x = enforcePeak(x, peakMax)
pk = max(abs(x));
if pk > peakMax
    x = x * (peakMax/pk);
end
end


function choice = getChoice12()
% Returns 1 or 2. Returns 0 if ESC pressed.
% Uses figure keypress capture; ensure the figure has focus.

choice = NaN;

fig = findobj('Type','figure','Name','LoudnessMatch');
if isempty(fig) || ~isvalid(fig)
    fig = figure('Name','LoudnessMatch','NumberTitle','off');
    axis off;
    text(0.1,0.6,'Press 1 if interval 1 louder, 2 if interval 2 louder','FontSize',12);
    text(0.1,0.4,'ESC to abort','FontSize',12);
end
figure(fig); drawnow;

while isnan(choice)
    w = waitforbuttonpress;
    if w
        ch = get(fig,'CurrentCharacter');
        if double(ch) == 27
            choice = 0; % ESC
            return;
        elseif ch == '1'
            choice = 1;
        elseif ch == '2'
            choice = 2;
        end
    end
end
end
