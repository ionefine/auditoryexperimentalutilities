% This method allows you to define various auditory stimuli,
% compatible with the auditory harmonics experiment. 
%
% The methods 'stimuli' supports the following stimulus types 'stim.type'
%
% 'tone'            A single pure tone
% 'chord'           A chord containing harmonics
% 'MF'              A chord with the missing fundamental
% 'scale'           An ascending or descending scale
% 'Oxenham'         A reconstruction of the stimulus used in Oxenham et al.
% 'CircularPitch'   The circular pitch illusion
% 'Aim3'            The stimulus in Aim 3 of the R21 grant
% 'file'            Loads in an existing stimulus file ('.wav' or '.mat')
%
% All parameters of the stimulus are in a single structure, e.g. 'stim'
% The vector 'stim.y' will contain the actual sound time-series.
%
% To generate a stimulus, set up some stimulus properties and call, for
% example:
%
% 'stim = stimulus.tone(stim);'
%
% This will fill in some default parameters and generate the vector stim.y
% 
% To see the default values, call the function with no input. e.g.  
%
% stimulus.chord
%
% To play the sound, run:
%
% sound(stim.y,stim.Fs)   Where stim.Fs is the sound samping rate, default
% to 44100 Hz
%
% All stimuli are build from pure tones ramped on and off with a raised
% cosine window. Tones are defined by the vectors:
%
% 'freq'        frequencies
% 'dur'         durations
% 'amp'      amps
% 't0'          starting times
% 'rampDur'     cosine ramp durations

classdef stimulus
    methods (Static)
        function stim = tone(stim)
            % Pure tone
            stim.type = 'tone';
            d = stimulus.defaults;
            d.dur = .5;
            d.rampDur = .1;
            d.freq = 256;
            d.t0 = 0;
            d.amp = 1;

            stim = stimulus.addFields(stim,d);
            stim.y = stimulus.make_tones(stim); % make a chord with one tone
            stim = stimulus.add_off_period(stim);
        end

        function stim = chord(stim)
            % A single chord
            stim.type = 'chord';
            d = stimulus.defaults;
            % specific defaults
            d.ntones = 6;
            d.F0 = 256;
            stim  = stimulus.addFields(stim,d);

            d.freq = stim.F0*(1:d.ntones);
            d.amp = 1;
            d.dur = .5;
            d.rampDur = 0.1;
            d.t0 = 0;
            stim  = stimulus.addFields(stim,d);
            stim.y = stimulus.make_tones(stim);
            stim = stimulus.add_off_period(stim);
        end


        function stim = MF(stim)
            stim.type = 'MF';
            stim = stimulus.chord(stim);  % make a chord
            stim.amp = [0,ones(1,stim.ntones-1)]; % remove the fundamental
            stim = stimulus.chord(stim); % remake the chord
            stim = stimulus.add_off_period(stim);

        end

        % function stim = tone_sequence(stim)
        %     stim.type = 'tone_sequence';
        %     d = stimulus.defaults;
        %     % defaults
        %     d.freq = 256*ones(1,3);
        %     d.ISI = 0;
        %     d.dur = .5;
        %     d.rampDur = .05;
        %     d.amp = 1;
        %     stim  = stimulus.addFields(stim,d);
        %     stim.t0 = (0:(numel(stim.freq)-1))*(stim.ISI+stim.dur);
        % 
        %     stim.y = stimulus.make_tones(stim);
        %     stim = stimulus.add_off_period(stim);
        % 
        % 
        % end

        function stim = scale(stim)
            stim.type = 'scale';
            d = stimulus.defaults;
            d.F0 = 261.63;
            d.ISI = .1;
            d.dur = .5;
            d.amp = 1;
            d.rampDur = .1;
            stim = stimulus.addFields(stim,d);

            allFreqs = stim.F0* (2^(1/12).^(0:12));  % the 12 equally spaced notes covering an octave
            % Western scales pull out these (the white keys in the C major scale).
            d.freq = allFreqs(logical([1,0,1,0,1,1,0,1,0,1,0,1,1]));
            stim = stimulus.addFields(stim,d);

            stim.t0 = (0:(numel(stim.freq)-1))*(stim.ISI+stim.dur);

            stim.y = stimulus.make_tones(stim);
            stim = stimulus.add_off_period(stim);


        end

        function stim = CircularPitch(stim)
            stim.type = 'CircularPitch';
            d = stimulus.defaults;
            d.direction = 'ascending';
            d.F0 = 128;
            d.ISI = 0;
            d.dur = .3;
            d.rampDur= .05;
            d.fsigma = .85;
            stim = stimulus.addFields(stim,d);
            scaleStim = stimulus.scale(stim);
            d.fc = exp(mean(log(stim.F0*[4,8])));
            stim = stimulus.addFields(stim,d);

            freq = scaleStim.freq'*[1,2,4,8,16];

            ampsdB = 2*normpdf(log(freq),log(stim.fc),stim.fsigma);

            % Convert decibel to amps
            amp = ampsdB; % 10.^(-ampsdB/20);

            % define the sequence of chords
            switch stim.direction
                case 'ascending'
                    d.seq = [1:7,1];
                case 'descending'
                    d.seq = [1,7:-1:1];
                case 'ambiguous'
                    d.seq = [1,8,1,8];
                otherwise
                    error('''direction'' not defined')
            end
            stim = stimulus.addFields(stim,d);

            stim.freq = freq(stim.seq,:);
            stim.amp = amp(stim.seq,:);
            stim.t0 = repmat(((0:(length(stim.seq)-1))*(stim.ISI+stim.dur))',1,size(stim.freq,2));
            stim.y = stimulus.make_tones(stim);
            stim = stimulus.add_off_period(stim);
        end

        function stim = Oxenham(stim)

            stim.type = 'Oxenham';
            d = stimulus.defaults;
            d.ISI = 0;
            d.rampDur= .05;
            d.F0 = 256;
            d.dur = .125;
            d.Fc = 100;
            d.slope = 12;  %dB/octave
            d.nTones = 32;
            d.nReps = 4;
            stim = stimulus.addFields(stim,d);

            freq = stim.F0*[1:stim.nTones];
            octaves = log2(freq);
            ampdB = -stim.slope*abs(octaves - log2(stim.Fc));
            amp = 10.^(ampdB/20);

            stim.freq = repmat(freq,stim.nReps,1);
            stim.amp =repmat(amp,stim.nReps,1);
            stim.t0 = repmat(((0:(stim.nReps-1))*(stim.ISI+stim.dur))',1,size(stim.freq,2));

            stim.y = stimulus.make_tones(stim);
            stim = stimulus.add_off_period(stim);

        end

        function stim = Aim3(stim)
            stim.type = 'Aim3';
            d = stimulus.defaults;
            d.scFac = linspace(0,1,5).^2;
            d.seq = 1:5;
            d.dur = .5;
            d.ISI = .2;
            d.rampDur= .05;
            d.F0 = 256;
            stim = stimulus.addFields(stim,d);
            n = length(stim.scFac);
            freq = repmat(stim.F0*[1:6],n,1);
            amp = ones(n,6);
            amp(:,[1,3,5]) = repmat(stim.scFac(:),1,3);

            stim.freq = freq(stim.seq,:);
            stim.amp = amp(stim.seq,:);
            stim.t0 = repmat(((0:(n-1))*(stim.ISI+stim.dur))',1,size(stim.freq,2));

            stim.y = stimulus.make_tones(stim);
            stim = stimulus.add_off_period(stim);

        end

        function stim = file(stim)
            if exist('stim','var') && ischar(stim)
                tmp = stim;
                stim = struct();
                stim.filename = tmp;
            end
            stim.type = 'file';

            d = stimulus.defaults;
            d.filename = 'splat.mat';
            stim = stimulus.addFields(stim,d);

            if endsWith(lower(stim.filename), '.mat') |  endsWith(lower(stim.filename), '.wav')
                stim.y = tmap.read_audio_stim(stim.filename, stim.Fs);
            else
                error('File type ''%s'' not recognized.',stim.filename(end-3:end));
            end
        end

        %%% Support fuctions %%%

        % Simply pad the end of 'y' with zeros of duration .offPeriod
        function stim = add_off_period(stim)
            d.offPeriod = 0;
            stim = stimulus.addFields(stim,d);
            stim.y = [stim.y,zeros(1,floor(stim.offPeriod*stim.Fs))];
        end

        % Default parameters for all stimuli
        function d = defaults

            d.Fs = 44100;
            d.Fs_i = 100;
       
            d.noise =0;
            d.offPeriod = 0;

            d.EPI.tone_dB = 83.4;  % Calibrated volume of 1000Hz tone
            d.EPI.scanner_dB = 67; % Volume of scanner noise 110-67
            d.EPI.noise_type = 'none';


        end

        function y = raisedCosineWindow(y, Fs, rampDur)
            %RAISEDCOSINEWINDOW Apply a smooth fade-in and fade-out.

            y = y(:);
            t = (1:numel(y)) / Fs;

            tt = t(t <= rampDur);
            if isempty(tt)
                return;
            end

            ramp = (1 - cos(pi * tt / rampDur)) / 2;

            win = ones(size(y));
            win(1:numel(tt)) = ramp;
            win(end-numel(tt)+1:end) = 1 - ramp;

            y = y .* win;
        end

        function y = make_tones(stim)

            nTones = max([numel(stim.dur),numel(stim.freq),numel(stim.rampDur),numel(stim.t0),numel(stim.amp)]);
            % propagate scalars
            if isscalar(stim.t0)
                stim.t0 = stim.t0*ones(1,nTones);
            end
            if isscalar(stim.freq)
                stim.freq = stim.freq*ones(1,nTones);
            end
            if isscalar(stim.rampDur)
                stim.rampDur = stim.rampDur*ones(1,nTones);
            end
            if isscalar(stim.amp)
                stim.amp = stim.amp*ones(1,nTones);
            end
            if isscalar(stim.dur)
                stim.dur = stim.dur*ones(1,nTones);
            end

            dur = max(stim.t0(:)+stim.dur(:));
            y = zeros(ceil(dur*stim.Fs),1);         % preallocate

            % Sum all sinusoids, then window once
            for i = 1:numel(stim.freq)
                ti = 1/stim.Fs:1/stim.Fs:stim.dur(i);
                yi = stim.amp(i) * sin(stim.freq(i) * 2*pi*ti);
                yi = stimulus.raisedCosineWindow(yi, stim.Fs, stim.rampDur(i));
                tid = floor(stim.t0(i)*stim.Fs)+(1:length(yi));
                y(tid) = y(tid)+yi;
            end

            % Normalize (avoid divide-by-zero)
            mx = max(abs(y));
            if mx > 0
                y = y(:)' / mx;  % return row vector, normalized
            else
                y = y(:)';
            end
        end

        function s = addFields(s,d)

            % Adds fields in default structure d to structure s if they
            % don't exist in s.  Any overlap keeps values of s
            if ~isempty(s)
                sf = fieldnames(s);
            else
                sf = {};
            end
            df = fieldnames(d);
            % List fields missing in s
            missingIdx = find(~ismember(df,sf));
            % Assign missing fields to s
            for i = 1:length(missingIdx)
                s.(df{missingIdx(i)}) = d.(df{missingIdx(i)});
            end
        end


        function EPI_noise = make_EPI_noise(stim)
            % generates EPI simulated noise to the time course y sampled at
            % a rate Fs (Hz). Uses interpolated curves from the 'Passive
            % Attenuation' data from optoacoustics, saved in
            % OptoacousticAttenuation.csv.
            %
            % stim.EPI.tone_dB is the dB level for a pure tone
            % stim.EPI.scanner_dB is the dB level for the EPI noise.
            %
            % white noise is attenuated by the spectrum from the
            % Optoacoustics data, and then scaled in comparison of the
            % ratio of the stim.EPI.tone_dB and stim.EPI.scanner_dB.
            %
            % Scaling is with respect to the rms of the stimuli.  For
            % example, if stim.EPI.tone_dB = stim.EPI.scanner_dB, then the rms of the noise will
            % be 1/sqrt(2), which is the rms of a pure tone.

            if strcmp(stim.EPI.noise_type,'none')
                EPI_noise = zeros(size(stim.y));
                return
            end

            N = length(stim.y);
            t = (1:N)/stim.Fs;

            white_noise = randn(1,N);
            fft_white_noise = complex2real(fft(white_noise),t);

            if strcmpi(stim.EPI.noise_type, 'passive')
                EPI = csvread('OptoacousticAttenuationPassive.csv');

            elseif strcmpi(stim.EPI.noise_type, 'active')
                EPI = csvread('OptoacousticAttenuationPassive.csv');
            end
            S = interp1(log(EPI(:,1)),EPI(:,2),log(fft_white_noise.freq),'linear','extrap');
            A = 10.^(S/20);  % convert relative dB to amplitude

            fft_white_noise.amp = fft_white_noise.amp.*A; % scale the noise amplitudes by A
            EPI_noise = real(ifft(real2complex(fft_white_noise))); % convert back

            attFac = 10^((stim.EPI.scanner_dB-stim.EPI.tone_dB)/20);  % attFac is the change in amplitude for delta dB
            scFac = attFac/(sqrt(2)*rms(EPI_noise));

            EPI_noise = EPI_noise * scFac;
        end

        function stim = spectrogram(stim)
            %MYSPECTROGRAM Simple custom spectrogram using a Gaussian time window.
            %
            % fft = tmap.myspectrogram(y, Fs)
            % fft = tmap.myspectrogram(y, Fs, stim.Fs)
            %
            % stim.Fs controls the time step: dt = 1/stim.Fs (default 50 Hz)
            %
            % NOTE: requires complex2real(...) on your path.

            n = numel(stim.y);

            dur = n/stim.Fs;
            n = length(stim.y);
            t = (1:n)/stim.Fs;

            stim.y = stim.y(:)'; % row
            dt = 1/stim.Fs_i;
            stim.fft.t = (dt/2):dt:max(t);
            gaussWidth = 0.02; % seconds

            nAmps = ceil(numel(t) / 2);
            stim.fft.amp = zeros(nAmps, numel(stim.fft.t));

            for tid = 1:numel(stim.fft.t)
                gaussWin = exp(-(t - stim.fft.t(tid)).^2 / gaussWidth.^2);
                %gaussWin = normpdf(t,fft.t(tid),gaussWidth);
                newy = stim.y .* gaussWin;

                Y = complex2real(fft(newy'), t);
                Y.amp = Y.amp/mean(gaussWin);  % gmb 2/4/26 -> scaling was wrong. Now max Y.amp = carrier amplitude.

                stim.fft.amp(:, tid) = Y.amp;
            end

            stim.fft.freq = Y.freq;
        end

    end
end






