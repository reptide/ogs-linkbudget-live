function ogs_gui()
% OGS_GUI Interactive Control Panel for Optical Link Budget
% Integrates live weather parameters, single snapshot runs, and time-series simulations.

    % Initialize application window interface
    fig = uifigure('Name', 'OGS Live Link Budget Control Panel', 'Position', [100, 100, 480, 500]);
    
    %% ---- Configuration & Inputs UI Group ----
    panel = uipanel(fig, 'Title', 'Link Configuration Parameters', 'Position', [20, 140, 440, 340]);
    
    % Link direction toggle selection
    uilabel(panel, 'Position', [20, 280, 120, 22], 'Text', 'Link Direction:');
    linkTypeDrop = uidropdown(panel, 'Position', [160, 280, 150, 22], 'Items', {'downlink', 'uplink', 'inter-satellite'});
    
    % Elevation input selection parameters
    uilabel(panel, 'Position', [20, 240, 120, 22], 'Text', 'Elevation Angle (deg):');
    elevSpinner = uispinner(panel, 'Position', [160, 240, 100, 22], 'Limits', [5, 90], 'Value', 50);

    % Real-time weather API selector
    uilabel(panel, 'Position', [20, 200, 120, 22], 'Text', 'Atmosphere Data:');
    weatherSwitch = uiswitch(panel, 'slider', 'Position', [160, 205, 45, 20], 'Items', {'Live API', 'Manual'});
    
    % Core processing operation modes
    uilabel(panel, 'Position', [20, 140, 120, 22], 'Text', 'Simulation Mode:', 'FontWeight', 'bold');
    modeGroup = uibuttongroup(panel, 'Position', [160, 115, 250, 55], 'BorderType', 'none');
    radioSingle = uiradiobutton(modeGroup, 'Text', 'Single Snapshot', 'Position', [10, 30, 150, 22]);
    radioCont   = uiradiobutton(modeGroup, 'Text', 'Continuous Tracking', 'Position', [10, 5, 150, 22]);
    
    % Time dimensions configuration inputs (Conditional logic controlled)
    uilabel(panel, 'Position', [40, 70, 120, 22], 'Text', 'Duration (seconds):');
    durSpinner = uispinner(panel, 'Position', [160, 70, 80, 22], 'Limits', [1, 3600], 'Value', 60, 'Enable', 'off');
    
    uilabel(panel, 'Position', [40, 30, 120, 22], 'Text', 'Time Step (seconds):');
    stepSpinner = uispinner(panel, 'Position', [160, 30, 80, 22], 'Limits', [0.01, 10], 'Value', 0.1, 'Enable', 'off');

    %% ---- Dynamic Visibility Control States ----
    modeGroup.SelectionChangedFcn = @(bg, event) toggleContinuousFields(event.NewValue, durSpinner, stepSpinner);
    
    %% ---- Main Simulation Trigger ----
    runBtn = uibutton(fig, 'push', 'Text', '⚡ RUN LINK BUDGET', ...
        'Position', [20, 75, 440, 45], ...
        'FontSize', 14, 'FontWeight', 'bold', 'BackgroundColor', [0 0.45 0.74], 'FontColor', 'white');
    runBtn.ButtonPushedFcn = @(btn, event) executeLinkBudget(...
        linkTypeDrop.Value, elevSpinner.Value, weatherSwitch.Value, ...
        radioCont.Value, durSpinner.Value, stepSpinner.Value);

    uilabel(fig, 'Position', [20, 20, 440, 22], 'Text', 'Status: Ready to compute.', 'Style', 'italic', 'Tag', 'StatusBar');
end

function toggleContinuousFields(selectedButton, durSpinner, stepSpinner)
    if strcmp(selectedButton.Text, 'Continuous Tracking')
        durSpinner.Enable = 'on';
        stepSpinner.Enable = 'on';
    else
        durSpinner.Enable = 'off';
        stepSpinner.Enable = 'off';
    end
end

function executeLinkBudget(linkType, elevation, weatherMode, isContinuous, duration, timeStep)
    cfg = ogs_config();
    cfg.link.Type = linkType;
    cfg.orbit.FixedElevationAngle = elevation;
    cfg.weather.UseLive = strcmp(weatherMode, 'Live API');
    
    if ~isContinuous
        run_link_budget_live(cfg);
    else
        run_link_budget_continuous(cfg, duration, timeStep);
    end
end