function stim = Alternating_Stimulus(stim)
% Alternating_Stimulus Generate a configurable alternating C-tone sequence.
%
% Default event sequence:
%   hC lC hC lC aC hC lC
%
% The implementation expands the event-level description in stim.sequence
% into the component-level fields expected by stimulus.make_tones. Pure-tone
% events contribute one frequency, while ambiguous events contribute the
% six-harmonic Aim 3 chord defined in stimulus.Aim3.
%
% Optional fields in stim:
%   baseFreq                      Base pitch in Hz for the low pure tone / ambiguous C
%   sequence                      Cell array describing the order of events
%   toneMap                       Struct mapping sequence labels to tone definitions
%   dur                           Scalar or per-event durations in seconds
%   ISI                           Scalar or per-gap silent intervals in seconds
%   t0                            Explicit event onset times in seconds
%   rampDur                       Scalar or per-event ramp durations in seconds
%   amp                           Scalar or per-event amplitudes
%   harmonicMultipliers           Harmonics used for harmonic-tone events
%   ambiguousHarmonicMultipliers  Harmonics used for the Aim 3 ambiguous tone
%   scFac                         Odd-harmonic scale factor for the Aim 3 ambiguous tone
%   offPeriod                     Silence appended after the sequence
%   makeSpectrogram               Logical flag for computing stim.fft
%
% Default toneMap entries:
%   lC  - pure tone at middle C
%   hC  - pure tone one octave above middle C
%   aC  - Aim 3 ambiguous C with attenuated odd harmonics

if nargin < 1 || isempty(stim)
    stim = struct();
end

hasCustomToneMap = isfield(stim, 'toneMap') && ~isempty(stim.toneMap);
stim.type = 'alternating_stimulus';
stim = stimulus.addFields(stim, defaultConfig());

if ~hasCustomToneMap
    stim.toneMap = defaultToneMap(stim.baseFreq);
end

nEvents = numel(stim.sequence);
eventDurations = expandToLength(stim.dur, nEvents, 'dur');
eventRampDurations = expandToLength(stim.rampDur, nEvents, 'rampDur');
eventAmplitudes = expandToLength(stim.amp, nEvents, 'amp');
eventOnsets = resolveEventOnsets(stim, nEvents, eventDurations);

[eventFreq, componentAmp, componentDur, componentRampDur, componentOnsets, componentLabels] = ...
    buildSequenceComponents(stim, eventDurations, eventRampDurations, eventAmplitudes, eventOnsets);

stim.freq = eventFreq;
stim.amp = componentAmp;
stim.dur = componentDur;
stim.rampDur = componentRampDur;
stim.t0 = componentOnsets;
stim.componentLabels = componentLabels;
stim.eventOnsets = eventOnsets;
stim.eventSequence = stim.sequence;

stim.y = stimulus.make_tones(stim);
stim = stimulus.add_off_period(stim);

if stim.makeSpectrogram
    stim = stimulus.spectrogram(stim);
end
soundsc(stim.y, stim.Fs)
end

function d = defaultConfig()
d = stimulus.defaults;
d.Fs_i = 100;
d.Fs = 8192;
d.baseFreq = 261.63;
d.sequence = {'aC', 'aC'}; %'hhC','lhC', 'hhC','lhC', 'aC', 'lhC','hhC','lhC', 'hhC', 'aC', 'hhC'};
d.dur = 0.30;
d.ISI = 0.05;
d.rampDur = 0.05;
d.amp = 1;
d.ambiguousHarmonicMultipliers = 1:6;
d.harmonicMultipliers = 1:5;
d.scFac = 0;
d.offPeriod = 0;
d.makeSpectrogram = true;
d.toneMap = defaultToneMap(d.baseFreq);
end

function toneMap = defaultToneMap(baseFreq)
toneMap.lC = struct('kind', 'pure', 'freq', baseFreq);
toneMap.hC = struct('kind', 'pure', 'freq', 2 * baseFreq);
toneMap.lhC = struct('kind', 'harmonic', 'freq', baseFreq);
toneMap.hhC = struct('kind', 'harmonic', 'freq', 2 * baseFreq);
toneMap.aC = struct('kind', 'ambiguous', 'centerFreq', baseFreq);
end

function eventOnsets = resolveEventOnsets(stim, nEvents, eventDurations)
if isfield(stim, 't0') && ~isempty(stim.t0)
    eventOnsets = expandToLength(stim.t0, nEvents, 't0');
    return
end

interStimulusIntervals = expandISI(stim, nEvents);
eventOnsets = zeros(1, nEvents);

for iEvent = 2:nEvents
    previousOffset = eventOnsets(iEvent - 1) + eventDurations(iEvent - 1);
    eventOnsets(iEvent) = previousOffset + interStimulusIntervals(iEvent - 1);
end
end

function [freq, amp, dur, rampDur, t0, componentLabels] = buildSequenceComponents(stim, eventDurations, eventRampDurations, eventAmplitudes, eventOnsets)
nEvents = numel(stim.sequence);
componentCountPerEvent = zeros(1, nEvents);
eventFrequencies = cell(1, nEvents);
eventComponentAmplitudes = cell(1, nEvents);

for iEvent = 1:nEvents
    [eventFrequencies{iEvent}, eventComponentAmplitudes{iEvent}] = ...
        describeEventComponents(stim, stim.sequence{iEvent}, eventAmplitudes(iEvent));
    componentCountPerEvent(iEvent) = numel(eventFrequencies{iEvent});
end

nComponents = sum(componentCountPerEvent);
freq = zeros(1, nComponents);
amp = zeros(1, nComponents);
dur = zeros(1, nComponents);
rampDur = zeros(1, nComponents);
t0 = zeros(1, nComponents);
componentLabels = cell(1, nComponents);

nextComponent = 1;
for iEvent = 1:nEvents
    componentIndices = nextComponent:(nextComponent + componentCountPerEvent(iEvent) - 1);

    freq(componentIndices) = eventFrequencies{iEvent};
    amp(componentIndices) = eventComponentAmplitudes{iEvent};
    dur(componentIndices) = eventDurations(iEvent);
    rampDur(componentIndices) = eventRampDurations(iEvent);
    t0(componentIndices) = eventOnsets(iEvent);
    componentLabels(componentIndices) = repmat(stim.sequence(iEvent), 1, componentCountPerEvent(iEvent));

    nextComponent = componentIndices(end) + 1;
end
end

function [eventFreq, eventAmp] = describeEventComponents(stim, label, baseAmplitude)
if ~isfield(stim.toneMap, label)
    error('Sequence label ''%s'' is not defined in stim.toneMap.', label);
end

toneDef = stim.toneMap.(label);
if ~isfield(toneDef, 'kind') || isempty(toneDef.kind)
    error('stim.toneMap.%s must define a non-empty ''kind'' field.', label);
end

switch lower(toneDef.kind)
    case 'pure'
        if ~isfield(toneDef, 'freq') || isempty(toneDef.freq)
            error('stim.toneMap.%s must define ''freq'' for pure tones.', label);
        end
        eventFreq = toneDef.freq;
        eventAmp = baseAmplitude;
    case 'harmonic'
        if ~isfield(toneDef, 'freq') || isempty(toneDef.freq)
            error('stim.toneMap.%s must define ''freq'' for harmonic tones.', label);
        end
        eventFreq = toneDef.freq .* stim.harmonicMultipliers;
        eventAmp = baseAmplitude * ones(size(stim.harmonicMultipliers));
    case 'ambiguous'
        if ~isfield(toneDef, 'centerFreq') || isempty(toneDef.centerFreq)
            error('stim.toneMap.%s must define ''centerFreq'' for ambiguous tones.', label);
        end
        eventFreq = toneDef.centerFreq .* stim.ambiguousHarmonicMultipliers;
        eventAmp = baseAmplitude * ones(size(stim.ambiguousHarmonicMultipliers));
        oddHarmonics = mod(stim.ambiguousHarmonicMultipliers, 2) == 1;
        eventAmp(oddHarmonics) = baseAmplitude * stim.scFac;
    otherwise
        error('Unknown tone kind ''%s'' for sequence label ''%s''.', toneDef.kind, label);
end

% Ensure row vectors so downstream concatenation is predictable.
eventFreq = reshape(eventFreq, 1, []);
eventAmp = expandAmplitudeToMatch(eventAmp, numel(eventFreq), label);
end

function eventAmp = expandAmplitudeToMatch(eventAmp, nComponents, label)
if isscalar(eventAmp)
    eventAmp = repmat(eventAmp, 1, nComponents);
elseif numel(eventAmp) ~= nComponents
    error('Amplitude definition for sequence label ''%s'' must be scalar or match its component count.', label);
else
    eventAmp = reshape(eventAmp, 1, []);
end
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
if ~isfield(stim, 'ISI') || isempty(stim.ISI)
    ISI = zeros(1, max(nEvents - 1, 1));
elseif isscalar(stim.ISI)
    ISI = repmat(stim.ISI, 1, max(nEvents - 1, 1));
elseif numel(stim.ISI) == nEvents
    ISI = reshape(stim.ISI(1:end-1), 1, []);
elseif numel(stim.ISI) == nEvents - 1
    ISI = reshape(stim.ISI, 1, []);
else
    error('stim.ISI must be scalar, length nEvents-1, or length nEvents.');
end
end
