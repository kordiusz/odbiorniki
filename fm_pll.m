%% PlutoSDR FM Pilot + 38 kHz PLL Demo
% FM Stereo 101.6 MHz
clear; clc;

%% --- Parametry SDR ---
FmCenter = 101.6e6;
SampleRate = 2.4e6;       % Baseband sample rate, aby objąć cały MPX
SamplesPerFrame = 400000;

rx = sdrrx('Pluto', ...
    'CenterFrequency', FmCenter, ...
    'BasebandSampleRate', SampleRate, ...
    'SamplesPerFrame', SamplesPerFrame, ...
    'GainSource', 'AGC Slow Attack');

%% --- Filtr pilot 19 kHz ---
% Pasmo 18.8-19.2 kHz
h_pilot = fdesign.bandpass('N,Fp1,Fp2,Ap', 40, 18.8e3, 19.2e3, 0.1, SampleRate);
pilot_filter = design(h_pilot, 'cheby1');

%% --- Analizatory widma ---
specPilot = dsp.SpectrumAnalyzer('SampleRate', SampleRate, ...
    'PlotAsTwoSidedSpectrum', false, ...
    'Title', 'Pilot 19 kHz', ...
    'YLimits', [-100 0]);

specPLL = dsp.SpectrumAnalyzer('SampleRate', SampleRate, ...
    'PlotAsTwoSidedSpectrum', false, ...
    'Title', 'Lokalny Oscylator PLL 38 kHz', ...
    'YLimits', [-100 0]);

%% --- PLL 38 kHz ---
% Parametry PLL
pllGain = 0.01;    % wzmocnienie pętli
phase = 0;         % początkowa faza
vcoFreq = 38e3;    % częstotliwość VCO w Hz
pllOut = [];       % wyjście PLL

disp('Odbiór FM Stereo 101.6 MHz i synchronizacja PLL... Ctrl+C by stop');

while true
    % 1. Pobranie danych z Pluto
    rxData = double(rx());
    
    % 2. FM demodulacja
    fmDemod = angle(conj(rxData(1:end-1)) .* rxData(2:end));
    
    % 3. Detekcja pilota 19 kHz
    pilot = filter(pilot_filter, fmDemod);
    
%% PlutoSDR FM Pilot + 38 kHz PLL Demo
% FM Stereo 101.6 MHz
clear; clc;

%% --- Parametry SDR ---
FmCenter = 101.6e6;
SampleRate = 2.4e6;       % Baseband sample rate, aby objąć cały MPX
SamplesPerFrame = 400000;

rx = sdrrx('Pluto', ...
    'CenterFrequency', FmCenter, ...
    'BasebandSampleRate', SampleRate, ...
    'SamplesPerFrame', SamplesPerFrame, ...
    'GainSource', 'AGC Slow Attack');

%% --- Filtr pilot 19 kHz ---
% Pasmo 18.8-19.2 kHz
h_pilot = fdesign.bandpass('N,Fp1,Fp2,Ap', 40, 18.8e3, 19.2e3, 0.1, SampleRate);
pilot_filter = design(h_pilot, 'cheby1');

%% --- Analizatory widma ---
specPilot = dsp.SpectrumAnalyzer('SampleRate', SampleRate, ...
    'PlotAsTwoSidedSpectrum', false, ...
    'Title', 'Pilot 19 kHz', ...
    'YLimits', [-100 0]);

specPLL = dsp.SpectrumAnalyzer('SampleRate', SampleRate, ...
    'PlotAsTwoSidedSpectrum', false, ...
    'Title', 'Lokalny Oscylator PLL 38 kHz', ...
    'YLimits', [-100 0]);

%% --- PLL 38 kHz ---
% Parametry PLL
pllGain = 0.01;    % wzmocnienie pętli
phase = 0;         % początkowa faza
vcoFreq = 38e3;    % częstotliwość VCO w Hz
pllOut = [];       % wyjście PLL

disp('Odbiór FM Stereo 101.6 MHz i synchronizacja PLL... Ctrl+C by stop');

while true
    % 1. Pobranie danych z Pluto
    rxData = double(rx());
    
    % 2. FM demodulacja
    fmDemod = angle(conj(rxData(1:end-1)) .* rxData(2:end));
    
    % 3. Detekcja pilota 19 kHz
    pilot = filter(pilot_filter, fmDemod);
    
    % 4. Prosty cyfrowy PLL
    N = length(pilot);
    pllSignal = zeros(N,1);
    for n = 1:N
        % Oscylator VCO
        vco = cos(2*pi*vcoFreq*(n/SampleRate) + phase);
        % Faza błędu (mieszanie z pilotem)
        error = pilot(n) * vco;
        % Aktualizacja fazy
        phase = phase + pllGain * error;
        pllSignal(n) = vco;
    end
    
    % 5. Wyświetlanie widma
    specPilot(pilot);
    specPLL(pllSignal);
end

    
    % 5. Wyświetlanie widma
    specPilot(pilot);
    specPLL(pllSignal);
end
