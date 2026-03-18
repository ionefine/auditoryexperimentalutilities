function stim = Alternating_Stimulus(stim)
% Alternating_Stimulus Generate a configurable alternating C-tone sequence.
%
%   stim = Alternating_Stimulus() returns a default stimulus sequence:
%       hC lC hC lC aC hC lC
%
%   The stimulus combines pure tones and an ambiguous circular-pitch chord
%   modeled after stimulus.CircularPitch. Every component tone is passed
%   through stimulus.raisedCosineWindow via stimulus.make_tones.
%
%   Adjustable parameters (all optional fields in stim):
%       baseFreq        Base pitch in Hz for the low pure tone / ambiguous C
%       sequence        Cell array describing the order of events
%       toneMap         Struct mapping sequence labels to tone types/freqs
%       dur             Scalar or per-event durations in seconds
%       ISI             Scalar or per-gap silent intervals in seconds
%       t0              Explicit event onset times in seconds
%       rampDur         Scalar or per-event ramp durations in seconds
%       amp             Scalar or per-event amplitudes
%       harmonicMultipliers  Harmonics used for ambiguous circular-pitch tone
%       fsigma          Width of the spectral envelope for ambiguous tone
%       offPeriod       Silence appended after the sequence
%       makeSpectrogram Logical flag for computing stim.fft
%
%   Sequence labels can be freely changed. The default toneMap contains:
%       lC  - pure tone at middle C
%       hC  - pure tone one octave above middle C
%       aC  - ambiguous circular-pitch C

if nargin < 1 || isempty(stim)
    stim = struct();
end

hasCustomToneMap = isfield(stim,'toneMap') && ~isempty(stim.toneMap);

stim.type = 'alternating_stimulus';
d = stimulus.defaults;
d.Fs_i = 100;
d.baseFreq = 261.63;
d.sequence = {'hC','lC','hC','lC','aC','hC','lC'};
d.dur = 0.30;
d.ISI = 0.05;
d.rampDur = 0.05;
d.amp = 1;
d.harmonicMultipliers = [1,2,4,8,16];
d.fsigma = 0.85;
d.offPeriod = 0;
d.makeSpectrogram = true;
d.toneMap = defaultToneMap(d.baseFreq);
stim = stimulus.addFields(stim,d);

if ~hasCustomToneMap
    stim.toneMap = defaultToneMap(stim.baseFreq);
end

nEvents = numel(stim.sequence);
stim.dur = expandToLength(stim.dur, nEvents, 'dur');
stim.rampDur = expandToLength(stim.rampDur, nEvents, 'rampDur');
stim.amp = expandToLength(stim.amp, nEvents, 'amp');

if isfield(stim,'t0') && ~isempty(stim.t0)
    stim.t0 = expandToLength(stim.t0, nEvents, 't0');
else
    ISI = expandISI(stim, nEvents);
    stim.t0 = zeros(1,nEvents);
    for iEvent = 2:nEvents
        stim.t0(iEvent) = stim.t0(iEvent-1) + stim.dur(iEvent-1) + ISI(iEvent-1);
    end
end

eventOnsets = stim.t0;

freq = [];
amp = [];
dur = [];
rampDur = [];
t0 = [];
componentLabels = {};

for iEvent = 1:nEvents
    label = stim.sequence{iEvent};
    if ~isfield(stim.toneMap, label)
        error('Sequence label ''%s'' is not defined in stim.toneMap.', label);
    end

    toneDef = stim.toneMap.(label);
    switch lower(toneDef.kind)
        case 'pure'
            eventFreq = toneDef.freq;
            eventAmp = stim.amp(iEvent);
        case 'ambiguous'
            eventFreq = toneDef.centerFreq .* stim.harmonicMultipliers;
            eventAmp = stim.amp(iEvent) .* circularPitchEnvelope(eventFreq, toneDef.centerFreq, stim.fsigma);
        otherwise
            error('Unknown tone kind ''%s'' for sequence label ''%s''.', toneDef.kind, label);
    end

    nComponents = numel(eventFreq);
    freq = [freq, eventFreq]; %#ok<AGROW>
    amp = [amp, eventAmp]; %#ok<AGROW>
    dur = [dur, repmat(stim.dur(iEvent), 1, nComponents)]; %#ok<AGROW>
    rampDur = [rampDur, repmat(stim.rampDur(iEvent), 1, nComponents)]; %#ok<AGROW>
    t0 = [t0, repmat(stim.t0(iEvent), 1, nComponents)]; %#ok<AGROW>
    componentLabels = [componentLabels, repmat({label}, 1, nComponents)]; %#ok<AGROW>
end

stim.freq = freq;
stim.amp = amp;
stim.dur = dur;
stim.rampDur = rampDur;
stim.t0 = t0;
stim.componentLabels = componentLabels;
stim.eventOnsets = eventOnsets;
stim.eventSequence = stim.sequence;

stim.y = stimulus.make_tones(stim);
stim = stimulus.add_off_period(stim);

if stim.makeSpectrogram
    stim = stimulus.spectrogram(stim);
end
end

function toneMap = defaultToneMap(baseFreq)
toneMap.lC = struct('kind','pure','freq',baseFreq);
toneMap.hC = struct('kind','pure','freq',2*baseFreq);
toneMap.aC = struct('kind','ambiguous','centerFreq',baseFreq);
end

function vals = expandToLength(vals, n, fieldName)
if isscalar(vals)
    vals = repmat(vals, 1, n);
elseif numel(vals) ~= n
    error('stim.%s must be scalar or have %d elements.', fieldName, n);
else
    vals = reshape(vals, 1, []);
end
end

function ISI = expandISI(stim, nEvents)
if ~isfield(stim,'ISI') || isempty(stim.ISI)
    ISI = zeros(1, max(nEvents-1, 1));
elseif isscalar(stim.ISI)
    ISI = repmat(stim.ISI, 1, max(nEvents-1, 1));
elseif numel(stim.ISI) == nEvents
    ISI = reshape(stim.ISI(1:end-1), 1, []);
elseif numel(stim.ISI) == nEvents-1
    ISI = reshape(stim.ISI, 1, []);
else
    error('stim.ISI must be scalar, length nEvents-1, or length nEvents.');
end
end

function amp = circularPitchEnvelope(freq, centerFreq, fsigma)
fc = exp(mean(log(centerFreq .* [4,8])));
amp = 2 * exp(-0.5 * ((log(freq) - log(fc)) ./ fsigma).^2);
end
