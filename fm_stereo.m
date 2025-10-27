%% PlutoSDR FM Radio Receiver (Stereo)
% Frequency: 101.6 MHz

%% --- Konfiguracja SDR ---
FmCenter = 101.6e6;
SampleRate = 2.4e6;          % wyższe niż mono, by objąć pełne MPX
SamplesPerFrame = 100000;

rx = sdrrx('Pluto', ...
    'CenterFrequency', FmCenter, ...
    'BasebandSampleRate', SampleRate, ...
    'SamplesPerFrame', SamplesPerFrame, ...
    'GainSource', 'AGC Slow Attack');

specAnalyzer = dsp.SpectrumAnalyzer( ...
    'SampleRate', SampleRate, ...
    'PlotAsTwoSidedSpectrum', false, ...
    'SpectralAverages', 20, ...
    'Title', ['FM Baseband ', num2str(FmCenter/1e6), ' MHz'], ...
    'YLimits', [-100 0]);

%% --- Filtry ---
% FM channel filter (ok. 200 kHz)
fmChannelFilter = designfilt('lowpassfir', 'PassbandFrequency', 100e3, ...
    'StopbandFrequency', 120e3, 'PassbandRipple', 0.5, ...
    'StopbandAttenuation', 60, 'SampleRate', SampleRate);

% Pilot 19 kHz
h_pilot = fdesign.bandpass('N,Fp1,Fp2,Ap', 40, 18.8e3, 19.2e3, 0.1, SampleRate);
pilot_filter = design(h_pilot, 'cheby1');

% Sum channel (L+R) 0-15 kHz
h_sum = fdesign.lowpass('N,Fp,Ap', 40, 15e3, 0.1, SampleRate);
sum_filter = design(h_sum, 'cheby1');

% Difference channel (L-R) 23-53 kHz
h_diff = fdesign.bandpass('N,Fp1,Fp2,Ap', 40, 23e3, 53e3, 0.1, SampleRate);
diff_filter = design(h_diff, 'cheby1');

%% --- Audio ---
audioFs = 48000;
audioPlayer = audioDeviceWriter('SampleRate', audioFs);

DecimationFactor = 20;               % z 2.4 MHz -> 120 kHz
Fs_AudioBase = SampleRate / DecimationFactor;

decimator = designfilt('lowpassfir', 'PassbandFrequency', 20e3, ...
    'StopbandFrequency', 25e3, 'PassbandRipple', 0.5, ...
    'StopbandAttenuation', 60, 'SampleRate', SampleRate);

%% --- Główna pętla ---
disp(['Odbiór FM Stereo na ', num2str(FmCenter/1e6), ' MHz. Ctrl+C by stop.']);
while true
    rxData = double(rx());

    % FM channel filter
    rxData = filter(fmChannelFilter, rxData);

    % FM demodulation (phase difference)
    fmDemod = angle(conj(rxData(1:end-1)) .* rxData(2:end));

    % --- Stereo decoding ---
    % Pilot 19 kHz
    pilotTone = filter(pilot_filter, fmDemod);

    % Ideal 38 kHz carrier (na potrzeby demo, bez PLL)
    t = (0:length(fmDemod)-1)' / SampleRate;
    pilot38k = cos(2*pi*38e3*t);

    % Sum channel (L+R)
    sumSignal = filter(sum_filter, fmDemod);

    % Difference channel (L-R)
    diffDemod = fmDemod .* pilot38k;          % demodulate L-R
    diffSignal = filter(sum_filter, diffDemod);

    % Stereo reconstruction
    left_raw = sumSignal + diffSignal;
    right_raw = sumSignal - diffSignal;

    % Decimate
    left_dec = decimate(filter(decimator, left_raw), DecimationFactor);
    right_dec = decimate(filter(decimator, right_raw), DecimationFactor);


    % Resample do audioFs
    left_out = resample(left_dec, audioFs, Fs_AudioBase);
    right_out = resample(right_dec, audioFs, Fs_AudioBase);

    audioOut = [left_out, right_out];

    % Spektrum
    specAnalyzer(abs(rxData));

    % Odtwarzanie
    audioPlayer(audioOut * 5); % wzmocnienie
end
