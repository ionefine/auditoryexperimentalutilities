%StaircaseAnalysis.m
%
% Exploration and anlysis of loudness matching results

% load in a 'results' structure
load result3
nFreqs = length(result.perFreq);

% Find the maxumum number of trials across the staircases, used to make the
% staircase plots have the same aspect ratio since some staircaises have
% more trials than others.

maxx = 0;
for i=1:nFreqs
    maxx = max(maxx,length(result.perFreq(i).hist.choice));
end

%%
% Show the staircases in figure 1, and the psychometric functions in figure
% 2 along with the ML fits with the cumulative normal.

figure(1);clf
figure(2);clf

for i=1:nFreqs

    y = result.perFreq(i).hist.amp_present;
    x = 1:numel(y);
    figure(1)
    subplot(1,nFreqs,i)
    stairs(y)

    down = result.perFreq(i).hist.targetLouder ==1;

    hold on

    plot(x(down),y(down),'bo','MarkerFaceColor','g','MarkerSize',4)
    plot(x(~down),y(~down),'bo','MarkerFaceColor','r','MarkerSize',4)

    title(sprintf('%g Hz',result.perFreq(i).freqHz))
    set(gca,'YLim',[0,.6])
    set(gca,'XLim',[0,maxx+1])
    plot([0,maxx+1],result.perFreq(i).estTargetAmp*[1,1],'k-','LineWidth',1)
    grid

    foo.intensity = round(y,4);
    foo.response = down;

    figure(2)
    
    subplot(1,nFreqs,i)
    
    % initial conditions for the cumulative normal.  t = mean, b = sd.
    p.t = .3;
    p.b = .1;
    p = fit('fitPsychometricFunction',p,{'t','b'},foo,'Normal');
        err = fitPsychometricFunction(p,foo,'Normal');

    plotPsycho(foo,'Amplitude',p,'Normal')
    figure(1)

    plot([0,maxx+1],p.t*[1,1],'m-','LineWidth',3)
    grid

    % save the matches defined by reversals and normal fits.
    reversal_thresh(i) = result.perFreq(i).estTargetAmp;
    psycho_thresh(i) = p.t;
    freq(i) = result.perFreq(i).freqHz;
end

%%
%
% Plot bar graphs  
figure(3)
clf
hold on
h(1) = plot(log(freq),reversal_thresh,'ko-','MarkerFaceColor','b');
h(2) = plot(log(freq),psycho_thresh,'ko-','MarkerFaceColor','m');
h(3) = plot(log(freq),result.refAmp*ones(size(freq)),'k:');
legend({'reversal','psycho','reference'})
grid
set(gca,'XTick',log(freq));
set(gca,'YLim',[0,.75])
logx2raw
xlabel('Test Frequency (Hz)')
ylabel(sprintf('Amplitude Matching %g Hz',result.refFreqHz));




function plotPsycho(results,intensityName,p,functionName)
% plotPsycho(results,intensityName,p,functionName)

if ~exist('intensityName','var')
    intensityName= 'Intensity';
end

intensities = unique(results.intensity);

% Then we'll loop through these intensities calculating the proportion of
% times that 'response' is equal to 1:

nCorrect = zeros(1,length(intensities));
nTrials = zeros(1,length(intensities));

for i=1:length(intensities)
    id = results.intensity == intensities(i) & isreal(results.response);
    nTrials(i) = sum(id);
    nCorrect(i) = sum(results.response(id));
end

pCorrect = nCorrect./nTrials;

hold on

sd = pCorrect.*(1-pCorrect)./sqrt(nTrials);  %pq/sqrt(n)
errorbar((intensities),100*pCorrect,100*sd,'bo','MarkerFaceColor','b');

if exist('p','var')
    %plot the parametric psychometric function
    x = linspace(min(results.intensity),max(results.intensity),101);
    evalStr = sprintf('y=%s(p,x);',functionName);
    eval(evalStr)
    plot((x),100*y,'r-','LineWidth',2);

end

ylim  = get(gca,'YLim');
xlim = get(gca,'XLim');

pThresh = 100*(1/2)^(1/3);
pThresh = 50;
if exist('p','var')
    plot([xlim(1),(p.t),(p.t)],[pThresh,pThresh,ylim(1)],'k-');
    title(sprintf('Amplitude: %5.2g',p.t));
end

set(gca,'XTick',(intensities));
%logx2raw
%set(gca,'YLim',[0,100]);
xlabel(intensityName);
ylabel('Percent Louder');
end