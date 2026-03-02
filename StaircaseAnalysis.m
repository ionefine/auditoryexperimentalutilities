% StaircaseAnalysis.m
%
% Exploration and analysis of loudness-matching results.

% Load a MAT file that contains either `result` or `results`.
S = load('result3.mat');
if isfield(S, 'result')
    result = S.result;
elseif isfield(S, 'results')
    result = S.results;
else
    error('Expected variable `result` or `results` in result3.mat.');
end

nFreqs = numel(result.perFreq);

% Find the maximum number of trials across staircases so axes align.
maxx = 0;
for i = 1:nFreqs
    maxx = max(maxx, numel(result.perFreq(i).hist.choice));
end

% Show staircases in figure 1 and psychometric fits in figure 2.
figure(1); clf;
figure(2); clf;

reversal_thresh = zeros(1, nFreqs);
psycho_thresh = zeros(1, nFreqs);
freq = zeros(1, nFreqs);

for i = 1:nFreqs
    y = result.perFreq(i).hist.amp_present;
    x = 1:numel(y);

    figure(1);
    subplot(1, nFreqs, i);
    stairs(y);

    down = result.perFreq(i).hist.targetLouder == 1;

    hold on;
    plot(x(down), y(down), 'bo', 'MarkerFaceColor', 'g', 'MarkerSize', 4);
    plot(x(~down), y(~down), 'bo', 'MarkerFaceColor', 'r', 'MarkerSize', 4);

    title(sprintf('%g Hz', result.perFreq(i).freqHz));
    set(gca, 'YLim', [0, .6]);
    set(gca, 'XLim', [0, maxx + 1]);
    plot([0, maxx + 1], result.perFreq(i).estTargetAmp * [1, 1], 'k-', 'LineWidth', 1);
    grid on;

    foo.intensity = round(y, 4);
    foo.response = down;

    figure(2);
    subplot(1, nFreqs, i);

    % Initial conditions for cumulative normal. t = mean, b = sd.
    p.t = .3;
    p.b = .1;
    p = fit('fitPsychometricFunction', p, {'t', 'b'}, foo, 'Normal');
    err = fitPsychometricFunction(p, foo, 'Normal'); %#ok<NASGU>

    plotPsycho(foo, 'Amplitude', p, 'Normal');

    figure(1);
    plot([0, maxx + 1], p.t * [1, 1], 'm-', 'LineWidth', 3);
    grid on;

    % Save the matches defined by reversals and normal fits.
    reversal_thresh(i) = result.perFreq(i).estTargetAmp;
    psycho_thresh(i) = p.t;
    freq(i) = result.perFreq(i).freqHz;
end

% Plot summary curves.
figure(3);
clf;
hold on;
h(1) = plot(log(freq), reversal_thresh, 'ko-', 'MarkerFaceColor', 'b'); %#ok<NASGU>
h(2) = plot(log(freq), psycho_thresh, 'ko-', 'MarkerFaceColor', 'm'); %#ok<NASGU>
h(3) = plot(log(freq), result.refAmp * ones(size(freq)), 'k:'); %#ok<NASGU>
legend({'reversal', 'psycho', 'reference'});
grid on;
set(gca, 'XTick', log(freq));
set(gca, 'YLim', [0, .75]);
logx2raw;
xlabel('Test Frequency (Hz)');
ylabel(sprintf('Amplitude Matching %g Hz', result.refFreqHz));
