function run_link_budget_continuous(cfg, duration, timeStep, txJitterProfile, rxJitterProfile)
%RUN_LINK_BUDGET_CONTINUOUS Simulates a moving optical link with terminal jitter.
% Orbit geometry, weather, and high-rate pointing motion are sampled on
% separate timelines and combined into margin, access, and outage results.

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
    if duration <= 0 || timeStep <= 0
        error('Duration and time step must be positive.');
    end

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
    if t(end) < duration
        t(end+1) = duration;
    end
    N = numel(t);
    [weatherContext, startTimeUTC, plotTime, plotTimeLabel] = ...
        prepareWeatherTimeline(cfg, duration, t);

    if link.Type == "inter-satellite"
        geometryElapsed = [0, duration];
        geometry = struct( ...
            'Mode', "fixed-inter-satellite", ...
            'Source', "Fixed inter-satellite range", ...
            'ElapsedSeconds', geometryElapsed, ...
            'RangeM', repmat(link.SatDistance*1e3, 1, 2), ...
            'AzimuthDeg', [NaN, NaN], ...
            'ElevationDeg', [NaN, NaN], ...
            'Visible', [true, true]);
    else
        geometryStep = cfg.orbit.GeometrySampleTime;
        if ~isfinite(geometryStep) || geometryStep <= 0
            error('Orbit geometry sample time must be positive.');
        end
        geometryElapsed = 0:geometryStep:duration;
        if geometryElapsed(end) < duration
            geometryElapsed(end+1) = duration;
        end
        geometry = resolve_trajectory(cfg, geometryElapsed, startTimeUTC);
    end

    rangeProfileM = interp1(geometry.ElapsedSeconds, geometry.RangeM, t, 'linear');
    if link.Type == "inter-satellite"
        elevationProfileDeg = nan(size(t));
        visibleProfile = true(size(t));
    else
        elevationProfileDeg = interp1( ...
            geometry.ElapsedSeconds, geometry.ElevationDeg, t, 'linear');
        visibleProfile = elevationProfileDeg >= cfg.orbit.MinElevationAngle;
    end

    callerRngState = rng;
    restoreRng = onCleanup(@() rng(callerRngState));
    rng('shuffle');
    [txX, txY, txProfileInfo] = generate_terminal_jitter( ...
        txJitterProfile, tx.JitterSigma, timeStep, N);
    [rxX, rxY, rxProfileInfo] = generate_terminal_jitter( ...
        rxJitterProfile, rx.JitterSigma, timeStep, N);
    txSuppressionDB = link.TxJitterSuppressionDB;
    rxSuppressionDB = link.RxJitterSuppressionDB;
    outageMarginDB = link.OutageMarginDB;
    if txSuppressionDB < 0 || rxSuppressionDB < 0
        error('Jitter suppression values must be nonnegative.');
    end
    if outageMarginDB < 0
        error('Required operational margin must be nonnegative.');
    end

    thetaBias = link.BoresightBias;
    if nargin < 5 && ~legacyRician
        thetaBias = 0;
    end
    txScale = 10^(-txSuppressionDB/20);
    rxScale = 10^(-rxSuppressionDB/20);
    angularError = hypot( ...
        thetaBias + txX*txScale + rxX*rxScale, ...
        txY*txScale + rxY*rxScale);
    divergence = 1.22*link.Wavelength/tx.ApertureDiameter;
    beamRadiusM = rangeProfileM*divergence;
    displacementM = rangeProfileM.*angularError;
    trackingLossDB = 10*log10(max( ...
        exp(-2*(displacementM.^2)./(beamRadiusM.^2)), 1e-30));

    if link.Type == "inter-satellite"
        atmosphereLossDB = zeros(size(t));
        fprintf("Continuous sim path: INTER-SATELLITE (%.1f km, no atmospheric loss)\n", ...
            link.SatDistance);
    else
        atmosphereAtGeometry = calculateAtmosphereTimeline( ...
            cfg, weatherContext, geometry);
        atmosphereLossDB = interp1(geometry.ElapsedSeconds, ...
            atmosphereAtGeometry, t, 'linear');
        fprintf("Continuous sim trajectory: %s (%.1f%% geometric access)\n", ...
            geometry.Source, 100*mean(visibleProfile));
    end

    wavelength = link.Wavelength;
    pathLossDB = 20*log10(4*pi*rangeProfileM/wavelength);
    txGainDB = 10*log10((pi*tx.ApertureDiameter/wavelength)^2);
    rxGainDB = 10*log10((pi*rx.ApertureDiameter/wavelength)^2);
    receivedReferenceDBm = link.Ptx + 10*log10(tx.OpticsEfficiency) + ...
        10*log10(rx.OpticsEfficiency) + txGainDB + rxGainDB - pathLossDB;
    idealMarginDB = receivedReferenceDBm-link.Preq;
    marginProfile = idealMarginDB-atmosphereLossDB+trackingLossDB;

    serviceOutageMask = ~visibleProfile | marginProfile < outageMarginDB;
    serviceOutageRate = 100*mean(serviceOutageMask);
    noAccessRate = 100*mean(~visibleProfile);
    if any(visibleProfile)
        visibleLinkOutageRate = 100*mean( ...
            marginProfile(visibleProfile) < outageMarginDB);
    else
        visibleLinkOutageRate = NaN;
    end

    fig = findobj('Type', 'figure', ...
        'Name', 'Continuous Dynamic Performance Simulation Analytics');
    if isempty(fig)
        fig = figure('Name', 'Continuous Dynamic Performance Simulation Analytics', ...
            'Position', [450, 80, 1000, 760]);
    else
        figure(fig);
        clf(fig);
        fig.Position = [450, 80, 1000, 760];
    end
    layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'loose', 'Padding', 'loose');

    marginAxes = nexttile(layout, [1, 2]);
    marginForPlot = marginProfile;
    marginForPlot(~visibleProfile) = NaN;
    plot(marginAxes, plotTime, marginForPlot, 'b-', 'LineWidth', 1.3, ...
        'DisplayName', 'Simulated Margin');
    hold(marginAxes, 'on');
    referenceForPlot = idealMarginDB;
    referenceForPlot(~visibleProfile) = NaN;
    plot(marginAxes, plotTime, referenceForPlot, '-.', ...
        'Color', [0.00 0.50 0.15], 'LineWidth', 1.5, ...
        'DisplayName', 'No Atmospheric/Jitter Loss');
    if outageMarginDB ~= 0
        yline(marginAxes, 0, ':', 'Receiver Sensitivity Boundary (0 dB)', ...
            'Color', [0.45 0.45 0.45], 'LineWidth', 1, ...
            'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom', ...
            'HandleVisibility', 'off');
    end
    yline(marginAxes, outageMarginDB, 'r--', sprintf( ...
        'Operational Outage Threshold (%.1f dB)', outageMarginDB), ...
        'LineWidth', 1.5, 'LabelHorizontalAlignment', 'right', ...
        'HandleVisibility', 'off');
    grid(marginAxes, 'on');
    if link.Type == "inter-satellite"
        trajectorySummary = 'Fixed Inter-satellite Range';
    elseif geometry.Mode == "fixed"
        trajectorySummary = sprintf('Fixed Elevation %.1f deg', elevationProfileDeg(1));
    else
        trajectorySummary = sprintf('%s, Access %.1f%%', ...
            geometry.Source, 100*mean(visibleProfile));
    end
    title(marginAxes, sprintf( ...
        'Dynamic Margin Profile (%s; Tx: %s, %.1f dB; Rx: %s, %.1f dB)', ...
        trajectorySummary, txProfileInfo.DisplayName, txSuppressionDB, ...
        rxProfileInfo.DisplayName, rxSuppressionDB));
    xlabel(marginAxes, plotTimeLabel);
    ylabel(marginAxes, 'Link Margin (dB)');
    legend(marginAxes, 'Location', 'best');
    finiteProfile = [marginProfile(visibleProfile & isfinite(marginProfile)), ...
        idealMarginDB(visibleProfile & isfinite(idealMarginDB)), 0, outageMarginDB];
    profileMinimum = min(finiteProfile);
    profileMaximum = max(finiteProfile);
    ylim(marginAxes, [max(-100, profileMinimum-10), max(20, profileMaximum+10)]);

    pdfAxes = nexttile(layout);
    visibleMargins = marginProfile(visibleProfile & isfinite(marginProfile));
    if isempty(visibleMargins)
        axis(pdfAxes, 'off');
        text(pdfAxes, 0.5, 0.5, 'No samples above the elevation mask', ...
            'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    else
        histogram(pdfAxes, visibleMargins, 'Normalization', 'pdf', ...
            'FaceColor', [0.4660 0.6740 0.1880], 'EdgeColor', 'k');
        grid(pdfAxes, 'on');
        title(pdfAxes, 'Visible-Link Margin PDF');
        xlabel(pdfAxes, 'Margin (dB)');
        ylabel(pdfAxes, 'PDF');
    end

    outageAxes = nexttile(layout);
    bar(outageAxes, [serviceOutageRate, noAccessRate], 0.55, ...
        'FaceColor', [0.8500 0.3250 0.0980]);
    grid(outageAxes, 'on');
    set(outageAxes, 'XTick', 1:2, ...
        'XTickLabel', {'Service Outage', 'No Access'});
    title(outageAxes, sprintf( ...
        'Availability (< %.1f dB; Visible-link outage %.1f%%)', ...
        outageMarginDB, visibleLinkOutageRate));
    ylabel(outageAxes, 'Time (%)');
    ylim(outageAxes, [0 100]);
    text(outageAxes, 1:2, min([serviceOutageRate, noAccessRate]+5, 95), ...
        compose('%.1f%%', [serviceOutageRate, noAccessRate]), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

function [context, startTimeUTC, plotTime, plotTimeLabel] = prepareWeatherTimeline(cfg, duration, elapsed)
%PREPAREWEATHERTIMELINE Resolves weather data and the simulation epoch.

    startTimeUTC = datetime('now', 'TimeZone', 'UTC');
    plotTime = elapsed;
    plotTimeLabel = 'Time (Seconds)';
    if cfg.link.Type == "inter-satellite"
        context = struct('Kind', "none");
    elseif ~cfg.weather.UseLive
        context = struct( ...
            'Kind', "constant", ...
            'VisibilityKm', cfg.weather.Manual.VisibilityKm, ...
            'AttenuationType', string(cfg.weather.Manual.AttenuationType));
        fprintf("Continuous sim atmosphere: MANUAL (%.2f km visibility, %s)\n", ...
            context.VisibilityKm, context.AttenuationType);
    elseif string(cfg.weather.ContinuousMode) == "Current Hold"
        weather = fetch_live_weather(cfg.gs.Latitude, cfg.gs.Longitude);
        context = struct( ...
            'Kind', "constant", ...
            'VisibilityKm', weather.VisibilityKm, ...
            'AttenuationType', string(weather.AttenuationType));
        plotTime = startTimeUTC+seconds(elapsed);
        plotTimeLabel = 'Projected Time (UTC)';
        fprintf("Continuous sim atmosphere: CURRENT HOLD (%.2f km visibility, %s, %.1f minutes)\n", ...
            weather.VisibilityKm, weather.AttenuationType, duration/60);
    else
        weather = fetch_weather_history(cfg.gs.Latitude, cfg.gs.Longitude, duration);
        startTimeUTC = weather.TimeUTC(end)-seconds(duration);
        plotTime = startTimeUTC+seconds(elapsed);
        plotTimeLabel = 'Historical Time (UTC)';
        context = struct('Kind', "history", 'History', weather);
        fprintf("Continuous sim atmosphere: PAST REPLAY (%d samples, %s to %s UTC)\n", ...
            numel(weather.TimeUTC), string(weather.TimeUTC(1), "yyyy-MM-dd HH:mm"), ...
            string(weather.TimeUTC(end), "yyyy-MM-dd HH:mm"));
    end
end

function lossDB = calculateAtmosphereTimeline(cfg, context, geometry)
%CALCULATEATMOSPHERETIMELINE Applies weather along the changing elevation path.

    sampleCount = numel(geometry.ElapsedSeconds);
    lossDB = zeros(1, sampleCount);
    if context.Kind == "history"
        history = context.History;
        relativeWeatherTime = double(history.RelativeTimeSeconds(:));
        visibilityAtGeometry = interp1(relativeWeatherTime, ...
            double(history.VisibilityKm(:)), geometry.ElapsedSeconds, ...
            'linear', 'extrap');
    else
        visibilityAtGeometry = repmat(context.VisibilityKm, 1, sampleCount);
    end

    for sampleIndex = 1:sampleCount
        if ~geometry.Visible(sampleIndex)
            continue;
        end
        if context.Kind == "history"
            [~, weatherIndex] = min(abs( ...
                relativeWeatherTime-geometry.ElapsedSeconds(sampleIndex)));
            attenuationType = history.AttenuationType(weatherIndex);
        else
            attenuationType = context.AttenuationType;
        end
        lossDB(sampleIndex) = compute_atmospheric_loss( ...
            visibilityAtGeometry(sampleIndex), attenuationType, ...
            geometry.ElevationDeg(sampleIndex), cfg.gs.Height, ...
            cfg.link.Wavelength, cfg.link.TroposphereHeight, ...
            cfg.link.AbsorptionLoss);
    end
end
