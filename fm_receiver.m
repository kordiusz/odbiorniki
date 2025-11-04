%% PlutoSDR FM Radio Receiver + SIMPLE RDS PS Decoder
% Frequency: 101.6 MHz

rx = sdrrx('Pluto', ...
    'CenterFrequency', 101.6e6, ...
    'BasebandSampleRate', 1e6, ...
    'SamplesPerFrame', 400000, ...
    'GainSource', 'AGC Slow Attack');

audioFs = 48000;
audioPlayer = audioDeviceWriter('SampleRate', audioFs);

%% Filters
fmChannelFilter = designfilt('lowpassfir', ...
    'FilterOrder', 100, ...
    'PassbandFrequency', 100e3, ...
    'StopbandFrequency', 120e3, ...
    'SampleRate', 1e6);

audioDecimation = 10;
Fs_dec = 1e6 / audioDecimation;

audioLPF = designfilt('lowpassfir', ...
    'FilterOrder', 100, ...
    'PassbandFrequency', 15e3, ...
    'StopbandFrequency', 20e3, ...
    'SampleRate', Fs_dec);

% 57 kHz BPF (RDS subcarrier)
rdsBPF = designfilt('bandpassfir', ...
    'FilterOrder', 80, ...
    'CutoffFrequency1', 54e3, ...
    'CutoffFrequency2', 60e3, ...
    'SampleRate', 1e6);

% RDS baseband LPF (2.4 kHz)
rdsLPF = designfilt('lowpassfir', ...
    'FilterOrder', 100, ...
    'PassbandFrequency', 2.4e3, ...
    'StopbandFrequency', 4e3, ...
    'SampleRate', Fs_dec);


%% RDS states
bitBuf = [];
psName = repmat('_',1,8);


disp('Receiving FM + SIMPLE RDS PS... Press Ctrl+C to stop.');

%% Main loop
while true
    % FM receive and demod
    rxData = double(rx());
    rxData = filter(fmChannelFilter, rxData);
    fmDemod = angle(conj(rxData(1:end-1)) .* rxData(2:end));

    % Audio
    audioBase = fmDemod(1:audioDecimation:end);
    audioMono = filter(audioLPF, audioBase);
    audioOut = resample(audioMono, audioFs, Fs_dec);
    audioPlayer(audioOut);


    %% --- SIMPLE RDS BPSK decode ---
    rdsBand = filter(rdsBPF, fmDemod);
    rdsDec  = rdsBand(1:audioDecimation:end);
    rdsBB   = filter(rdsLPF, rdsDec);

    % Zero-crossing → bits
    bits = rdsBB > 0;
    bitBuf = [bitBuf bits']; %#ok<AGROW>

    % Minimal parsing: try full RDS group (104 bits)
    while length(bitBuf) >= 104
        block = bitBuf(1:104);
        bitBuf(1:104) = [];

        % Word 2: address + 2 chars
        word2 = block(17:32);

        addr = bi2de(word2(13:16), 'left-msb');
        c1 = char(bi2de(word2(1:8),  'left-msb'));
        c2 = char(bi2de(word2(9:16), 'left-msb'));

        if addr <= 3
            pos = addr*2 + 1;

            if pos >= 1 && pos+1 <= 8
                psName(pos:pos+1) = [c1 c2];

                % jeśli zebrało komplet znaków
                if addr == 3
                    fprintf("PS = %s\n", psName);
                end
            end
        end
    end
end
