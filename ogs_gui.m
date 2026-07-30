function ogs_gui()
%OGS_GUI Opens the scenario and hardware control panel for link simulations.
% The Run button converts UI values into the ogs_config schema and dispatches
% either a single snapshot or continuous tracking simulation.

    defaultCfg = ogs_config();

    fig = uifigure('Name', 'OGS Live Link Budget Control Panel', 'Position', [100, 80, 560, 760]);
    fig.Color = [0.96 0.96 0.98];

    %% ---- Main Navigation Tab Control Group ----
    tabGroup = uitabgroup(fig, 'Position', [20, 130, 520, 600]);

    tabScenario = uitab(tabGroup, 'Title', 'Scenario Settings');
    tabHardware = uitab(tabGroup, 'Title', 'Hardware Configuration');
    tabJitter = uitab(tabGroup, 'Title', 'Jitter Models');

    %% ==========================================
    %% TAB 1: SCENARIO SETTINGS LAYOUT
    %% ==========================================
    panelScenario = uipanel(tabScenario, 'Title', 'Link Orbit & Environment Profiles', ...
                          'Position', [15, 15, 490, 540], ...
                          'FontWeight', 'bold', 'FontSize', 11, 'BackgroundColor', [1 1 1]);

    uilabel(panelScenario, 'Position', [20, 490, 160, 22], 'Text', 'Link Direction:', 'HorizontalAlignment', 'right');
    linkTypeDrop = uidropdown(panelScenario, 'Position', [200, 490, 210, 22], 'Items', {'downlink', 'uplink', 'inter-satellite'});

    % Ground-space links are evaluated at this conservative design angle.
    uilabel(panelScenario, 'Position', [10, 450, 170, 22], 'Text', 'Worst-case Elevation (deg):', 'HorizontalAlignment', 'right');
    elevSpinner = uispinner(panelScenario, 'Position', [200, 450, 100, 22], ...
        'Limits', [5, 90], 'Value', defaultCfg.orbit.WorstCaseElevationAngle);

    uilabel(panelScenario, 'Position', [20, 410, 160, 22], 'Text', 'Atmosphere Data:', 'HorizontalAlignment', 'right');
    weatherSwitch = uiswitch(panelScenario, 'slider', 'Position', [255, 413, 45, 20], 'Items', {'Live API', 'Manual'});

    % Direct Geodetic Coordinate Input Fields
    uilabel(panelScenario, 'Position', [20, 370, 160, 22], 'Text', 'Station Latitude (deg N):', 'HorizontalAlignment', 'right');
    latField = uieditfield(panelScenario, 'numeric', 'Position', [200, 370, 100, 22], 'Limits', [-90, 90], 'Value', 36.3504);

    uilabel(panelScenario, 'Position', [20, 330, 160, 22], 'Text', 'Station Longitude (deg E):', 'HorizontalAlignment', 'right');
    lonField = uieditfield(panelScenario, 'numeric', 'Position', [200, 330, 100, 22], 'Limits', [-180, 180], 'Value', 127.3845);

    uilabel(panelScenario, 'Position', [20, 290, 160, 22], 'Text', 'Station Alt AMSL (m):', 'HorizontalAlignment', 'right');
    altField = uieditfield(panelScenario, 'numeric', 'Position', [200, 290, 100, 22], 'Limits', [0, 9000], 'Value', 100);

    uilabel(panelScenario, 'Position', [20, 245, 160, 22], 'Text', 'Simulation Mode:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    modeGroup = uibuttongroup(panelScenario, 'Position', [200, 225, 240, 55], 'BorderType', 'none', 'BackgroundColor', [1 1 1]);
    radioSingle = uiradiobutton(modeGroup, 'Text', 'Single Snapshot', 'Position', [10, 30, 150, 22], 'FontWeight', 'bold');
    radioCont   = uiradiobutton(modeGroup, 'Text', 'Continuous Tracking', 'Position', [10, 5, 150, 22]);

    subPanel = uipanel(panelScenario, 'Title', 'Continuous Simulation Sub-settings', ...
                       'Position', [15, 10, 460, 200], ...
                       'BackgroundColor', [0.95 0.95 0.95], 'ForegroundColor', [0.5 0.5 0.5]);

    uilabel(subPanel, 'Position', [15, 145, 150, 22], 'Text', 'Live Weather Timeline:', 'HorizontalAlignment', 'right');
    weatherTimelineSwitch = uiswitch(subPanel, 'slider', 'Position', [255, 148, 45, 20], ...
        'Items', {'Past Replay', 'Current Hold'}, 'Value', defaultCfg.weather.ContinuousMode, ...
        'Enable', 'off');

    uilabel(subPanel, 'Position', [15, 95, 150, 22], 'Text', 'Duration (minutes):', 'HorizontalAlignment', 'right');
    durSpinner = uispinner(subPanel, 'Position', [180, 95, 90, 22], 'Limits', [1, 60], 'Value', 1, 'Enable', 'off');

    stepValueHidden = 0.1;

    %% ==========================================
    %% TAB 2: HARDWARE CONFIGURATION LAYOUT
    %% ==========================================
    panelHardware = uipanel(tabHardware, 'Title', 'Physical Layer Laser & Optics Specs', ...
                          'Position', [15, 15, 490, 540], ...
                          'FontWeight', 'bold', 'FontSize', 11, 'BackgroundColor', [1 1 1]);

    uilabel(panelHardware, 'Position', [20, 480, 180, 22], 'Text', 'Tx Laser Power (W):', 'HorizontalAlignment', 'right');
    txPowerSpinner = uispinner(panelHardware, 'Position', [220, 480, 100, 22], 'Limits', [0.01, 100], 'Value', 10.0, 'Step', 0.5);

    uilabel(panelHardware, 'Position', [20, 440, 180, 22], 'Text', 'Wavelength (nm):', 'HorizontalAlignment', 'right');
    wavelengthSpinner = uispinner(panelHardware, 'Position', [220, 440, 100, 22], 'Limits', [400, 2000], 'Value', 1550, 'Step', 10);

    uilabel(panelHardware, 'Position', [20, 380, 180, 22], 'Text', 'Tx Aperture Diameter (m):', 'HorizontalAlignment', 'right');
    txDiamSpinner = uispinner(panelHardware, 'Position', [220, 380, 100, 22], 'Limits', [0.01, 2.0], 'Value', 0.3, 'Step', 0.01);

    uilabel(panelHardware, 'Position', [20, 340, 180, 22], 'Text', 'Rx Aperture Diameter (m):', 'HorizontalAlignment', 'right');
    rxDiamSpinner = uispinner(panelHardware, 'Position', [220, 340, 100, 22], 'Limits', [0.01, 10.0], 'Value', 0.3, 'Step', 0.01);

    satJitterLabel = uilabel(panelHardware, 'Position', [20, 280, 180, 22], 'Text', 'Satellite Jitter (urad):', 'HorizontalAlignment', 'right');
    satJitterSpinner = uispinner(panelHardware, 'Position', [220, 280, 100, 22], 'Limits', [0.0, 50.0], 'Value', 2.0, 'Step', 0.05);

    secondJitterLabel = uilabel(panelHardware, 'Position', [20, 240, 180, 22], 'Text', 'Ground Jitter (urad):', 'HorizontalAlignment', 'right');
    ogsJitterSpinner = uispinner(panelHardware, 'Position', [220, 240, 100, 22], 'Limits', [0.0, 50.0], 'Value', 1.0, 'Step', 0.001);

    uilabel(panelHardware, 'Position', [20, 200, 180, 22], 'Text', 'Boresight Bias (urad):', 'HorizontalAlignment', 'right');
    biasSpinner = uispinner(panelHardware, 'Position', [220, 200, 100, 22], 'Limits', [0.0, 20.0], 'Value', 0.0, 'Step', 0.05);

    uilabel(panelHardware, 'Position', [10, 150, 190, 22], ...
        'Text', 'Required Operational Margin (dB):', 'HorizontalAlignment', 'right');
    outageMarginSpinner = uispinner(panelHardware, 'Position', [220, 150, 100, 22], ...
        'Limits', [0.0, 30.0], 'Value', defaultCfg.link.OutageMarginDB, 'Step', 0.5);

    %% ==========================================
    %% TAB 3: JITTER MODEL LAYOUT
    %% ==========================================
    jitterPanel = uipanel(tabJitter, 'Title', 'Terminal Jitter Profiles & Suppression', ...
        'Position', [15, 15, 490, 540], 'FontWeight', 'bold', ...
        'FontSize', 11, 'BackgroundColor', [0.95 0.95 0.95], ...
        'ForegroundColor', [0.5 0.5 0.5]);

    uilabel(jitterPanel, 'Position', [25, 455, 440, 48], ...
        'Text', ['Select a platform or residual ATP profile independently for each ' ...
                 'terminal. Suppression represents optional additional isolation.'], ...
        'WordWrap', 'on');

    jitterProfiles = { ...
        'Configured Random', ...
        'OLYMPUS Platform PSD (Open Loop)', ...
        'OLYMPUS After ATP (Reference Design)', ...
        'Micius Before ATP (Open Loop)', ...
        'Micius After ATP (Measured)'};
    uilabel(jitterPanel, 'Position', [20, 390, 150, 22], ...
        'Text', 'Tx Jitter Profile:', 'HorizontalAlignment', 'right');
    txJitterDrop = uidropdown(jitterPanel, 'Position', [185, 390, 270, 22], ...
        'Items', jitterProfiles, 'Enable', 'off');

    uilabel(jitterPanel, 'Position', [20, 345, 150, 22], ...
        'Text', 'Rx Jitter Profile:', 'HorizontalAlignment', 'right');
    rxJitterDrop = uidropdown(jitterPanel, 'Position', [185, 345, 270, 22], ...
        'Items', jitterProfiles, 'Enable', 'off');

    uilabel(jitterPanel, 'Position', [10, 270, 180, 22], ...
        'Text', 'Additional Tx Suppression (dB):', 'HorizontalAlignment', 'right');
    txSuppressionSpinner = uispinner(jitterPanel, 'Position', [205, 270, 100, 22], ...
        'Limits', [0.0, 60.0], 'Value', defaultCfg.link.TxJitterSuppressionDB, ...
        'Step', 1, 'Enable', 'off');

    uilabel(jitterPanel, 'Position', [10, 225, 180, 22], ...
        'Text', 'Additional Rx Suppression (dB):', 'HorizontalAlignment', 'right');
    rxSuppressionSpinner = uispinner(jitterPanel, 'Position', [205, 225, 100, 22], ...
        'Limits', [0.0, 60.0], 'Value', defaultCfg.link.RxJitterSuppressionDB, ...
        'Step', 1, 'Enable', 'off');

    uilabel(jitterPanel, 'Position', [35, 105, 420, 75], ...
        'Text', ['After-ATP profiles already contain the residual tracking error. ' ...
                 'Leave suppression at 0 dB to reproduce them; a nonzero value ' ...
                 'adds hypothetical frequency-independent suppression.'], ...
        'WordWrap', 'on', 'FontAngle', 'italic');

    %% ---- Dynamic Mode Callbacks ----
    modeGroup.SelectionChangedFcn = @(bg, event) toggleContinuousFields( ...
        event.NewValue, durSpinner, txJitterDrop, rxJitterDrop, weatherTimelineSwitch, ...
        txSuppressionSpinner, rxSuppressionSpinner, subPanel, jitterPanel, ...
        radioSingle, radioCont);
    linkTypeDrop.ValueChangedFcn = @(drop, event) updateJitterLabels( ...
        drop.Value, satJitterLabel, secondJitterLabel);

    %% ---- Main Simulation Trigger Button ----
    runBtn = uibutton(fig, 'push', 'Text', '⚡ RUN LINK BUDGET', ...
        'Position', [20, 55, 520, 50], ...
        'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', [0.0 0.45 0.74], 'FontColor', 'white');

    runBtn.ButtonPushedFcn = @(btn, event) executeLinkBudget(...
        linkTypeDrop.Value, elevSpinner.Value, weatherSwitch.Value, latField.Value, lonField.Value, altField.Value, ...
        radioCont.Value, durSpinner.Value * 60, stepValueHidden, txJitterDrop.Value, rxJitterDrop.Value, ...
        weatherTimelineSwitch.Value, ...
        txPowerSpinner.Value, wavelengthSpinner.Value, txDiamSpinner.Value, rxDiamSpinner.Value, ...
        satJitterSpinner.Value, ogsJitterSpinner.Value, biasSpinner.Value, ...
        txSuppressionSpinner.Value, rxSuppressionSpinner.Value, outageMarginSpinner.Value);

    uilabel(fig, 'Position', [25, 15, 510, 22], 'Text', 'Status: Control panel ready.', 'FontAngle', 'italic', 'Tag', 'StatusBar');
end

function updateJitterLabels(linkType, satJitterLabel, secondJitterLabel)
%UPDATEJITTERLABELS Identifies the physical terminals represented by jitter controls.

    if string(linkType) == "inter-satellite"
        satJitterLabel.Text = 'Satellite A Jitter (urad):';
        secondJitterLabel.Text = 'Satellite B Jitter (urad):';
    else
        satJitterLabel.Text = 'Satellite Jitter (urad):';
        secondJitterLabel.Text = 'Ground Jitter (urad):';
    end
end

function toggleContinuousFields(selectedButton, durSpinner, txJitterDrop, rxJitterDrop, weatherTimelineSwitch, txSuppressionSpinner, rxSuppressionSpinner, subPanel, jitterPanel, radioSingle, radioCont)
%TOGGLECONTINUOUSFIELDS Enables time-series controls in continuous mode.

    if strcmp(selectedButton.Text, 'Continuous Tracking')
        durSpinner.Enable = 'on';
        txJitterDrop.Enable = 'on';
        rxJitterDrop.Enable = 'on';
        txSuppressionSpinner.Enable = 'on';
        rxSuppressionSpinner.Enable = 'on';
        weatherTimelineSwitch.Enable = 'on';
        subPanel.BackgroundColor = [0.90 0.95 1.00];
        subPanel.ForegroundColor = [0.00 0.25 0.50];
        jitterPanel.BackgroundColor = [0.90 0.95 1.00];
        jitterPanel.ForegroundColor = [0.00 0.25 0.50];
        radioCont.FontWeight = 'bold';
        radioSingle.FontWeight = 'normal';
    else
        durSpinner.Enable = 'off';
        txJitterDrop.Enable = 'off';
        rxJitterDrop.Enable = 'off';
        txSuppressionSpinner.Enable = 'off';
        rxSuppressionSpinner.Enable = 'off';
        weatherTimelineSwitch.Enable = 'off';
        subPanel.BackgroundColor = [0.95 0.95 0.95];
        subPanel.ForegroundColor = [0.50 0.50 0.50];
        jitterPanel.BackgroundColor = [0.95 0.95 0.95];
        jitterPanel.ForegroundColor = [0.50 0.50 0.50];
        radioCont.FontWeight = 'normal';
        radioSingle.FontWeight = 'bold';
    end
end

function executeLinkBudget(linkType, worstCaseElevation, weatherMode, lat, lon, altMeters, isContinuous, duration, timeStep, txJitterProfile, rxJitterProfile, weatherTimelineMode, ...
                           txPowerW, wavelengthNm, D_tx, D_rx, satJitterUrad, ogsJitterUrad, boresightBiasUrad, txSuppressionDB, rxSuppressionDB, outageMarginDB)
%EXECUTELINKBUDGET Maps UI values to configuration fields and runs the selected engine.

    cfg = ogs_config();

    % ---- Scenario configuration ----
    cfg.link.Type = linkType;
    cfg.orbit.WorstCaseElevationAngle = worstCaseElevation;
    cfg.weather.UseLive = strcmp(weatherMode, 'Live API');
    cfg.weather.ContinuousMode = weatherTimelineMode;

    cfg.gs.Latitude  = lat;
    cfg.gs.Longitude = lon;
    cfg.gs.Height    = altMeters / 1000;  % m -> km, matches ogs_config.m units

    % ---- Hardware configuration ----
    cfg.link.Ptx = 10*log10(txPowerW * 1000);  % W -> dBm, matches link.Ptx convention
    cfg.link.Wavelength = wavelengthNm * 1e-9; % nm -> m

    % Tx/Rx aperture controls map to the physical terminals for the
    % selected link direction.
    if cfg.link.Type == "uplink"
        cfg.gs.ApertureDiameter   = D_tx;
        cfg.satA.ApertureDiameter = D_rx;
    elseif cfg.link.Type == "inter-satellite"
        cfg.satA.ApertureDiameter = D_tx;
        cfg.satB.ApertureDiameter = D_rx;
    else
        cfg.satA.ApertureDiameter = D_tx;
        cfg.gs.ApertureDiameter   = D_rx;
    end

    cfg.satA.JitterSigma = satJitterUrad * 1e-6;
    if cfg.link.Type == "inter-satellite"
        cfg.satB.JitterSigma = ogsJitterUrad * 1e-6;
    else
        cfg.gs.JitterSigma = ogsJitterUrad * 1e-6;
    end
    cfg.link.BoresightBias = boresightBiasUrad * 1e-6;
    cfg.link.TxJitterSuppressionDB = txSuppressionDB;
    cfg.link.RxJitterSuppressionDB = rxSuppressionDB;
    cfg.link.OutageMarginDB = outageMarginDB;

    assignin('base', 'cfg', cfg);

    if ~isContinuous
        run_link_budget_live(cfg);
    else
        run_link_budget_continuous(cfg, duration, timeStep, txJitterProfile, rxJitterProfile);
    end
end
