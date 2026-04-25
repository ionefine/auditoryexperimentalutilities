function run_crossmodal_arousal_fmri(subjID, runNum, side)
%RUN_CROSSMODAL_AROUSAL_FMRI  fMRI task: Aim 1B cross-modal arousal.
%
% Usage:
%   run_crossmodal_arousal_fmri('S01', 1, 'left')
%
% Args:
%   subjID  : participant identifier (string)
%   runNum  : run number (integer, 1..N)
%   side    : 'left' or 'right' (which ear stimuli appear on; fixed per participant)
%
% Conditions per run (34 trials, mean ITI = 10s -> ~340s of trials):
%   CAUD     (10): cue only, no stimulus
%   AAUD     (8) : cue + attended stimulus on participant side
%   AAUDIAUD (8) : cue + attended + ignored distractor (opposite ear, opposite
%                  pitch, opposite timbre)
%   Baseline (8) : silence
%
% Per cued trial, attended pitch (high/low) and attended timbre (flute/oboe)
% are independently balanced across the 4 (pitch x timbre) combinations.
% In AAUDIAUD trials, the distractor is the OPPOSITE pitch, OPPOSITE timbre,
% on the OPPOSITE ear, so attended and distractor always differ on all three
% dimensions. The cue (central, 250 ms, constant pitch) carries the same
% pitch + timbre as the attended.
%
% In 2/8 AAUD and 2/8 AAUDIAUD trials, the attended tone is replaced by a
% smooth pitch glide (1 rising, 1 descending). Participant reports direction:
% '1' = rising, '2' = descending. A 3-down 1-up adaptive staircase on glide
% ratio holds performance near 79%.
%
% Trigger key: 't'. ESCAPE aborts.
%
% Outputs:
%   data/sub-<id>_staircase.mat                  (persisted across runs)
%   data/sub-<id>_run-<n>_<timestamp>.mat        (per-run trial log)

%% --- Validate args ---
if nargin < 3
    error('Usage: run_crossmodal_arousal_fmri(subjID, runNum, side)');
end
assert(any(strcmp(side, {'left','right'})), 'side must be ''left'' or ''right''');

%% --- Parameters ---
fs              = 48000;
cueDur          = 0.25;       % cue duration (s)
stimOnsetDelay  = 0.75;       % cue onset -> stim onset (s)
stimDur         = 0.55;       % attended/distractor duration (s)
respWindow      = 1.70;       % response window after stim onset (s)

nCAUD           = 10;
nAAUD           = 8;
nAAUDIAUD       = 8;
nBaseline       = 8;
oddballPerCond  = 2;          % per AAUD and per AAUDIAUD
itiMin          = 5;
itiMax          = 15;
itiMean         = 10;
leadInSec       = 8;          % silent baseline before first trial
tailSec         = 12;         % HRF tail after last trial

triggerKey      = 't';
risingKey       = '1';
descKey         = '2';

% Stimulus tone properties (matched to call_generate_complex_tone_stimuli.m)
f0_high         = 800;
f0_low          = 200;
amp_high        = 0.27;
amp_low         = 0.33;

% Staircase (operates on glideRatio - 1)
glideStartRatio = 1.06;
glideMin        = 1.005;
glideMax        = 1.30;
glideStepInit   = 0.02;
glideStepFloor  = 0.005;

%% --- Side mapping ---
% azimuthDeg in generate_complex_tone_stimuli: +135 = left, -135 = right.
if strcmp(side, 'left')
    azAttend = 135;  azDistract = -135;
else
    azAttend = -135; azDistract =  135;
end

%% --- Output paths ---
if ~exist('data','dir'), mkdir('data'); end
staircaseFile = fullfile('data', sprintf('sub-%s_staircase.mat', subjID));
ts            = datestr(now, 'yyyymmdd_HHMMSS');
runFile       = fullfile('data', sprintf('sub-%s_run-%02d_%s.mat', subjID, runNum, ts));

%% --- Staircase load / init ---
if exist(staircaseFile, 'file')
    s = load(staircaseFile);
    staircase = s.staircase;
    fprintf('Loaded staircase: ratio=%.4f, step=%.4f, nRev=%d\n', ...
        staircase.ratio, staircase.step, staircase.nRev);
else
    staircase = struct( ...
        'ratio',         glideStartRatio, ...
        'step',          glideStepInit, ...
        'nCorrectInRow', 0, ...
        'lastDir',       0, ...
        'nRev',          0, ...
        'history',       []);
    fprintf('Initialized staircase at ratio=%.4f\n', staircase.ratio);
end

%% --- Build trial sequence ---
trials = build_trials(nCAUD, nAAUD, nAAUDIAUD, nBaseline, oddballPerCond, ...
                      itiMin, itiMax, itiMean);

%% --- Pre-generate cached audio (4 cues, 4 attended-constants, 4 distractors) ---
fprintf('Generating audio buffers...\n');
combos = {{'high','flute'}, {'high','oboe'}, {'low','flute'}, {'low','oboe'}};
cues       = struct();
attConst   = struct();
distractor = struct();
for c = 1:numel(combos)
    p = combos{c}{1};   % 'high' or 'low'
    t = combos{c}{2};   % 'flute' or 'oboe'
    [f0, lvl] = pitch_props(p, f0_high, f0_low, amp_high, amp_low);
    cues       = setfield(cues,       p, t, make_audio(t, f0, lvl, 0,          cueDur,  'constant', 1, fs));
    attConst   = setfield(attConst,   p, t, make_audio(t, f0, lvl, azAttend,   stimDur, 'constant', 1, fs));
    distractor = setfield(distractor, p, t, make_audio(t, f0, lvl, azDistract, stimDur, 'constant', 1, fs));
end
errorSound = make_error_sound(fs);
silentGap  = zeros(round((stimOnsetDelay - cueDur) * fs), 2);

%% --- Init audio + keyboard ---
KbName('UnifyKeyNames');
InitializePsychSound(1);
pahandle = PsychPortAudio('Open', [], 1, 1, fs, 2);
PsychPortAudio('Volume', pahandle, 1.0);
cleanupObj = onCleanup(@() safe_close(pahandle)); %#ok<NASGU>

%% --- Wait for scanner trigger ---
fprintf('\nRun %d ready (subj=%s, side=%s).\n', runNum, subjID, side);
fprintf('Waiting for scanner trigger (''%s'')... ESCAPE to abort.\n', triggerKey);
if wait_for_key(triggerKey)
    fprintf('Aborted before trigger.\n'); return
end
runStart  = GetSecs;
trialBase = runStart + leadInSec;
fprintf('Trigger received. Lead-in %.1fs, then %d trials.\n', leadInSec, numel(trials));

%% --- Trial loop ---
log = struct([]);

for iTrial = 1:numel(trials)
    tr = trials(iTrial);
    onsetAbs = trialBase + tr.onsetSec;

    % --- Build trial audio ---
    if strcmp(tr.cond, 'Baseline')
        trialAudio = [];
    elseif strcmp(tr.cond, 'CAUD')
        trialAudio = cues.(tr.attendPitch).(tr.attendTimbre);
    else
        cue = cues.(tr.attendPitch).(tr.attendTimbre);

        % Attended: cached if constant, regenerated if oddball (uses staircase ratio).
        if tr.isOddball
            [f0, lvl] = pitch_props(tr.attendPitch, f0_high, f0_low, amp_high, amp_low);
            attended  = make_audio(tr.attendTimbre, f0, lvl, azAttend, ...
                                   stimDur, tr.glideDirection, staircase.ratio, fs);
        else
            attended = attConst.(tr.attendPitch).(tr.attendTimbre);
        end

        if strcmp(tr.cond, 'AAUDIAUD')
            distract = distractor.(tr.distractPitch).(tr.distractTimbre);
            stim = attended + distract;
            mx = max(abs(stim(:)));
            if mx > 0.99, stim = stim * (0.99/mx); end
        else
            stim = attended;
        end
        trialAudio = [cue; silentGap; stim];
    end

    % --- Schedule audio (blocks until scheduled start) ---
    actualStart = NaN;
    if ~isempty(trialAudio)
        PsychPortAudio('Stop', pahandle, 1);  % wait for any prior playback to finish
        PsychPortAudio('FillBuffer', pahandle, trialAudio');
        actualStart = PsychPortAudio('Start', pahandle, 1, onsetAbs, 1);
    else
        WaitSecs('UntilTime', onsetAbs);
    end

    % --- Collect response ---
    respWindowEnd = onsetAbs + stimOnsetDelay + respWindow;
    [respKey, respTime, escFlag] = collect_response(respWindowEnd, ...
        {risingKey, descKey, 'ESCAPE'});

    if escFlag
        fprintf('Aborted by user at trial %d.\n', iTrial);
        log(iTrial).aborted = true;
        save(runFile, 'log', 'trials', 'staircase', 'subjID', 'runNum', 'side', 'runStart');
        save(staircaseFile, 'staircase');
        return
    end

    % --- Score ---
    if strcmp(tr.cond, 'Baseline')
        correct = NaN; isFA = false;
    else
        [correct, isFA] = score_trial(tr, respKey, risingKey, descKey);
    end

    % --- Error feedback ---
    needFeedback = isFA || (tr.isOddball && ~isempty(respKey) && correct == false);
    if needFeedback
        PsychPortAudio('Stop', pahandle, 1);
        PsychPortAudio('FillBuffer', pahandle, errorSound');
        PsychPortAudio('Start', pahandle, 1, 0, 1);
    end

    % --- Staircase update (only on responded oddballs) ---
    if tr.isOddball && ~isempty(respKey)
        staircase = update_staircase(staircase, correct, glideStepFloor, glideMin, glideMax);
    end

    % --- Log + save ---
    if isnan(respTime), respRel = NaN; else, respRel = respTime - onsetAbs; end
    log(iTrial).iTrial          = iTrial;
    log(iTrial).cond            = tr.cond;
    log(iTrial).attendPitch     = tr.attendPitch;
    log(iTrial).attendTimbre    = tr.attendTimbre;
    log(iTrial).distractPitch   = tr.distractPitch;
    log(iTrial).distractTimbre  = tr.distractTimbre;
    log(iTrial).isOddball       = tr.isOddball;
    log(iTrial).glideDirection  = tr.glideDirection;
    log(iTrial).onsetPlanned    = tr.onsetSec;
    log(iTrial).onsetAbsRel     = onsetAbs    - runStart;
    log(iTrial).audioStartRel   = actualStart - runStart;
    log(iTrial).respKey         = respKey;
    log(iTrial).respTimeRel     = respRel;
    log(iTrial).correct         = correct;
    log(iTrial).falseAlarm      = isFA;
    log(iTrial).staircaseRatio  = staircase.ratio;
    log(iTrial).staircaseStep   = staircase.step;
    log(iTrial).staircaseNRev   = staircase.nRev;
    log(iTrial).aborted         = false;

    save(runFile, 'log', 'trials', 'staircase', 'subjID', 'runNum', 'side', 'runStart');
    save(staircaseFile, 'staircase');

    fprintf('T%02d %-9s att=%s+%-5s odd=%d dir=%-10s resp=%-3s ok=%-3s ratio=%.4f\n', ...
        iTrial, tr.cond, tr.attendPitch, tr.attendTimbre, tr.isOddball, ...
        tr.glideDirection, empty_to_dash(respKey), correct_str(correct), staircase.ratio);
end

%% --- HRF tail ---
WaitSecs(tailSec);

fprintf('\nRun %d complete. Saved: %s\n', runNum, runFile);
fprintf('Final staircase: ratio=%.4f, step=%.4f, nRev=%d\n', ...
    staircase.ratio, staircase.step, staircase.nRev);

end


%% =====================================================================
%  Helpers
%% =====================================================================

function trials = build_trials(nCAUD, nAAUD, nAAUDIAUD, nBaseline, oddballPerCond, ...
                               itiMin, itiMax, itiMean)
n = nCAUD + nAAUD + nAAUDIAUD + nBaseline;

conds = [repmat({'CAUD'},     1, nCAUD), ...
         repmat({'AAUD'},     1, nAAUD), ...
         repmat({'AAUDIAUD'}, 1, nAAUDIAUD), ...
         repmat({'Baseline'}, 1, nBaseline)];

% Per-cued-trial: balance 4 (pitch x timbre) combinations within each condition.
attendPitch  = repmat({'none'}, 1, n);
attendTimbre = repmat({'none'}, 1, n);
for c = {'CAUD','AAUD','AAUDIAUD'}
    idx = find(strcmp(conds, c{1}));
    [pitches, timbres] = balanced_pitch_timbre(numel(idx));
    attendPitch(idx)  = pitches;
    attendTimbre(idx) = timbres;
end

% Distractor properties (opposite of attended on all dimensions).
distractPitch  = cellfun(@opposite_pitch,  attendPitch,  'UniformOutput', false);
distractTimbre = cellfun(@opposite_timbre, attendTimbre, 'UniformOutput', false);

% Oddballs: oddballPerCond per AAUD and per AAUDIAUD, half rising / half descending.
isOddball = false(1, n);
glideDir  = repmat({'constant'}, 1, n);
for c = {'AAUD','AAUDIAUD'}
    idx = find(strcmp(conds, c{1}));
    pickIdx = idx(randperm(numel(idx), oddballPerCond));
    isOddball(pickIdx) = true;
    nRise = ceil(oddballPerCond/2);
    dirs = [repmat({'rising'},1,nRise), repmat({'descending'},1,oddballPerCond-nRise)];
    dirs = dirs(randperm(numel(dirs)));
    for k = 1:numel(pickIdx)
        glideDir{pickIdx(k)} = dirs{k};
    end
end

% Random order with no >2 consecutive same condition.
order = balanced_shuffle(conds);

% Jittered ITIs (uniform [itiMin,itiMax]), rescaled so mean = itiMean.
itis = itiMin + (itiMax - itiMin) * rand(1, n - 1);
itis = itis * (itiMean * (n-1) / sum(itis));
onsets = [0, cumsum(itis)];

trials = repmat(struct('cond','','attendPitch','','attendTimbre','', ...
    'distractPitch','','distractTimbre','','isOddball',false, ...
    'glideDirection','','onsetSec',0), 1, n);
for i = 1:n
    j = order(i);
    trials(i).cond           = conds{j};
    trials(i).attendPitch    = attendPitch{j};
    trials(i).attendTimbre   = attendTimbre{j};
    trials(i).distractPitch  = distractPitch{j};
    trials(i).distractTimbre = distractTimbre{j};
    trials(i).isOddball      = isOddball(j);
    trials(i).glideDirection = glideDir{j};
    trials(i).onsetSec       = onsets(i);
end
end


function [pitches, timbres] = balanced_pitch_timbre(n)
% Return n pitch/timbre assignments balanced across the 4 (pitch x timbre)
% combinations. When n is not divisible by 4, the surplus combinations are
% chosen uniformly at random.
combos = {{'high','flute'}, {'high','oboe'}, {'low','flute'}, {'low','oboe'}};
counts = floor(n/4) * ones(1,4);
extra  = mod(n, 4);
if extra > 0
    extraIdx = randperm(4, extra);
    counts(extraIdx) = counts(extraIdx) + 1;
end
pitches = cell(1, n);
timbres = cell(1, n);
k = 0;
for i = 1:4
    for j = 1:counts(i)
        k = k + 1;
        pitches{k} = combos{i}{1};
        timbres{k} = combos{i}{2};
    end
end
ord = randperm(n);
pitches = pitches(ord);
timbres = timbres(ord);
end


function p = opposite_pitch(x)
switch x
    case 'high', p = 'low';
    case 'low',  p = 'high';
    otherwise,   p = 'none';
end
end


function t = opposite_timbre(x)
switch x
    case 'flute', t = 'oboe';
    case 'oboe',  t = 'flute';
    otherwise,    t = 'none';
end
end


function [f0, lvl] = pitch_props(pitch, f0_high, f0_low, amp_high, amp_low)
if strcmp(pitch, 'high')
    f0 = f0_high; lvl = amp_high;
else
    f0 = f0_low;  lvl = amp_low;
end
end


function s = setfield(s, k1, k2, v)
s.(k1).(k2) = v;
end


function order = balanced_shuffle(conds)
n = numel(conds);
for attempt = 1:1000
    order = randperm(n);
    seq = conds(order);
    bad = false;
    for i = 3:n
        if strcmp(seq{i}, seq{i-1}) && strcmp(seq{i-1}, seq{i-2})
            bad = true; break
        end
    end
    if ~bad, return; end
end
warning('Could not produce a no-3-in-a-row shuffle in 1000 attempts.');
end


function audio = make_audio(timbre, f0, level, azDeg, dur, trajectory, glideRatio, fs)
snd.timbre       = timbre;
snd.f0           = f0;
snd.trajectory   = trajectory;
snd.glideRatio   = glideRatio;
snd.azimuthDeg   = azDeg;
snd.distanceM    = 1;
snd.level        = level;
snd.duration     = dur;
snd.fs           = fs;
snd.rampDuration = 0.025;
snd.phaseMode    = 'random';
snd = generate_complex_tone_stimuli(snd);
audio = snd.y;   % Nx2
end


function noise = make_error_sound(fs)
% Brief broadband noise burst with raised-cosine ramps.
dur  = 0.15;
n    = round(dur * fs);
ramp = round(0.02 * fs);
env  = ones(n,1);
r    = 0.5 * (1 - cos(pi*(0:ramp-1)'/ramp));
env(1:ramp)         = r;
env(end-ramp+1:end) = flipud(r);
x     = 0.4 * randn(n,1) .* env;
noise = [x x];
end


function abortFlag = wait_for_key(key)
abortFlag = false;
flush_keys(0.5);
while true
    [isDown, ~, keyCode] = KbCheck;
    if isDown
        names = KbName(keyCode);
        if ischar(names), names = {names}; end
        if matches_key(names, key),       return;                   end
        if matches_key(names, 'ESCAPE'),  abortFlag = true; return; end
    end
    WaitSecs(0.001);
end
end


function [respKey, respTime, escFlag] = collect_response(deadlineAbs, validKeys)
respKey  = '';
respTime = NaN;
escFlag  = false;
flush_keys(0.05);
captured = false;
while GetSecs < deadlineAbs
    if ~captured
        [isDown, t, keyCode] = KbCheck;
        if isDown
            names = KbName(keyCode);
            if ischar(names), names = {names}; end
            if matches_key(names, 'ESCAPE')
                escFlag = true; return
            end
            for k = 1:numel(validKeys)
                if strcmpi(validKeys{k}, 'ESCAPE'), continue; end
                if matches_key(names, validKeys{k})
                    respKey  = validKeys{k};
                    respTime = t;
                    captured = true;
                    break
                end
            end
        end
    end
    WaitSecs(0.001);
end
end


function tf = matches_key(names, key)
% Case-insensitive prefix match. Handles PTB names like '1!' for the '1' key.
tf = false;
for i = 1:numel(names)
    n = names{i};
    if strcmpi(n, key), tf = true; return; end
    if numel(n) >= numel(key) && strcmpi(n(1:numel(key)), key), tf = true; return; end
end
end


function flush_keys(maxWait)
t0 = GetSecs;
while GetSecs - t0 < maxWait
    [isDown,~,~] = KbCheck;
    if ~isDown, break; end
    WaitSecs(0.005);
end
WaitSecs(0.01);
end


function [correct, isFA] = score_trial(tr, respKey, risingKey, descKey)
correct = false;
isFA    = false;
if tr.isOddball
    if strcmp(respKey, risingKey) && strcmp(tr.glideDirection, 'rising')
        correct = true;
    elseif strcmp(respKey, descKey) && strcmp(tr.glideDirection, 'descending')
        correct = true;
    end
else
    if ~isempty(respKey), isFA = true; end
end
end


function staircase = update_staircase(staircase, correct, stepFloor, ratioMin, ratioMax)
% 3-down 1-up on (ratio - 1). Step halved once, after the first reversal.
if correct
    staircase.nCorrectInRow = staircase.nCorrectInRow + 1;
    if staircase.nCorrectInRow < 3, return; end
    staircase.nCorrectInRow = 0;
    dir = -1;   % harder
else
    staircase.nCorrectInRow = 0;
    dir = +1;   % easier
end

if staircase.lastDir ~= 0 && dir ~= staircase.lastDir
    staircase.nRev = staircase.nRev + 1;
    if staircase.nRev == 1
        staircase.step = max(staircase.step/2, stepFloor);
    end
end
staircase.lastDir = dir;

dev = staircase.ratio - 1;
dev = dev + dir * staircase.step;
dev = max(min(dev, ratioMax - 1), ratioMin - 1);
staircase.ratio = 1 + dev;
staircase.history(end+1) = staircase.ratio;
end


function s = empty_to_dash(c)
if isempty(c), s = '-'; else, s = c; end
end


function s = correct_str(c)
if isnan(c), s = '-';
elseif c,    s = 'y';
else,        s = 'n';
end
end


function safe_close(pahandle)
try, PsychPortAudio('Close', pahandle); catch, end
end
