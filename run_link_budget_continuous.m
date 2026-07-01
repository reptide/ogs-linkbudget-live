function run_link_budget_continuous(varargin)
% RUN_LINK_BUDGET_CONTINUOUS Simulates high-frequency tracking jitter distributions.
% Patched to correctly process micro-radian parameters shared from the GUI workspace.

    % 1. Pull the custom configuration structure from the base workspace
    try
        cfg = evalin('base', 'cfg');
    catch
        cfg = ogs_config(); % Fallback if called manually without GUI
    end

    % 2. Extract simulation time parameters
    duration = 60; 
    timeStep = 0.1;
    t = 0:timeStep:duration;
    N = length(t);

    % 3. Extract physical layer configurations
    P_tx = cfg.tx.Power;                        % Transmitter power (W)
    lambda = cfg.link.Wavelength;               % Operating wavelength (m)
    D_tx = cfg.tx.ApertureDiameter;             % Tx Aperture (m)
    D_rx = cfg.rx.ApertureDiameter;             % Rx Aperture (m)
    
    % Extract angular tracking jitter values
    sigma_sat = cfg.sat.JitterX;                % Satellite jitter (rad)
    sigma_ogs = cfg.ogs.JitterX;                % Ground jitter (rad)
    theta_bias = cfg.link.BoresightBias;        % Pointing bias (rad)

    % 4. Calculate proper Gaussian laser beam divergence width at ground target
    % Divergence half-angle (radians)
    theta_div = 1.22 * lambda / D_tx; 
    L_space = 36000000; % Nominal GEO link range scale (meters)
    w_z = L_space * theta_div; % Actual beam footprint radius at receiver (meters)

    % Combined total tracking alignment jitter variance
    sigma_total = sqrt(sigma_sat^2 + sigma_ogs^2);
    if sigma_total == 0, sigma_total = 1e-9; end % Evade zero division math bounds

    % 5. Generate random tracking misalignments across time matrix
    % Models pointing errors via standard Rayleigh/Rician components
    x_error = theta_bias + sigma_total * randn(1, N);
    y_error = sigma_total * randn(1, N);
    theta_pointing = sqrt(x_error.^2 + y_error.^2); % Radial tracking offset (rad)
    
    % Target displacement displacement distance offset (meters)
    r_displacement = L_space * theta_pointing;

    % 6. Calculate True Geometric Tracking Misalignment Fading Loss
    % FIXED: Normalized tracking attenuation factor profile calculation
    L_tracking_raw = exp(-2 * (r_displacement.^2) / (w_z^2));
    L_tracking_dB = 10 * log10(max(L_tracking_raw, 1e-30)); % Bound floor to -300dB max fade

    % 7. Establish Link Budget Static Baseline (Atmosphere, Path, Optics gains)
    % Clear sky atmospheric attenuation baseline loss bounds
    L_atm_dB = -3.0; 
    
    % Free space path loss calculation geometric model
    FSPL_dB = 20 * log10(lambda / (4 * pi * L_space));
    
    % Optical telescope aperture antenna gains
    G_tx = 10 * log10((pi * D_tx / lambda)^2);
    G_rx = 10 * log10((pi * D_rx / lambda)^2);
    
    % Combined total baseline margin excluding variable tracking losses
    P_rx_baseline_dBW = 10 * log10(P_tx) + G_tx + FSPL_dB + L_atm_dB + G_rx;
    Rx_Sensitivity_dBW = -90; % Minimum receiver optical threshold definition
    base_margin_dB = P_rx_baseline_dBW - Rx_Sensitivity_dBW;

    % 8. Build full dynamic timeline margin profile array
    margin_profile = base_margin_dB + L_tracking_dB;
    outage_indices = margin_profile < 0;
    outage_rate = (sum(outage_indices) / N) * 100;

    % ==========================================
    % 9. RENDER ANALYTICS GRAPHICAL INTERFACE
    % ==========================================
    fig = findobj('Type', 'figure', 'Name', 'Continuous Dynamic Performance Simulation Analytics');
    if isempty(fig)
        fig = figure('Name', 'Continuous Dynamic Performance Simulation Analytics', 'Position', [600, 100, 600, 500]);
    else
        figure(fig); clf(fig);
    end

    % Subplot 1: Link Margin Timeline Profile
    subplot(2, 2, [1, 2]);
    plot(t, margin_profile, 'b-', 'LineWidth', 1.5); hold on;
    yline(0, 'r--', 'Link Outage Threshold (Margin=0 dB)', 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'right');
    grid on;
    title('Dynamic Margin Profile (Model: Rayleigh (No Bias))');
    xlabel('Time (Seconds)');
    ylabel('Link Margin Availability (dB)');
    ylim([max(-100, min(margin_profile)-10), max(20, max(margin_profile)+10)]);

    % Subplot 2: Margin Probability Density Function Histogram
    subplot(2, 2, 3);
    histogram(margin_profile, 'Normalization', 'pdf', 'FaceColor', [0.4660 0.6740 0.1880], 'EdgeColor', 'k');
    grid on;
    title('Margin Probability Density Function (PDF)');
    xlabel('Margin (dB)');
    ylabel('PDF');

    % Subplot 3: Link Outage Rate Summary Chart
    subplot(2, 2, 4);
    bar(1, outage_rate, 0.4, 'FaceColor', [0.8500 0.3250 0.0980]);
    grid on;
    set(gca, 'XTick', 1, 'XTickLabel', {'Time in Outage (%)'});
    title('Calculated Link Outage Rate');
    ylabel('Time in Outage (%)');
    ylim([0 100]);
    text(1, outage_rate + 5, sprintf('%.1f%%', outage_rate), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end