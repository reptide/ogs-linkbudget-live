function run_link_budget_continuous(cfg, duration, timeStep, jitterModel)
% RUN_LINK_BUDGET_CONTINUOUS Time-Series Jitter Simulation and Analytics Engine
%
%   Generates dynamic tracking noise sequences using dual orthogonal axis errors. 
%   Resolves into either Rayleigh or biased Rician radial pointing vectors to output 
%   continuous link margin profiles and structural transmission analytics.

    gs   = cfg.gs;
    satA = cfg.satA;
    link = cfg.link;

    %% ---- 1. Weather Profile Initialization ----
    if cfg.weather.UseLive
        w = fetch_live_weather(gs.Latitude, gs.Longitude);
        visibility = w.VisibilityKm;
        link.AttenuationType = w.AttenuationType;
    else
        visibility = cfg.weather.Manual.VisibilityKm;
        link.AttenuationType = cfg.weather.Manual.AttenuationType;
    end

    %% ---- 2. Static Hardware & Atmospheric Attenuation Coefficients ----
    txGain = (pi*satA.ApertureDiameter/link.Wavelength)^2;
    Gtx = 10*log10(txGain);
    rxGain = (pi*gs.ApertureDiameter/link.Wavelength)^2;
    Grx = 10*log10(rxGain);

    dT  = (link.TroposphereHeight - gs.Height) .* cscd(cfg.orbit.FixedElevationAngle);
    dGS = slantRangeCircularOrbit(cfg.orbit.FixedElevationAngle, satA.Height*1e3, gs.Height*1e3);
    pathLoss = fspl(dGS, link.Wavelength);

    if link.AttenuationType == "rain"
        geoCoeff = 2.8/visibility;
    elseif link.AttenuationType == "snow"
        geoCoeff = 58/visibility;
    else
        if visibility <= 0.5,     delta = 0;
        elseif visibility <= 1,   delta = visibility - 0.5;
        elseif visibility <= 6,   delta = 0.16*visibility + 0.34;
        elseif visibility <= 50,  delta = 1.3;
        else,                     delta = 1.6;
        end
        geoCoeff = (3.91/visibility) * ((link.Wavelength*1e9/550)^-delta);
    end
    geoScaLoss = 4.3429*geoCoeff*dT;

    lambda_mu = link.Wavelength*1e6;
    a = (0.000487*lambda_mu^3) - (0.002237*lambda_mu^2) + (0.003864*lambda_mu) - 0.004442;
    b = (-0.00573*lambda_mu^3) + (0.02639*lambda_mu^2) - (0.04552*lambda_mu) + 0.05164;
    c = (0.02565*lambda_mu^3) - (0.1191*lambda_mu^2) + (0.20385*lambda_mu) - 0.216;
    d = (-0.0638*lambda_mu^3) + (0.3034*lambda_mu^2) - (0.5083*lambda_mu) + 0.425;
    mieER = a*(gs.Height^3) + b*(gs.Height^2) + c*gs.Height + d;
    mieScaLoss = (4.3429*mieER) ./ sind(cfg.orbit.FixedElevationAngle);

    % Base link budget margin excluding stochastic misalignment dynamics
    baseMargin = link.Ptx + 10*log10(satA.OpticsEfficiency) + 10*log10(gs.OpticsEfficiency) + ...
                 Gtx + Grx - pathLoss - link.AbsorptionLoss - geoScaLoss - mieScaLoss - link.Preq;

    %% ---- 3. Stochastic Time-Series Execution Loop ----
    timeVec = 0:timeStep:duration;
    numSteps = length(timeVec);
    marginTime = zeros(1, numSteps);

    for t = 1:numSteps
        if strcmp(jitterModel, 'Rayleigh (No Bias)')
            % Zero-mean independent dual-axis tracking vibrations (Rayleigh distribution)
            theta_tx = sqrt(normrnd(0, satA.JitterSigma)^2 + normrnd(0, satA.JitterSigma)^2);
            theta_rx = sqrt(normrnd(0, gs.JitterSigma)^2 + normrnd(0, gs.JitterSigma)^2);
        else
            % Combined fixed offset centers with random tracking noise (Rician distribution)
            theta_tx = sqrt(normrnd(satA.BoresightBias, satA.JitterSigma)^2 + normrnd(satA.BoresightBias, satA.JitterSigma)^2);
            theta_rx = sqrt(normrnd(gs.BoresightBias, gs.JitterSigma)^2 + normrnd(gs.BoresightBias, gs.JitterSigma)^2);
        end
        
        txLoss = 4.3429 * (txGain * theta_tx^2);
        rxLoss = 4.3429 * (rxGain * theta_rx^2);
        marginTime(t) = baseMargin - txLoss - rxLoss;
    end

    %% ---- 4. Data Visualizations & Plot Windows ----
    figure('Name', 'Continuous Dynamic Performance Simulation Analytics');
    subplot(2,1,1);
    plot(timeVec, marginTime, 'b', 'LineWidth', 1.5); hold on;
    yline(0, 'r--', 'Link Outage Threshold (Margin=0)', 'LineWidth', 1.5);
    grid on; title(sprintf('Dynamic Margin Profile (Model: %s)', jitterModel));
    xlabel('Time (Seconds)'); ylabel('Link Margin Availability (dB)');

    subplot(2,2,3);
    histogram(marginTime, 25, 'Normalization', 'pdf', 'FaceColor', [0.46 0.67 0.18]);
    grid on; title('Margin Probability Density Function (PDF)'); xlabel('Margin (dB)');

    subplot(2,2,4);
    outagePct = (sum(marginTime <= 0) / numSteps) * 100;
    bar(outagePct, 'FaceColor', [0.85 0.32 0.09]);
    set(gca, 'XTick', []); title('Calculated Link Outage Rate'); ylabel('Time in Outage (%)');
end