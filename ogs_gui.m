function ogs_gui()
% OGS_GUI Advanced Multi-Tab Control Panel for Optical Link Budgets
% Cleaned template with direct Geodetic Coordinate Overrides and workspace variable sync.

    % Initialize professional dashboard layout window frame
    fig = uifigure('Name', 'OGS Live Link Budget Control Panel', 'Position', [100, 100, 520, 660]);
    fig.Color = [0.96 0.96 0.98];
    
    %% ---- Main Navigation Tab Control Group ----
    tabGroup = uitabgroup(fig, 'Position', [20, 130, 480, 500]);
    
    tabScenario = uitab(tabGroup, 'Title', 'Scenario Settings');
    tabHardware = uitab(tabGroup, 'Title', 'Hardware Configuration');
    
    %% ==========================================
    %% TAB 1: SCENARIO SETTINGS LAYOUT
    %% ==========================================
    panelScenario = uipanel(tabScenario, 'Title', 'Link Orbit & Environment Profiles', ...
                          'Position', [15, 15, 450, 440], ...
                          'FontWeight', 'bold', 'FontSize', 11, 'BackgroundColor', [1 1 1]);
    
    uilabel(panelScenario, 'Position', [20, 390, 140, 22], 'Text', 'Link Direction:', 'HorizontalAlignment', 'right');
    linkTypeDrop = uidropdown(panelScenario, 'Position', [180, 390, 180, 22], 'Items', {'downlink', 'uplink', 'inter-satellite'});
    
    uilabel(panelScenario, 'Position', [20, 350, 140, 22], 'Text', 'Min Elevation Floor (deg):', 'HorizontalAlignment', 'right');
    elevSpinner = uispinner(panelScenario, 'Position', [180, 350, 100, 22], 'Limits', [5, 90], 'Value', 20);

    uilabel(panelScenario, 'Position', [20, 310, 140, 22], 'Text', 'Atmosphere Data:', 'HorizontalAlignment', 'right');
    weatherSwitch = uiswitch(panelScenario, 'slider', 'Position', [235, 313, 45, 20], 'Items', {'Live API', 'Manual'});
    
    % Direct Geodetic Coordinate Input Fields
    uilabel(panelScenario, 'Position', [20, 270, 140, 22], 'Text', 'Station Latitude (deg N):', 'HorizontalAlignment', 'right');
    latField = uieditfield(panelScenario, 'numeric', 'Position', [180, 270, 100, 22], 'Limits', [-90, 90], 'Value', 20.71);
    
    uilabel(panelScenario, 'Position', [20, 230, 140, 22], 'Text', 'Station Longitude (deg E):', 'HorizontalAlignment', 'right');
    lonField = uieditfield(panelScenario, 'numeric', 'Position', [180, 230, 100, 22], 'Limits', [-180, 180], 'Value', -156.25);
    
    uilabel(panelScenario, 'Position', [20, 190, 140, 22], 'Text', 'Station Alt AMSL (m):', 'HorizontalAlignment', 'right');
    altField = uieditfield(panelScenario, 'numeric', 'Position', [180, 190, 100, 22], 'Limits', [0, 9000], 'Value', 3052);
    
    uilabel(panelScenario, 'Position', [20, 145, 140, 22], 'Text', 'Simulation Mode:', 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
    modeGroup = uibuttongroup(panelScenario, 'Position', [180, 125, 240, 55], 'BorderType', 'none', 'BackgroundColor', [1 1 1]);
    radioSingle = uiradiobutton(modeGroup, 'Text', 'Single Snapshot', 'Position', [10, 30, 150, 22], 'FontWeight', 'bold');
    radioCont   = uiradiobutton(modeGroup, 'Text', 'Continuous Tracking', 'Position', [10, 5, 150, 22]);
    
    % Continuous Sub-settings Container Panel
    subPanel = uipanel(panelScenario, 'Title', 'Continuous Simulation Sub-settings', ...
                       'Position', [15, 10, 420, 110], ...
                       'BackgroundColor', [0.95 0.95 0.95], 'ForegroundColor', [0.5 0.5 0.5]);
    
    uilabel(subPanel, 'Position', [15, 60, 130, 22], 'Text', 'Jitter Model:', 'HorizontalAlignment', 'right');
    jitterModelDrop = uidropdown(subPanel, 'Position', [160, 60, 180, 22], 'Items', {'Rayleigh (No Bias)', 'Rician (With Bias)'}, 'Enable', 'off');

    uilabel(subPanel, 'Position', [15, 20, 130, 22], 'Text', 'Duration (seconds):', 'HorizontalAlignment', 'right');
    durSpinner = uispinner(subPanel, 'Position', [160, 20, 90, 22], 'Limits', [1, 3600], 'Value', 60, 'Enable', 'off');
    
    stepValueHidden = 0.1;

    %% ==========================================
    %% TAB 2: HARDWARE CONFIGURATION LAYOUT
    %% ==========================================
    panelHardware = uipanel(tabHardware, 'Title', 'Physical Layer Laser & Optics Specs', ...
                          'Position', [15, 15, 450, 440], ...
                          'FontWeight', 'bold', 'FontSize', 11, 'BackgroundColor', [1 1 1]);
                      
    uilabel(panelHardware, 'Position', [20, 380, 160, 22], 'Text', 'Tx Laser Power (W):', 'HorizontalAlignment', 'right');
    txPowerSpinner = uispinner(panelHardware, 'Position', [200, 380, 100, 22], 'Limits', [0.01, 100], 'Value', 10.0, 'Step', 0.5);
    
    uilabel(panelHardware, 'Position', [20, 340, 160, 22], 'Text', 'Wavelength (nm):', 'HorizontalAlignment', 'right');
    wavelengthSpinner = uispinner(panelHardware, 'Position', [200, 340, 100, 22], 'Limits', [400, 2000], 'Value', 1550, 'Step', 10);
    
    uilabel(panelHardware, 'Position', [20, 280, 160, 22], 'Text', 'Tx Aperture Diameter (m):', 'HorizontalAlignment', 'right');
    txDiamSpinner = uispinner(panelHardware, 'Position', [200, 280, 100, 22], 'Limits', [0.01, 2.0], 'Value', 0.3, 'Step', 0.01);
    
    uilabel(panelHardware, 'Position', [20, 240, 160, 22], 'Text', 'Rx Aperture Diameter (m):', 'HorizontalAlignment', 'right');
    rxDiamSpinner = uispinner(panelHardware, 'Position', [200, 240, 100, 22], 'Limits', [0.01, 10.0], 'Value', 0.3, 'Step', 0.01);
    
    uilabel(panelHardware, 'Position', [20, 180, 160, 22], 'Text', 'Satellite Jitter (urad):', 'HorizontalAlignment', 'right');
    satJitterSpinner = uispinner(panelHardware, 'Position', [200, 180, 100, 22], 'Limits', [0.0, 50.0], 'Value', 2.0, 'Step', 0.05);
    
    uilabel(panelHardware, 'Position', [20, 140, 160, 22], 'Text', 'Ground Jitter (urad):', 'HorizontalAlignment', 'right');
    ogsJitterSpinner = uispinner(panelHardware, 'Position', [200, 140, 100, 22], 'Limits', [0.0, 50.0], 'Value', 1.0, 'Step', 0.001);
    
    uilabel(panelHardware, 'Position', [20, 100, 160, 22], 'Text', 'Boresight Bias (urad):', 'HorizontalAlignment', 'right');
    biasSpinner = uispinner(panelHardware, 'Position', [200, 100, 100, 22], 'Limits', [0.0, 20.0], 'Value', 0.0, 'Step', 0.05);

    %% ---- Dynamic Mode Callbacks ----
    modeGroup.SelectionChangedFcn = @(bg, event) toggleContinuousFields(event.NewValue, durSpinner, jitterModelDrop, subPanel, radioSingle, radioCont);
    
    %% ---- Main Simulation Trigger Button ----
    runBtn = uibutton(fig, 'push', 'Text', '⚡ RUN LINK BUDGET', ...
        'Position', [20, 55, 480, 50], ...
        'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', [0.0 0.45 0.74], 'FontColor', 'white');
    
    runBtn.ButtonPushedFcn = @(btn, event) executeLinkBudget(...
        linkTypeDrop.Value, elevSpinner.Value, weatherSwitch.Value, latField.Value, lonField.Value, altField.Value, ...
        radioCont.Value, durSpinner.Value, stepValueHidden, jitterModelDrop.Value, ...
        txPowerSpinner.Value, wavelengthSpinner.Value, txDiamSpinner.Value, rxDiamSpinner.Value, ...
        satJitterSpinner.Value, ogsJitterSpinner.Value, biasSpinner.Value);

    uilabel(fig, 'Position', [25, 15, 470, 22], 'Text', 'Status: Control panel ready.', 'FontAngle', 'italic', 'Tag', 'StatusBar');
end

function toggleContinuousFields(selectedButton, durSpinner, jitterModelDrop, subPanel, radioSingle, radioCont)
    if strcmp(selectedButton.Text, 'Continuous Tracking')
        durSpinner.Enable = 'on';
        jitterModelDrop.Enable = 'on';
        subPanel.BackgroundColor = [0.90 0.95 1.00];
        subPanel.ForegroundColor = [0.00 0.25 0.50];
        radioCont.FontWeight = 'bold';
        radioSingle.FontWeight = 'normal';
    else
        durSpinner.Enable = 'off';
        jitterModelDrop.Enable = 'off';
        subPanel.BackgroundColor = [0.95 0.95 0.95];
        subPanel.ForegroundColor = [0.50 0.50 0.50];
        radioCont.FontWeight = 'normal';
        radioSingle.FontWeight = 'bold';
    end
end

function executeLinkBudget(linkType, elevation, weatherMode, lat, lon, alt, isContinuous, duration, timeStep, jitterModel, ...
                           txPower, wavelength, D_tx, D_rx, satJitter, ogsJitter, boresightBias)
    
    cfg = ogs_config();
    
    % Parse control panels values directly into our runtime memory variables
    cfg.link.Type = linkType;
    cfg.orbit.FixedElevationAngle = elevation;
    cfg.weather.UseLive = strcmp(weatherMode, 'Live API');
    
    cfg.site.Latitude = lat;
    cfg.site.Longitude = lon;
    cfg.site.Elevation = alt;
    cfg.site.Name = sprintf('Custom (%.2f N, %.2f E)', lat, lon);
    
    cfg.tx.Power = txPower;
    cfg.link.Wavelength = wavelength * 1e-9; 
    cfg.tx.ApertureDiameter = D_tx;
    cfg.rx.ApertureDiameter = D_rx;
    
    cfg.sat.JitterX = satJitter * 1e-6;
    cfg.sat.JitterY = satJitter * 1e-6;
    cfg.ogs.JitterX = ogsJitter * 1e-6;
    cfg.ogs.JitterY = ogsJitter * 1e-6;
    cfg.link.BoresightBias = boresightBias * 1e-6;
    
    % FORCE FIX: Assign configuration values to the base workspace memory map
    assignin('base', 'cfg', cfg);
    
    if ~isContinuous
        run_link_budget_live(cfg);
    else
        try
            run_link_budget_continuous(cfg, duration, timeStep, jitterModel);
        catch
            run_link_budget_continuous(duration, timeStep, jitterModel);
        end
    end
end