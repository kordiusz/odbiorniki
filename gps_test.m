% pluto_gps_basic.m
% Basic GPS L1 C/A acquisition + simple demodulator using ADALM-PLUTO
% Shows constellation of demodulated navigation bits (BPSK symbols).
%
% Note: works as a simple demo/acquisition -> not a robust production GNSS receiver.

%% Parameters
fs_chip = 1.023e6;               % C/A chip rate
samplesPerChip = 4;              % samples per chip (choose 2..8 typically)
Fs = fs_chip * samplesPerChip;   % baseband sample rate
centerFreq = 1575.42e6;          % L1 centre frequency (Hz)
frameMS = 1;                     % process by 1 ms blocks
samplesPerMs = round(Fs * 1e-3);
samplesToCapture_ms = 200;       % ms of data to capture for acquisition (e.g. 200 ms)
numBlocks = samplesToCapture_ms; % because each block = 1 ms

% Acquisition parameters
dopplerRange = -5000:500:5000;   % Doppler search range (Hz) coarse
acqThreshold = 6;                % detection threshold (ratio of peak-to-mean) - tune if needed

% Choose a PRN to try (1..32). You can loop over list for multi-sat search.
targetPRN = 1;

%% Create Pluto SDR receiver (sdrrx)
try
    rx = sdrrx('Pluto', ...
        'CenterFrequency', centerFreq, ...
        'BasebandSampleRate', Fs, ...
        'OutputDataType','double', ...
        'SamplesPerFrame', samplesPerMs, ...
        'EnableBurstMode', false);
catch ME
    error('Failed to create Pluto SDR receiver. Make sure support package is installed and Pluto is connected. Error: %s', ME.message);
end

fprintf('Pluto configured: Fs=%.0f Hz, center=%.2f MHz, samplesPerMs=%d\n', Fs, centerFreq/1e6, samplesPerMs);

%% Generate local C/A code for target PRN (1ms code)
caCode = generate_ca_code(targetPRN);        % 1023 chips vector (1/-1)
% Upsample code to sampling rate
samplesPerCode = samplesPerMs;  % because 1ms per code
% create sampled local code for 1 ms
caCodeUpsampled = repmat(caCode, 1, 1); % 1023 chips
% we need to stretch to samplesPerCode (1023 chips -> samplesPerCode)
chipSamples = floor(samplesPerCode/1023);
% Build localCode samples (simple: repeat each chip chipSamples times, then pad/truncate)
localCodeSamples = repelem(caCode, chipSamples);
if length(localCodeSamples) < samplesPerCode
    % pad with last chip
    localCodeSamples = [localCodeSamples, caCode(1:(samplesPerCode-length(localCodeSamples)))];
else
    localCodeSamples = localCodeSamples(1:samplesPerCode);
end

% Prepare for acquisition: capture a block of data (numBlocks ms)
fprintf('Capturing %.0f ms of data for acquisition...\n', samplesToCapture_ms);
rxBuffer = complex(zeros(samplesPerMs, numBlocks));
for k = 1:numBlocks
    rxFrame = rx();
    if isempty(rxFrame)
        error('No data from Pluto. Check connection and power.');
    end
    rxBuffer(:,k) = rxFrame;
end
% concatenate to long vector
rxData = rxBuffer(:); % column vector of complex samples (samplesPerMs * numBlocks)

%% Coarse acquisition (FFT-based correlation across Doppler)
fprintf('Starting coarse acquisition for PRN %d...\n', targetPRN);
% Use first 1ms segment as reference? We'll use a 1ms chunk sliding through captured data to boost SNR.
% For acquisition, average across Nms milliseconds to reduce noise. Use up to 20ms (or captured length).
avgMs = min(20, samplesToCapture_ms);
dataForAcq = reshape(rxData(1:avgMs*samplesPerMs), samplesPerMs, avgMs);
% compute 1ms coherent sums across avgMs to create one stronger 1ms vector (non-coherent sum after carrier rot)
% We'll do brute-force: for each Doppler, mix and correlate
% Precompute FFT of local code (zero padded to next pow2)
Nfft = 2^nextpow2(samplesPerMs*2);
localCodeFFT = conj(fft(localCodeSamples, Nfft));
bestMetric = 0;
bestDoppler = 0;
bestShift = 0;

for dop = dopplerRange
    % Mix dataForAcq to remove Doppler for each ms and sum coherently across avgMs
    mixedSum = zeros(samplesPerMs,1);
    for m = 1:avgMs
        t0 = (0:samplesPerMs-1).' / Fs + (m-1)*1e-3;
        mixed = dataForAcq(:,m) .* exp(-1j*2*pi*dop*t0);
        mixedSum = mixedSum + mixed;
    end
    % FFT-based circular correlation (via multiplication in freq domain)
    R = ifft(fft(mixedSum, Nfft) .* localCodeFFT);
    Rmag = abs(R(1:samplesPerMs));
    [peak, shiftIdx] = max(Rmag);
    metric = peak / mean(Rmag); % simple ratio metric
    if metric > bestMetric
        bestMetric = metric;
        bestDoppler = dop;
        bestShift = shiftIdx - 1; % zero-based
    end
end

fprintf('Best metric=%.2f Doppler=%.0f Hz shift=%d samples\n', bestMetric, bestDoppler, bestShift);
if bestMetric < acqThreshold
    warning('No strong acquisition peak found (metric %.2f < threshold %.2f). Try increasing capture time, adjusting doppler range or PRN list.', bestMetric, acqThreshold);
else
    fprintf('Acquired PRN %d (metric %.2f) at Doppler %.0f Hz.\n', targetPRN, bestMetric, bestDoppler);
end

%% Extract a longer stream for demodulation (e.g. 2 seconds) - but we'll use what we have plus additional capture
% We'll capture extra 2 seconds (2000 ms) or until enough symbols collected (e.g. 100 symbols)
symbolsNeeded = 100; % number of navigation bits to collect (each symbol = 20ms)
msPerSymbol = 20;
totalMsNeeded = symbolsNeeded * msPerSymbol;
fprintf('Capturing additional %.0f ms for symbol extraction...\n', totalMsNeeded);
rxData2 = complex(zeros(samplesPerMs, totalMsNeeded));
for k = 1:totalMsNeeded
    rxFrame = rx();
    if isempty(rxFrame)
        error('No data from Pluto during symbol capture.');
    end
    rxData2(:,k) = rxFrame;
end
rxLong = rxData2(:);

%% Wipe off Doppler and align code using bestShift
% Build complex exponential to remove carrier Doppler (approximate constant over short time)
nTotal = length(rxLong);
tLong = (0:nTotal-1).' / Fs;
carrierMix = exp(-1j*2*pi*bestDoppler * tLong);
rxWiped = rxLong .* carrierMix;

% Now perform ms-by-ms correlation with localCodeSamples (circularly shifted by bestShift)
% Pre-generate local code repeated for alignment
localCode_ms = localCodeSamples(:);
% Make a circularly-shifted version to match acquisition shift
localShifted = circshift(localCode_ms, bestShift);

% For every ms: multiply-by-code (despread) and compute complex sum per ms.
numMsCaptured = totalMsNeeded;
despreadMs = zeros(samplesPerMs, numMsCaptured);
for m = 1:numMsCaptured
    idx = (m-1)*samplesPerMs + (1:samplesPerMs);
    segment = rxWiped(idx);
    % correlate (i.e., multiply by conjugate of code and sum)
    despread = segment .* localShifted;    % despread at sample-rate
    despreadMs(:,m) = despread;
end

% For each ms sum across samples to collapse chip-rate -> one complex sample per ms
msSymbols = sum(despreadMs, 1).';   % complex values per ms (size numMsCaptured x 1)

%% Form navigation bits by integrating 20 ms groups (each navigation bit = 20 ms)
numSymbols = floor(numMsCaptured / msPerSymbol);
symbolSamples = zeros(numSymbols,1);
for s = 1:numSymbols
    groupIdx = (s-1)*msPerSymbol + (1:msPerSymbol);
    % Coherent integrate 20ms (this yields approx BPSK symbol)
    symbolSamples(s) = sum(msSymbols(groupIdx));
end

%% Plot constellation (I vs Q) of the symbolSamples
figure;
scatter(real(symbolSamples), imag(symbolSamples), 30, 'filled');
xlabel('I (In-phase)');
ylabel('Q (Quadrature)');
title(sprintf('Constellation of Demodulated Navigation Bits (PRN %d) — %d symbols', targetPRN, numSymbols));
grid on;
axis equal;

%% Optionally show decision (hard) and quick bit plot
bitsHard = real(symbolSamples) > 0;
figure;
subplot(2,1,1);
plot(real(symbolSamples), '-o');
ylabel('I (integrated)');
title('Integrated symbol I component over time');
grid on;
subplot(2,1,2);
stairs(bitsHard);
ylim([-0.2 1.2]);
xlabel('Symbol index');
ylabel('Demodulated bit (hard decision)');
title('Hard-decoded navigation bits (50 bps)');

%% Clean up
release(rx); clear rx;

%% Helper: generate C/A code for PRN (G1/G2)
function ca = generate_ca_code(prn)
% generate_ca_code  Generate GPS C/A code for a given PRN (1..37 typically)
% returns 1x1023 vector of +1/-1 values
if prn < 1 || prn > 37
    error('PRN must be in 1..37');
end

% G2 tap table (per GPS ICD)
g2taps = [...
    2 6; 3 7; 4 8; 5 9; 1 9; 2 10; 1 8; 2 9; 3 10; 2 3; ...
    3 4; 5 6; 6 7; 7 8; 8 9; 9 10; 1 4; 2 5; 3 6; 4 7; ...
    5 8; 6 9; 1 3; 4 6; 5 7; 6 8; 7 9; 8 10; 1 6; 2 7; ...
    3 8; 4 9; 5 10; 4 10; 1 7; 2 8];
% PRN mapping uses taps g2taps(prn,:)
taps = g2taps(prn,:);
% initialize shift registers
G1 = -ones(1,10); % use -1 for logic '1' mapping to -1/+1 to keep multiply math easier
G2 = -ones(1,10);
ca = zeros(1,1023);
for i=1:1023
    g1 = G1(10);
    g2 = G2(taps(1)) * G2(taps(2));
    ca(i) = - (g1 * g2);  % produce +1/-1 (neg sign adjust so standard mapping matches)
    % shift G1
    newG1 = G1(3)*G1(10); % taps 3 and 10 (x^10 + x^3 + 1)
    G1 = [newG1, G1(1:9)];
    % shift G2
    newG2 = G2(2)*G2(3)*G2(6)*G2(8)*G2(9)*G2(10); % G2 taps
    G2 = [newG2, G2(1:9)];
end
% normalize to +1/-1
ca = sign(ca);
% convert 0 to 1 if any
ca(ca==0) = 1;
end
