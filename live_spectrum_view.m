% --- KONFIGURACJA PLUTO SDR ---
rx = sdrrx('Pluto');
rx.CenterFrequency = 90e6;    % MHz
rx.BasebandSampleRate = 1e6;   % Hz
rx.GainSource = 'Manual';
rx.Gain = 30;
rx.SamplesPerFrame = 4096;

% --- PARAMETRY FFT ---
Fs = rx.BasebandSampleRate;
N = rx.SamplesPerFrame;
f = linspace(-Fs/2, Fs/2, N);

% --- RYSOWANIE ---
figure;
hPlot = plot(f/1e3, zeros(1,N));
xlabel('Częstotliwość [kHz]');
ylabel('Amplituda [dB]');
title(['Widmo wokół ', num2str(rx.CenterFrequency/1e6), ' MHz']);
grid on;
ylim([-120 0]);

disp('Odbieranie i wyświetlanie widma... (Ctrl+C, aby zatrzymać)');

while true
    data = rx();                           % Odczyt danych
    spectrum = fftshift(fft(data));        % FFT i przesunięcie
    spectrum_dB = 20*log10(abs(spectrum)/max(abs(spectrum)));
    set(hPlot, 'YData', spectrum_dB);
    drawnow;
    pause(0.5)
end
