rx = sdrrx('Pluto', ...
    'CenterFrequency', 101.6e6, ...
    'BasebandSampleRate', 1e6, ...
    'SamplesPerFrame', 400000, ...
    'GainSource', 'AGC Slow Attack');

%samples per frame - jak duzo pobieramy probek na jedno rx()
%basebandsamplerate - przez co pluto mnozy sygnal (przesuwamy wtedy to do
%basebandu, czyli wokol zera)

specAnalyzer = dsp.SpectrumAnalyzer( ...
    'SampleRate', 1e6, ... 
    'PlotAsTwoSidedSpectrum', false, ...
    'SpectralAverages', 10, ...
    'Title', 'FM Station 101.6 MHz - Baseband', ...
    'YLimits', [-50 100]);  % dB scale

specAnalyzer.SpectralAverages = 20;
specAnalyzer.Window = 'hann';

% Audio configuration
audioFs = 48000; % Hz
audioPlayer = audioDeviceWriter('SampleRate', audioFs);

% Design filters
fmChannelFilter = designfilt('lowpassfir', 'PassbandFrequency', 100e3, ...
    'StopbandFrequency', 120e3, 'PassbandRipple', 0.5, ...
    'StopbandAttenuation', 60, 'SampleRate', 1e6);

audioDecimation = round(1e6 / (audioFs * 10)); % rough downsample factor
audioLPF = designfilt('lowpassfir', 'PassbandFrequency', 15e3, ...
    'StopbandFrequency', 20e3, 'SampleRate', 1e6/audioDecimation);

% Main loop
disp('Receiving FM from 101.6 MHz... Press Ctrl+C to stop.');
while true
    % Receive samples
    rxData = double(rx());

    % Band-limit to FM channel
    rxData = filter(fmChannelFilter, rxData);

    % FM demodulation (phase difference method)
    fmDemod = angle(conj(rxData(1:end-1)) .* rxData(2:end));

    % Decimate to reduce sample rate
    audioBase = decimate(fmDemod, audioDecimation);

    % Low-pass filter for mono audio (0-15 kHz)
    audioMono = filter(audioLPF, audioBase);

    % Resample to audio rate
    audioOut = resample(audioMono, audioFs, round(1e6/audioDecimation));

    iqMagnitude = real(rxData);
    specAnalyzer.step(iqMagnitude);
    % Play sound
    audioPlayer(audioOut);
end
