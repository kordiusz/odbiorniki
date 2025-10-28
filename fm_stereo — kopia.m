%% PlutoSDR FM Radio Receiver (Stereo, FIR1 light)
% Frequency: 101.6 MHz

% Initialize PlutoSDR receiver
rx = sdrrx('Pluto', ...
    'CenterFrequency', 101.6e6, ...
    'BasebandSampleRate', 1e6, ...
    'SamplesPerFrame', 400000, ...
    'GainSource', 'AGC Slow Attack');

% Audio configuration
audioFs = 48000; % Hz
audioPlayer = audioDeviceWriter('SampleRate', audioFs);

% --- Filters (FIR1, niskiego rzędu) ---
fmChannelFilter = fir1(31, 120e3/(1e6/2));  % LPF ~120 kHz dla kanału FM
monoLPF       = fir1(31, 15e3/(1e6/2));     % LPF L+R 0-15 kHz
pilotBPF      = fir1(31, [18.8e3 19.2e3]/(1e6/2)); % BPF pilot 19 kHz
stereoBPF     = fir1(31, [23e3 53e3]/(1e6/2));     % BPF L-R 23-53 kHz

% Decimation factor to bring to ~100 kHz range
audioDecimation = 10;
Fs_dec = 1e6 / audioDecimation;

% LPF for audio after demodulation
audioLPF = fir1(31, 15e3/(Fs_dec/2));

disp('Receiving FM stereo from 101.6 MHz... Press Ctrl+C to stop.');

%% Main loop
while true
    % Receive samples
    rxData = double(rx());

    % Band-limit FM channel
    rxData = filter(fmChannelFilter,1, rxData);

    % FM demodulation (phase difference method)
    fmDemod = angle(conj(rxData(1:end-1)) .* rxData(2:end));

    % Filtered mono component (L+R)
    LplusR = filter(monoLPF, 1,fmDemod);

    % Extract pilot (19 kHz)
    pilot = filter(pilotBPF, 1, fmDemod);

    % Generate 38 kHz subcarrier by squaring pilot
    pilotNorm = pilot / max(abs(pilot) + eps);
    subcarrier = sign(pilotNorm);  % prosty 38 kHz w fazie z pilotem

    % Extract (L-R) band around 38 kHz
    LminusR_band = filter(stereoBPF, 1,fmDemod);

    % Multiply with regenerated 38 kHz subcarrier to demodulate
    LminusR = LminusR_band .* subcarrier;

    % Decimate and low-pass both signals
    LplusR_dec = LplusR(1:audioDecimation:end);
    LminusR_dec = LminusR(1:audioDecimation:end);

    % LPF after demodulation
    LplusR_filt = filter(audioLPF, 1,LplusR_dec);
    LminusR_filt = filter(audioLPF, 1, LminusR_dec);

    % Combine to left and right channels
    L = (LplusR_filt + LminusR_filt) / 2;
    R = (LplusR_filt - LminusR_filt) / 2;

    % Resample to audio rate
    L_audio = resample(L, audioFs, Fs_dec);
    R_audio = resample(R, audioFs, Fs_dec);

    % Combine and play
    stereoOut = [L_audio, R_audio];
    audioPlayer(stereoOut);
end
