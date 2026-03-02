function plotPsycho(results, intensityName, p, functionName)
% plotPsycho(results, intensityName, p, functionName)

if ~exist('intensityName', 'var') || isempty(intensityName)
    intensityName = 'Intensity';
end

intensities = unique(results.intensity);

% Loop through intensities calculating response=1 proportion.
nCorrect = zeros(1, length(intensities));
nTrials = zeros(1, length(intensities));

for i = 1:length(intensities)
    id = results.intensity == intensities(i) & isreal(results.response);
    nTrials(i) = sum(id);
    nCorrect(i) = sum(results.response(id));
end

pCorrect = nCorrect ./ nTrials;

hold on;
sd = pCorrect .* (1 - pCorrect) ./ sqrt(nTrials); % pq/sqrt(n)
errorbar(log(intensities), 100 * pCorrect, 100 * sd, 'bo', 'MarkerFaceColor', 'b');

if exist('p', 'var') && ~isempty(p)
    % Plot the parametric psychometric function.
    x = linspace(min(results.intensity), max(results.intensity), 101);
    y = feval(functionName, p, x);
    plot(log(x), 100 * y, 'r-', 'LineWidth', 2);
end

ylimVals = get(gca, 'YLim');
xlimVals = get(gca, 'XLim');

pThresh = 100 * (1 / 2)^(1 / 3);

if exist('p', 'var') && ~isempty(p)
    plot([xlimVals(1), log(p.t), log(p.t)], [pThresh, pThresh, ylimVals(1)], 'k-');
    title(sprintf('Threshold: %5.2g', p.t));
end

set(gca, 'XTick', log(intensities));
logx2raw;
xlabel(intensityName);
ylabel('Percent Correct');
