function [xError, yError, metadata] = generate_terminal_jitter(profile, configuredSigma, timeStep, sampleCount)
%GENERATE_TERMINAL_JITTER Produces two-axis angular motion for one terminal.
% Configured Random uses the terminal's entered per-axis standard deviation.
% OLYMPUS profiles use an analytic platform PSD or a reference ATP residual.
% Micius profiles use published before- and after-ATP frequency-band values.

    profile = string(profile);
    metadata = struct( ...
        'Name', profile, 'DisplayName', profile, ...
        'RadialRms', NaN, 'BandwidthHz', Inf);

    if contains(profile, "OLYMPUS", 'IgnoreCase', true)
        cornerFrequency = 1;              % Hz
        radialPsdLevel = 160e-12;         % rad^2/Hz
        axisVariance = radialPsdLevel * pi * cornerFrequency / 4;
        axisSigma = sqrt(axisVariance);
        correlation = exp(-2*pi*cornerFrequency*timeStep);
        innovationSigma = axisSigma * sqrt(1 - correlation^2);

        xError = zeros(1, sampleCount);
        yError = zeros(1, sampleCount);
        xError(1) = axisSigma * randn;
        yError(1) = axisSigma * randn;
        for sampleIndex = 2:sampleCount
            xError(sampleIndex) = correlation*xError(sampleIndex-1) + innovationSigma*randn;
            yError(sampleIndex) = correlation*yError(sampleIndex-1) + innovationSigma*randn;
        end

        openLoopRadialRms = sqrt(2*axisVariance);
        if contains(profile, "After ATP", 'IgnoreCase', true)
            referenceResidualRms = 0.34e-6;
            residualScale = referenceResidualRms/openLoopRadialRms;
            xError = residualScale*xError;
            yError = residualScale*yError;
            metadata.Name = "OLYMPUS After ATP (Reference Design)";
            metadata.DisplayName = "OLYMPUS After ATP (Reference)";
            metadata.RadialRms = referenceResidualRms;
        else
            metadata.Name = "OLYMPUS Platform PSD (Open Loop)";
            metadata.DisplayName = "OLYMPUS Open Loop";
            metadata.RadialRms = openLoopRadialRms;
        end
        metadata.BandwidthHz = 100;
        return;
    end
    if contains(profile, "Micius", 'IgnoreCase', true)
        if contains(profile, "After ATP", 'IgnoreCase', true)
            bandDefinitions = [ ...
                0, 1, 0.16; ...
                1, 10, 0.26; ...
                10, 50, 0.25; ...
                50, 100, 0.28];
            metadata.Name = "Micius After ATP (Measured)";
            metadata.DisplayName = "Micius After ATP";
        else
            bandDefinitions = [ ...
                0, 1, 8.6; ...
                1, 10, 2.8; ...
                10, 50, 1.9; ...
                50, 100, 0.6];
            metadata.Name = "Micius Before ATP (Open Loop)";
            metadata.DisplayName = "Micius Before ATP";
        end
        xError = zeros(1, sampleCount);
        yError = zeros(1, sampleCount);
        radialVariance = 0;
        for bandIndex = 1:size(bandDefinitions, 1)
            lowFrequency = bandDefinitions(bandIndex, 1);
            highFrequency = bandDefinitions(bandIndex, 2);
            radialRms = bandDefinitions(bandIndex, 3) * 1e-6;
            axisSigma = radialRms / sqrt(2);
            xError = xError + generateBandComponent( ...
                lowFrequency, highFrequency, axisSigma, timeStep, sampleCount);
            yError = yError + generateBandComponent( ...
                lowFrequency, highFrequency, axisSigma, timeStep, sampleCount);
            radialVariance = radialVariance + radialRms^2;
        end
        metadata.RadialRms = sqrt(radialVariance);
        metadata.BandwidthHz = 100;
        return;
    end
    if ~contains(profile, "Configured Random", 'IgnoreCase', true)
        error('Unsupported jitter profile: %s', profile);
    end

    xError = configuredSigma * randn(1, sampleCount);
    yError = configuredSigma * randn(1, sampleCount);
    metadata.Name = "Configured Random";
    metadata.DisplayName = "Configured Random";
    metadata.RadialRms = sqrt(2) * configuredSigma;
end

function values = generateBandComponent(lowFrequency, highFrequency, targetSigma, timeStep, sampleCount)
%GENERATEBANDCOMPONENT Shapes white noise between two first-order cutoffs.

    highDecay = exp(-2*pi*highFrequency*timeStep);
    if lowFrequency == 0
        lowDecay = NaN;
        varianceFactor = (1-highDecay)/(1+highDecay);
    else
        lowDecay = exp(-2*pi*lowFrequency*timeStep);
        varianceFactor = (1-highDecay)^2/(1-highDecay^2) + ...
            (1-lowDecay)^2/(1-lowDecay^2) - ...
            2*(1-highDecay)*(1-lowDecay)/(1-highDecay*lowDecay);
    end

    drivingSigma = targetSigma/sqrt(varianceFactor);
    highState = 0;
    lowState = 0;
    burnInCount = ceil(5/timeStep);
    values = zeros(1, sampleCount);
    outputIndex = 0;
    for sampleIndex = 1:(burnInCount + sampleCount)
        whiteSample = drivingSigma*randn;
        highState = highDecay*highState + (1-highDecay)*whiteSample;
        if lowFrequency == 0
            output = highState;
        else
            lowState = lowDecay*lowState + (1-lowDecay)*whiteSample;
            output = highState-lowState;
        end
        if sampleIndex > burnInCount
            outputIndex = outputIndex + 1;
            values(outputIndex) = output;
        end
    end
end
