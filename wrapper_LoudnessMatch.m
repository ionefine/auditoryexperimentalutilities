%wrapperLoudnessMatch
targetFreqsHz = [50 500 700 2000 4000 8000 11000];

% Ask for subject initials
initials = input('Enter subject initials: ', 's');

% Create date string (safe for filenames)
dateStr = datestr(now,'yyyymmdd_HHMMSS');

% Create filename
filename = [initials '_' dateStr '.mat'];

% Display filename
disp(['Data will be saved as: ' filename]);


LoudnessMatch_Staircase(targetFreqsHz, filename)

