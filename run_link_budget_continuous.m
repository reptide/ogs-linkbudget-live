function run_link_budget_continuous(cfg, duration, timeStep, jitterModel)
% RUN_LINK_BUDGET_CONTINUOUS Simulates high-frequency tracking jitter distributions.
%
%   run_link_budget_continuous(cfg, duration, timeStep, jitterModel)
%
%   Fixes vs. previous version:
%     - duration/timeStep/jitterModel are actually used now (previously
%       hardcoded to 60s/0.1s and a fixed "Rayleigh" title regardless of
%       what was passed in).
%     - Reads the unified cfg.gs/cfg.satA/cfg.link schema (previously read
%       cfg.tx/cfg.rx/cfg.sat/cfg.ogs/cfg.site, which ogs_config.m never
%       defined - only worked when the GUI's assignin('base',...) happened
%       to populate those exact field names).
%     - Atmosphere loss now calls compute_atmospheric_loss.m (the same
%       physics run_link_budget_live.m uses) driven by cfg.weather, instead
%       of a hardcoded -3.0 dB placeholder that ignored the Live/Manual
%       switch entirely.
%     - Slant range uses slantRangeCircularOrbit with the actual satA.Height
%       and orbit.FixedElevationAngle (previously hardcoded a 36,000 km GEO
%       range regardless of the configured LEO altitude).
%     - Rayleigh vs. Rician selection now actually changes the simulated
%       distribution: Rayleigh forces zero mean offset; Rician applies
%       link.BoresightBias as the mean offset. Previously both dropdown
%       choices produced identical output because the value was never read.
%     - Link margin arithmetic is dBm-consistent throughout, matching
%       run_link_budget_live.m (link.Ptx and link.Preq are both dBm).

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
    link = cfg.link;

    t = 0:timeStep:duration;
    N = length(t);

    %% ---- 1. Physical layer configuration (unified schema) ----
    lambda = link.Wavelength;             % m
    D_tx = satA.ApertureDiameter;         % m
    D_rx = gs.ApertureDiameter;           % m

    sigma_sat = satA.JitterSigma;         % rad, dynamic tracking jitter
    sigma_ogs = gs.JitterSigma;           % rad, dynamic tracking jitter

    isRician = contains(jitterModel, 'Rician', 'IgnoreCase', true);
    if isRician
        theta_bias = link.BoresightBias;  % rad, nonzero mean offset
    else
        theta_bias = 0;                   % Rayleigh: zero mean by definition
    end

    %% ---- 2. Real pass geometry (LEO slant range, not a fixed GEO assumption) ----
    elevationAngle = cfg.orbit.FixedElevationAngle;
    L_space = slantRangeCircularOrbit(elevationAngle, satA.Height*1e3, gs.Height*1e3); % meters

    %% ---- 3. Beam divergence / footprint at the receiver ----
    theta_div = 1.22 * lambda / D_tx;      % diffraction-limited half-angle, rad
    w_z = L_space * theta_div;             % beam footprint radius at receiver, m

    sigma_total = sqrt(sigma_sat^2 + sigma_ogs^2);
    if sigma_total == 0, sigma_total = 1e-9; end % avoid zero-division

    %% ---- 4. Generate random tracking misalignments across the pass ----
    x_error = theta_bias + sigma_total * randn(1, N);
    y_error = sigma_total * randn(1, N);
    theta_pointing = sqrt(x_error.^2 + y_error.^2);  % radial tracking offset, rad
    r_displacement = L_space * theta_pointing;        % m

    L_tracking_raw = exp(-2 * (r_displacement.^2) / (w_z^2));
    L_tracking_dB = 10 * log10(max(L_tracking_raw, 1e-30)); % floor at -300 dB

    %% ---- 5. Atmosphere (live or manual, same physics as the snapshot engine) ----
    if cfg.weather.UseLive
        w = fetch_live_weather(gs.Latitude, gs.Longitude);
        visibility = w.VisibilityKm;
        attenuationType = w.AttenuationType;
        fprintf("Continuous sim atmosphere: LIVE (%.2f km visibility, %s)\n", visibility, attenuationType);
    else
        visibility = cfg.weather.Manual.VisibilityKm;
        attenuationType = cfg.weather.Manual.AttenuationType;
        fprintf("Continuous sim atmosphere: MANUAL (%.2f km visibility, %s)\n", visibility, attenuationType);
    end

    L_atm_dB = compute_atmospheric_loss(visibility, attenuationType, elevationAngle, ...
        gs.Height, lambda, link.TroposphereHeight, link.AbsorptionLoss);

    %% ---- 6. Static baseline margin (dBm-consistent) ----
    FSPL_dB = fspl(L_space, lambda);  % positive-convention path loss, dB
    G_tx = 10*log10((pi*D_tx/lambda)^2);
    G_rx = 10*log10((pi*D_rx/lambda)^2);

    P_rx_baseline_dBm = link.Ptx + 10*log10(satA.OpticsEfficiency) + 10*log10(gs.OpticsEfficiency) + ...
        G_tx + G_rx - FSPL_dB - L_atm_dB;
    base_margin_dB = P_rx_baseline_dBm - link.Preq;

    %% ---- 7. Full dynamic timeline ----
    margin_profile = base_margin_dB + L_tracking_dB;
    outage_indices = margin_profile < 0;
    outage_rate = (sum(outage_indices) / N) * 100;

    %% ---- 8. Render analytics ----
    fig = findobj('Type', 'figure', 'Name', 'Continuous Dynamic Performance Simulation Analytics');
    if isempty(fig)
        fig = figure('Name', 'Continuous Dynamic Performance Simulation Analytics', 'Position', [600, 100, 600, 500]);
    else
        figure(fig); clf(fig);
    end

    subplot(2, 2, [1, 2]);
    plot(t, margin_profile, 'b-', 'LineWidth', 1.5); hold on;
    yline(0, 'r--', 'Link Outage Threshold (Margin=0 dB)', 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'right');
    grid on;
    title(sprintf('Dynamic Margin Profile (Model: %s)', jitterModel));
    xlabel('Time (Seconds)');
    ylabel('Link Margin Availability (dB)');
    ylim([max(-100, min(margin_profile)-10), max(20, max(margin_profile)+10)]);

    subplot(2, 2, 3);
    histogram(margin_profile, 'Normalization', 'pdf', 'FaceColor', [0.4660 0.6740 0.1880], 'EdgeColor', 'k');
    grid on;
    title('Margin Probability Density Function (PDF)');
    xlabel('Margin (dB)');
    ylabel('PDF');

    subplot(2, 2, 4);
    bar(1, outage_rate, 0.4, 'FaceColor', [0.8500 0.3250 0.0980]);
    grid on;
    set(gca, 'XTick', 1, 'XTickLabel', {'Time in Outage (%)'});
    title('Calculated Link Outage Rate');
    ylabel('Time in Outage (%)');
    ylim([0 100]);
    text(1, outage_rate + 5, sprintf('%.1f%%', outage_rate), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
