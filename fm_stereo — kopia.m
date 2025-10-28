%% --- PlutoSDR FM Stereo Receiver (wersja lekka i płynna) ---
% Autor: ChatGPT (GPT-5)
% Opis: uproszczony, wydajny odbiornik FM stereo działający płynnie z PlutoSDR

%% --- Ustawienia SDR ---
FmCenter = 101.6e6;          % częstotliwość stacji FM
SampleRate = 1e6;            % niższe Fs = mniejsze obciążenie CPU
SamplesPerFrame = 80000;

rx = sdrrx('Pluto', ...
    'CenterFrequency', FmCenter, ...
    'BasebandSampleRate', SampleRate, ...
    'SamplesPerFrame', SamplesPerFrame, ...
    'GainSource', 'AGC Slow Attack');

%% --- Etap 1: filtr kanału FM (~200 kHz) ---
fmChannelFilter = designfilt('lowpassfir', ...
    'PassbandFrequency', 100e3, 'StopbandFrequency', 120e3, ...
    'PassbandRipple', 0.5, 'StopbandAttenuation', 60, ...
    'SampleRate', SampleRate);

%% --- Etap 2: dwustopniowa decymacja (manualna) ---
Decim1 = 4;      % pierwszy stopień (1 MHz → 250 kHz)
Decim2 = 5;      % drugi stopień (250 → 50 kHz)
Fs1 = SampleRate / Decim1;
Fs_Audio = Fs1 / Decim2;

% Lekki filtr antyaliasingowy przed pierwszą decymacją
h1 = fir1(41, 0.18);   % 41-tap lowpass (~90 kHz przy 1 MHz)

% Lekki filtr antyaliasingowy przed drugą decymacją
h2 = fir1(31, 0.16);   % 31-tap lowpass (~20 kHz przy 250 kHz)

disp(['Fs1 = ', num2str(Fs1/1e3), ' kHz,  Fs_Audio = ', num2str(Fs_Audio/1e3), ' kHz']);

%% --- Filtry kanałów stereo (na Fs1 = 250 kHz) ---
sumFilter = designfilt('lowpassfir', ...
    'PassbandFrequency', 15e3, 'StopbandFrequency', 17e3, ...
    'PassbandRipple', 0.5, 'StopbandAttenuation', 60, ...
    'SampleRate', Fs1);

diffFilter = designfilt('bandpassfir', ...
    'FilterOrder', 80, 'CutoffFrequency1', 23e3, 'CutoffFrequency2', 53e3, ...
    'SampleRate', Fs1);

%% --- Odtwarzacz audio ---
audioPlayer = audioDeviceWriter('SampleRate', Fs_Audio, 'BufferSize', 8192);

disp(['Odbiór FM stereo ', num2str(FmCenter/1e6), ' MHz (płynny tryb). Ctrl+C = stop.']);

%% --- Pętla główna ---
while true
    rxData = double(rx());                        % odbiór próbek z PlutoSDR

    % 1️⃣ FM kanał – ogranicz pasmo
    rxData = filter(fmChannelFilter, rxData);

    % 2️⃣ FM demodulacja (szybka wersja bez angle)
    fmDemod = imag(conj(rxData(1:end-1)) .* rxData(2:end));

    % 3️⃣ Pierwsza decymacja (1 MHz → 250 kHz)
    x1 = filter(h1, 1, fmDemod);
    x1 = x1(1:Decim1:end);

    % 4️⃣ Stereo dekodowanie (na Fs1 = 250 kHz)
    t = (0:length(x1)-1)' / Fs1;
    pilot38 = cos(2*pi*38e3*t);

    sumSig = filter(sumFilter, x1);
    diffSig = filter(diffFilter, x1 .* pilot38);

    L = sumSig + diffSig;
    R = sumSig - diffSig;

    % 5️⃣ Druga decymacja (250 → 50 kHz)
    Ld = filter(h2, 1, L);
    Rd = filter(h2, 1, R);
    Ld = Ld(1:Decim2:end);
    Rd = Rd(1:Decim2:end);

    % 6️⃣ Odtwarzanie audio
    audioPlayer([Ld, Rd] * 2.5);
end
