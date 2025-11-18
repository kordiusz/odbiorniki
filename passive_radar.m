%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% vertical_difference_spectrogram_pluto.m
%
% Vertical slow spectrogram that shows ONLY the difference between
% the first FFT frame and each new FFT frame.
%
% New information appears as bright colors,
% unchanged frequencies stay dark.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% USER SETTINGS
Fs        = 4e6;        % Pluto sample rate
Nfft      = 1024;       % FFT size
frameLen  = Nfft;       % Samples per update
numRows   = 250;        % Display height
pauseTime = 0.05;       % Slow update speed

%% INIT PLUTO SDR
rx = sdrrx('Pluto', ...
    'CenterFrequency',     1575.42e6, ... % choose your band
    'BasebandSampleRate',  Fs, ...
    'SamplesPerFrame',     frameLen, ...
    'OutputDataType',      'double');

fprintf('Pluto ready. Taking baseline FFT...\n');

%% CAPTURE BASELINE (FIRST FRAME)
x0 = rx();
fftBaseline = fftshift(abs(fft(x0, Nfft)));
fprintf('Baseline FFT stored.\n');

%% ALLOCATE IMAGE BUFFER FOR DIFFERENCE SPECTROGRAM
specImg = zeros(numRows, Nfft);

figure('Name','Difference Spectrogram','Color','w');
hImg = imagesc(flipud(specImg));
colormap(jet);
colorbar;
title('Vertical Difference Spectrogram (New - Baseline)');
xlabel('Frequency Bin');
ylabel('Time (new at top)');
drawnow;

%% MAIN LOOP
while true

    % --- GET NEW FRAME ---
    x = rx();

    % --- FFT NEW FRAME ---
    fftNew = fftshift(abs(fft(x, Nfft)));

    % --- COMPUTE DIFFERENCE ---
    delta = fftNew ./ fftBaseline;   % highlight only changes

    % --- INSERT NEW ROW AT TOP ---
    specImg = [delta.'; specImg(1:end-1,:)];

    % --- VISUAL UPDATE ---
    set(hImg, 'CData', flipud(specImg));
    drawnow;

    pause(pauseTime);
end
