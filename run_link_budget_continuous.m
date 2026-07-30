function run_link_budget_continuous(cfg, duration, timeStep, txJitterProfile, rxJitterProfile)
%RUN_LINK_BUDGET_CONTINUOUS Simulates link margin under dynamic pointing jitter.
%
% The function selects ground-space or inter-satellite terminal roles,
% calculates path and propagation losses, generates independent two-axis
% terminal motion, and plots the margin distribution and outage rate.

    if nargin < 1 || isempty(cfg)
        try
            cfg = evalin('base', 'cfg');
        catch
            cfg = ogs_config();
        end
    end
    if nargin < 2 || isempty(duration), duration = 60; end
    if nargin < 3 || isempty(timeStep), timeStep = 0.1; end
    if nargin < 4 || isempty(txJitterProfile), txJitterProfile = 'Configured Random'; end
    if nargin < 5 || isempty(rxJitterProfile), rxJitterProfile = txJitterProfile; end

    legacyRician = contains(txJitterProfile, 'Rician', 'IgnoreCase', true);
    if contains(txJitterProfile, 'Rayleigh', 'IgnoreCase', true) || legacyRician
        txJitterProfile = 'Configured Random';
        rxJitterProfile = 'Configured Random';
    end
    if contains(string(txJitterProfile), "Micius", 'IgnoreCase', true) || ...
            contains(string(rxJitterProfile), "Micius", 'IgnoreCase', true)
        timeStep = min(timeStep, 0.004);
    elseif contains(string(txJitterProfile), "OLYMPUS", 'IgnoreCase', true) || ...
            contains(string(rxJitterProfile), "OLYMPUS", 'IgnoreCase', true)
        timeStep = min(timeStep, 0.005);
    end

    gs = cfg.gs;
    satA = cfg.satA;
    link = cfg.link;
    if link.Type == "uplink"
        tx = gs;
        rx = satA;
    elseif link.Type == "inter-satellite"
        tx = satA;
        rx = cfg.satB;
    else
        tx = satA;
        rx = gs;
    end

    t = 0:timeStep:duration;
    N = numel(t);
    plotTime = t;
    plotTimeLabel = 'Time (Seconds)';

    callerRngState = rng;
    restoreRng = onCleanup(@() rng(callerRngState));
    rng('shuffle');

    lambda = link.Wavelength;
    D_tx = tx.ApertureDiameter;
    D_rx = rx.ApertureDiameter;
    sigma_tx = tx.JitterSigma;
    sigma_rx = rx.JitterSigma;
    txSuppressionDB = link.TxJitterSuppressionDB;
    rxSuppressionDB = link.RxJitterSuppressionDB;
    outageMarginDB = link.OutageMarginDB;
    if txSuppressionDB < 0 || rxSuppressionDB < 0
        error('Jitter suppression values must be nonnegative.');
    end
    if outageMarginDB < 0
        error('Required operational margin must be nonnegative.');
    end

    if link.Type == "inter-satellite"
        elevationAngle = NaN;
        L_space = link.SatDistance * 1e3;
    else
        elevationAngle = cfg.orbit.WorstCaseElevationAngle;
        L_space = slantRangeCircularOrbit( ...
            elevationAngle, satA.Height*1e3, gs.Height*1e3);
    end
    divergence = 1.22 * lambda / D_tx;
    beamRadius = L_space * divergence;

    thetaBias = link.BoresightBias;
    if nargin < 5 && ~legacyRician
        thetaBias = 0;
    end
    [txX, txY, txProfileInfo] = generate_terminal_jitter( ...
        txJitterProfile, sigma_tx, timeStep, N);
    [rxX, rxY, rxProfileInfo] = generate_terminal_jitter( ...
        rxJitterProfile, sigma_rx, timeStep, N);
    txScale = 10^(-txSuppressionDB/20);
    rxScale = 10^(-rxSuppressionDB/20);
    angularError = hypot( ...
        thetaBias + txX*txScale + rxX*rxScale, ...
        txY*txScale + rxY*rxScale);
    displacement = L_space * angularError;
    trackingLossDB = 10*log10(max( ...
        exp(-2*(displacement.^2)/(beamRadius^2)), 1e-30));

    if link.Type == "inter-satellite"
        atmosphereLossDB = 0;
        fprintf("Continuous sim path: INTER-SATELLITE (%.1f km, no atmospheric loss)\n", ...
            link.SatDistance);
    elseif cfg.weather.UseLive
        if string(cfg.weather.ContinuousMode) == "Current Hold"
            weather = fetch_live_weather(gs.Latitude, gs.Longitude);
            atmosphereLossDB = compute_atmospheric_loss( ...
                weather.VisibilityKm, weather.AttenuationType, elevationAngle, ...
                gs.Height, lambda, link.TroposphereHeight, link.AbsorptionLoss);
            windowStart = datetime('now', 'TimeZone', 'UTC');
            plotTime = windowStart + seconds(t);
            plotTimeLabel = 'Projected Time (UTC)';
            fprintf("Continuous sim atmosphere: CURRENT HOLD (%.2f km visibility, %s, %.1f minutes)\n", ...
                weather.VisibilityKm, weather.AttenuationType, duration/60);
        else
            weather = fetch_weather_history(gs.Latitude, gs.Longitude, duration);
            sampleLossDB = zeros(size(weather.VisibilityKm));
            for k = 1:numel(sampleLossDB)
                sampleLossDB(k) = compute_atmospheric_loss( ...
                    weather.VisibilityKm(k), weather.AttenuationType(k), elevationAngle, ...
                    gs.Height, lambda, link.TroposphereHeight, link.AbsorptionLoss);
            end
            atmosphereLossDB = interp1( ...
                weather.RelativeTimeSeconds, sampleLossDB, t, 'linear', 'extrap');
            plotTime = weather.TimeUTC(end) - seconds(duration) + seconds(t);
            plotTimeLabel = 'Historical Time (UTC)';
            fprintf("Continuous sim atmosphere: PAST REPLAY (%d samples, %s to %s UTC)\n", ...
                numel(weather.TimeUTC), string(weather.TimeUTC(1), "yyyy-MM-dd HH:mm"), ...
                string(weather.TimeUTC(end), "yyyy-MM-dd HH:mm"));
        end
    else
        visibility = cfg.weather.Manual.VisibilityKm;
        attenuation = cfg.weather.Manual.AttenuationType;
        fprintf("Continuous sim atmosphere: MANUAL (%.2f km visibility, %s)\n", ...
            visibility, attenuation);
        atmosphereLossDB = compute_atmospheric_loss( ...
            visibility, attenuation, elevationAngle, gs.Height, lambda, ...
            link.TroposphereHeight, link.AbsorptionLoss);
    end

    pathLossDB = fspl(L_space, lambda);
    txGainDB = 10*log10((pi*D_tx/lambda)^2);
    rxGainDB = 10*log10((pi*D_rx/lambda)^2);
    idealReceivedDBm = link.Ptx + 10*log10(tx.OpticsEfficiency) + ...
        10*log10(rx.OpticsEfficiency) + txGainDB + rxGainDB - pathLossDB;
    idealMarginDB = idealReceivedDBm - link.Preq;
    baselineMarginDB = idealReceivedDBm - atmosphereLossDB - link.Preq;
    marginProfile = baselineMarginDB + trackingLossDB;
    outageRate = 100 * sum(marginProfile < outageMarginDB) / N;

    fig = findobj('Type', 'figure', ...
        'Name', 'Continuous Dynamic Performance Simulation Analytics');
    if isempty(fig)
        fig = figure('Name', 'Continuous Dynamic Performance Simulation Analytics', ...
            'Position', [450, 80, 900, 700]);
    else
        figure(fig);
        clf(fig);
        fig.Position = [450, 80, 900, 700];
    end
    layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'loose', 'Padding', 'loose');

    marginAxes = nexttile(layout, [1, 2]);
    plot(marginAxes, plotTime, marginProfile, 'b-', 'LineWidth', 1.5);
    hold(marginAxes, 'on');
    if outageMarginDB ~= 0
        yline(marginAxes, 0, ':', 'Receiver Sensitivity Boundary (0 dB)', ...
            'Color', [0.45 0.45 0.45], 'LineWidth', 1, ...
            'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom');
    end
    yline(marginAxes, outageMarginDB, 'r--', sprintf( ...
        'Operational Outage Threshold (%.1f dB)', outageMarginDB), ...
        'LineWidth', 1.5, 'LabelHorizontalAlignment', 'right');
    if link.Type == "inter-satellite"
        referenceLabel = sprintf('Reference: No Jitter Loss (%.1f dB)', idealMarginDB);
    else
        referenceLabel = sprintf( ...
            'Reference: No Atmospheric/Jitter Loss (%.1f dB)', idealMarginDB);
    end
    yline(marginAxes, idealMarginDB, '-.', referenceLabel, ...
        'Color', [0.00 0.50 0.15], 'LineWidth', 1.5, ...
        'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom');
    grid(marginAxes, 'on');
    if link.Type == "inter-satellite"
        title(marginAxes, sprintf( ...
            'Dynamic Margin Profile (Tx: %s, %.1f dB; Rx: %s, %.1f dB)', ...
            txProfileInfo.DisplayName, txSuppressionDB, ...
            rxProfileInfo.DisplayName, rxSuppressionDB));
    else
        title(marginAxes, sprintf( ...
            'Dynamic Margin Profile (Tx: %s, %.1f dB; Rx: %s, %.1f dB; Elevation: %.1f deg)', ...
            txProfileInfo.DisplayName, txSuppressionDB, ...
            rxProfileInfo.DisplayName, rxSuppressionDB, elevationAngle));
    end
    xlabel(marginAxes, plotTimeLabel);
    ylabel(marginAxes, 'Link Margin Availability (dB)');
    profileMinimum = min([marginProfile, 0, outageMarginDB, idealMarginDB]);
    profileMaximum = max([marginProfile, 0, outageMarginDB, idealMarginDB]);
    ylim(marginAxes, [max(-100, profileMinimum-10), max(20, profileMaximum+10)]);

    pdfAxes = nexttile(layout);
    histogram(pdfAxes, marginProfile, 'Normalization', 'pdf', ...
        'FaceColor', [0.4660 0.6740 0.1880], 'EdgeColor', 'k');
    grid(pdfAxes, 'on');
    title(pdfAxes, 'Margin Probability Density Function (PDF)');
    xlabel(pdfAxes, 'Margin (dB)');
    ylabel(pdfAxes, 'PDF');

    outageAxes = nexttile(layout);
    bar(outageAxes, 1, outageRate, 0.4, ...
        'FaceColor', [0.8500 0.3250 0.0980]);
    grid(outageAxes, 'on');
    set(outageAxes, 'XTick', 1, 'XTickLabel', {'Time in Outage (%)'});
    title(outageAxes, sprintf( ...
        'Calculated Link Outage Rate (< %.1f dB)', outageMarginDB));
    ylabel(outageAxes, 'Time in Outage (%)');
    ylim(outageAxes, [0 100]);
    text(outageAxes, 1, min(outageRate + 5, 95), sprintf('%.1f%%', outageRate), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
