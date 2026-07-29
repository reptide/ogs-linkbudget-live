function run_link_budget_continuous(cfg, duration, timeStep, jitterModel)
%RUN_LINK_BUDGET_CONTINUOUS Simulates link margin under dynamic pointing jitter.
%
%   run_link_budget_continuous(cfg, duration, timeStep, jitterModel)
%
%   The function selects ground-space or inter-satellite terminal roles,
%   calculates path and propagation losses, samples two-axis pointing errors,
%   and plots the resulting margin distribution and outage rate. Rayleigh
%   mode uses zero mean offset; Rician mode applies BoresightBias.

    if nargin < 1 || isempty(cfg)
        try
            cfg = evalin('base', 'cfg');
        catch
            cfg = ogs_config();
        end
    end
    if nargin < 2 || isempty(duration),  duration = 60;  end
    if nargin < 3 || isempty(timeStep),  timeStep = 0.1; end
    if nargin < 4 || isempty(jitterModel), jitterModel = 'Rayleigh (No Bias)'; end

    gs   = cfg.gs;
    satA = cfg.satA;
    satB = cfg.satB;
    link = cfg.link;

    if link.Type == "uplink"
        tx = gs;
        rx = satA;
    elseif link.Type == "inter-satellite"
        tx = satA;
        rx = satB;
    else
        tx = satA;
        rx = gs;
    end

    t = 0:timeStep:duration;
    N = length(t);
    plotTime = t;
    plotTimeLabel = 'Time (Seconds)';

    callerRngState = rng;
    restoreRng = onCleanup(@() rng(callerRngState));
    rng('shuffle');

    %% ---- 1. Physical layer configuration ----
    lambda = link.Wavelength;             % m
    D_tx = tx.ApertureDiameter;           % m
    D_rx = rx.ApertureDiameter;           % m

    sigma_tx = tx.JitterSigma;             % rad, transmitter tracking jitter
    sigma_rx = rx.JitterSigma;             % rad, receiver tracking jitter

    isRician = contains(jitterModel, 'Rician', 'IgnoreCase', true);
    if isRician
        theta_bias = link.BoresightBias;  % rad, nonzero mean offset
    else
        theta_bias = 0;                   % Rayleigh: zero mean by definition
    end

    %% ---- 2. Link geometry ----
    if link.Type == "inter-satellite"
        elevationAngle = NaN;
        L_space = link.SatDistance * 1e3;  % km -> m
    else
        elevationAngle = cfg.orbit.WorstCaseElevationAngle;
        L_space = slantRangeCircularOrbit(elevationAngle, satA.Height*1e3, gs.Height*1e3); % meters
    end

    %% ---- 3. Beam divergence / footprint at the receiver ----
    theta_div = 1.22 * lambda / D_tx;      % diffraction-limited half-angle, rad
    w_z = L_space * theta_div;             % beam footprint radius at receiver, m

    sigma_total = sqrt(sigma_tx^2 + sigma_rx^2);
    if sigma_total == 0, sigma_total = 1e-9; end % avoid zero-division

    %% ---- 4. Generate random tracking misalignments across the pass ----
    x_error = theta_bias + sigma_total * randn(1, N);
    y_error = sigma_total * randn(1, N);
    theta_pointing = sqrt(x_error.^2 + y_error.^2);  % radial tracking offset, rad
    r_displacement = L_space * theta_pointing;        % m

    L_tracking_raw = exp(-2 * (r_displacement.^2) / (w_z^2));
    L_tracking_dB = 10 * log10(max(L_tracking_raw, 1e-30)); % floor at -300 dB

    %% ---- 5. Atmospheric loss ----
    if link.Type == "inter-satellite"
        L_atm_dB = 0;
        fprintf("Continuous sim path: INTER-SATELLITE (%.1f km, no atmospheric loss)\n", ...
            link.SatDistance);
    elseif cfg.weather.UseLive
        if string(cfg.weather.ContinuousMode) == "Current Hold"
            weather = fetch_live_weather(gs.Latitude, gs.Longitude);
            L_atm_dB = compute_atmospheric_loss( ...
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

            L_atm_dB = interp1(weather.RelativeTimeSeconds, sampleLossDB, t, ...
                'linear', 'extrap');
            plotTime = weather.TimeUTC(end) - seconds(duration) + seconds(t);
            plotTimeLabel = 'Historical Time (UTC)';
            fprintf("Continuous sim atmosphere: PAST REPLAY (%d samples, %s to %s UTC)\n", ...
                numel(weather.TimeUTC), string(weather.TimeUTC(1), "yyyy-MM-dd HH:mm"), ...
                string(weather.TimeUTC(end), "yyyy-MM-dd HH:mm"));
        end
    else
        visibility = cfg.weather.Manual.VisibilityKm;
        attenuationType = cfg.weather.Manual.AttenuationType;
        fprintf("Continuous sim atmosphere: MANUAL (%.2f km visibility, %s)\n", visibility, attenuationType);
        L_atm_dB = compute_atmospheric_loss(visibility, attenuationType, elevationAngle, ...
            gs.Height, lambda, link.TroposphereHeight, link.AbsorptionLoss);
    end

    %% ---- 6. Static baseline margin (dBm-consistent) ----
    FSPL_dB = fspl(L_space, lambda);  % positive-convention path loss, dB
    G_tx = 10*log10((pi*D_tx/lambda)^2);
    G_rx = 10*log10((pi*D_rx/lambda)^2);

    P_rx_ideal_dBm = link.Ptx + 10*log10(tx.OpticsEfficiency) + ...
        10*log10(rx.OpticsEfficiency) + G_tx + G_rx - FSPL_dB;
    ideal_margin_dB = P_rx_ideal_dBm - link.Preq;

    P_rx_baseline_dBm = P_rx_ideal_dBm - L_atm_dB;
    base_margin_dB = P_rx_baseline_dBm - link.Preq;

    %% ---- 7. Full dynamic timeline ----
    margin_profile = base_margin_dB + L_tracking_dB;
    outage_indices = margin_profile < 0;
    outage_rate = (sum(outage_indices) / N) * 100;

    %% ---- 8. Render analytics ----
    fig = findobj('Type', 'figure', 'Name', 'Continuous Dynamic Performance Simulation Analytics');
    if isempty(fig)
        fig = figure('Name', 'Continuous Dynamic Performance Simulation Analytics', ...
            'Position', [450, 80, 900, 700]);
    else
        figure(fig); clf(fig);
        fig.Position = [450, 80, 900, 700];
    end

    layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'loose', 'Padding', 'loose');

    marginAxes = nexttile(layout, [1, 2]);
    plot(marginAxes, plotTime, margin_profile, 'b-', 'LineWidth', 1.5);
    hold(marginAxes, 'on');
    yline(marginAxes, 0, 'r--', 'Link Outage Threshold (Margin=0 dB)', ...
        'LineWidth', 1.5, 'LabelHorizontalAlignment', 'right');
    if link.Type == "inter-satellite"
        referenceLabel = sprintf('Reference: No Jitter Loss (%.1f dB)', ideal_margin_dB);
    else
        referenceLabel = sprintf( ...
            'Reference: No Atmospheric/Jitter Loss (%.1f dB)', ideal_margin_dB);
    end
    yline(marginAxes, ideal_margin_dB, '-.', referenceLabel, ...
        'Color', [0.00 0.50 0.15], 'LineWidth', 1.5, ...
        'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom');
    grid(marginAxes, 'on');
    if link.Type == "inter-satellite"
        title(marginAxes, sprintf('Dynamic Margin Profile (Model: %s)', jitterModel));
    else
        title(marginAxes, sprintf('Dynamic Margin Profile (Model: %s, Worst-case Elevation: %.1f deg)', ...
            jitterModel, elevationAngle));
    end
    xlabel(marginAxes, plotTimeLabel);
    ylabel(marginAxes, 'Link Margin Availability (dB)');
    profileMinimum = min([margin_profile, 0, ideal_margin_dB]);
    profileMaximum = max([margin_profile, 0, ideal_margin_dB]);
    ylim(marginAxes, [max(-100, profileMinimum-10), max(20, profileMaximum+10)]);

    pdfAxes = nexttile(layout);
    histogram(pdfAxes, margin_profile, 'Normalization', 'pdf', ...
        'FaceColor', [0.4660 0.6740 0.1880], 'EdgeColor', 'k');
    grid(pdfAxes, 'on');
    title(pdfAxes, 'Margin Probability Density Function (PDF)');
    xlabel(pdfAxes, 'Margin (dB)');
    ylabel(pdfAxes, 'PDF');

    outageAxes = nexttile(layout);
    bar(outageAxes, 1, outage_rate, 0.4, 'FaceColor', [0.8500 0.3250 0.0980]);
    grid(outageAxes, 'on');
    set(outageAxes, 'XTick', 1, 'XTickLabel', {'Time in Outage (%)'});
    title(outageAxes, 'Calculated Link Outage Rate');
    ylabel(outageAxes, 'Time in Outage (%)');
    ylim(outageAxes, [0 100]);
    text(outageAxes, 1, min(outage_rate + 5, 95), sprintf('%.1f%%', outage_rate), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
