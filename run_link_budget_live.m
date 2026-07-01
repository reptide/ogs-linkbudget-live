function run_link_budget_live(cfg)
%% RUN_LINK_BUDGET_LIVE
% Real-time weather API integrated optical link budget snapshot calculator
%
% Leverages standard MathWorks "Optical Satellite Communication Link Budget Analysis"
% equations while enhancing fidelity via two live environmental data inputs:
%   1) Replaces static cloud-type lookup matrices with real-time empirical visibility arrays
%   2) Automates attenuation categorization from live WMO weather condition indices
%
% Requirements: Satellite Communications Toolbox (fspl, slantRangeCircularOrbit)

% Support both standalone manual operations and programmatic GUI callback functions
if nargin < 1
    cfg = ogs_config();
end

gs   = cfg.gs;
satA = cfg.satA;
satB = cfg.satB;
link = cfg.link;

%% ---- 1. Weather Environment Data Processing ----
if cfg.weather.UseLive
    fprintf("Fetching real-time weather metrics for target coordinate (lat=%.4f, lon=%.4f)...\n", gs.Latitude, gs.Longitude);
    w = fetch_live_weather(gs.Latitude, gs.Longitude);
    fprintf("  -> Fetch Timestamp (UTC): %s | Data Source: %s\n", string(w.FetchTimeUTC), w.Source);
    fprintf("  -> Measured Visibility: %.2f km | Cloud Cover: %.0f%% | Weather Code: %g -> Class: %s\n", ...
        w.VisibilityKm, w.CloudCoverPct, w.WeatherCode, w.AttenuationType);
else
    w = struct;
    w.VisibilityKm    = cfg.weather.Manual.VisibilityKm;
    w.AttenuationType = cfg.weather.Manual.AttenuationType;
    fprintf("Using manual weather overrides: Visibility=%.2f km, Attenuation Mode=%s\n", w.VisibilityKm, w.AttenuationType);
end

visibility = w.VisibilityKm;               % Empirical visibility value in km
link.AttenuationType = w.AttenuationType;   % Auto-resolved attenuation category ("clear"|"rain"|"snow")

%% ---- 2. Orbital Path Geometry ----
link.ElevationAngle = cfg.orbit.FixedElevationAngle;

%% ---- 3. Establish System Terminal Roles ----
if link.Type=="downlink"
    tx = satA; rx = gs;
elseif link.Type=="uplink"
    tx = gs; rx = satA;
else % inter-satellite
    tx = satA; rx = satB;
end

%% ---- 4. Antenna Systems Performance: Gain & Pointing Metrics ----
txGain = (pi*tx.ApertureDiameter/link.Wavelength)^2;
Gtx = 10*log10(txGain);
rxGain = (pi*rx.ApertureDiameter/link.Wavelength)^2;
Grx = 10*log10(rxGain);
txPointingLoss = 4.3429*(txGain*(tx.PointingError)^2);
rxPointingLoss = 4.3429*(rxGain*(rx.PointingError)^2);

%% ---- 5. Link Margin Valuation ----
if link.Type=="inter-satellite"
    pathLoss = fspl(link.SatDistance*1e3, link.Wavelength);
    linkMargin = link.Ptx + 10*log10(tx.OpticsEfficiency) + 10*log10(rx.OpticsEfficiency) + ...
        Gtx + Grx - txPointingLoss - rxPointingLoss - pathLoss - link.Preq;
    fprintf("\nLink margin (inter-satellite): %.4f dB\n", linkMargin);

else % uplink / downlink atmospheric paths
    dT  = (link.TroposphereHeight - gs.Height) .* cscd(link.ElevationAngle);
    dGS = slantRangeCircularOrbit(link.ElevationAngle, satA.Height*1e3, gs.Height*1e3);
    pathLoss = fspl(dGS, link.Wavelength);

    % --- Geometrical Scattering Loss Evaluation (Empirical Visibility Framework) ---
    if link.AttenuationType == "rain"
        geoCoeff = 2.8/visibility;
    elseif link.AttenuationType == "snow"
        geoCoeff = 58/visibility;
    else % "clear" - Core Kim atmospheric scattering model (Matches baseline fog calculation)
        if visibility <= 0.5
            delta = 0;
        elseif visibility <= 1
            delta = visibility - 0.5;
        elseif visibility <= 6
            delta = 0.16*visibility + 0.34;
        elseif visibility <= 50
            delta = 1.3;
        else
            delta = 1.6;
        end
        geoCoeff = (3.91/visibility) * ((link.Wavelength*1e9/550)^-delta);
    end
    geoScaLoss = 4.3429*geoCoeff*dT;

    % --- Mie Scattering Loss Core Logic (Pure physical constraints) ---
    lambda_mu = link.Wavelength*1e6;
    a = (0.000487*lambda_mu^3) - (0.002237*lambda_mu^2) + (0.003864*lambda_mu) - 0.004442;
    b = (-0.00573*lambda_mu^3) + (0.02639*lambda_mu^2) - (0.04552*lambda_mu) + 0.05164;
    c = (0.02565*lambda_mu^3) - (0.1191*lambda_mu^2) + (0.20385*lambda_mu) - 0.216;
    d = (-0.0638*lambda_mu^3) + (0.3034*lambda_mu^2) - (0.5083*lambda_mu) + 0.425;
    mieER = a*(gs.Height^3) + b*(gs.Height^2) + c*gs.Height + d;
    mieScaLoss = (4.3429*mieER) ./ sind(link.ElevationAngle);

    linkMargin = link.Ptx + 10*log10(tx.OpticsEfficiency) + 10*log10(rx.OpticsEfficiency) + ...
        Gtx + Grx - txPointingLoss - rxPointingLoss - pathLoss - ...
        link.AbsorptionLoss - geoScaLoss - mieScaLoss - link.Preq;

    fprintf("\n===== LINK BUDGET SNAPSHOT RESULTS (%s) =====\n", upper(link.Type));
    fprintf("  Elevation angle       : %.1f deg\n", link.ElevationAngle);
    fprintf("  Slant range           : %.1f km\n", dGS/1e3);
    fprintf("  Visibility (Measured) : %.2f km\n", visibility);
    fprintf("  Attenuation type      : %s\n", link.AttenuationType);
    fprintf("  Free-space path loss  : %.2f dB\n", pathLoss);
    fprintf("  Geometrical scattering: %.2f dB\n", geoScaLoss);
    fprintf("  Mie scattering loss   : %.2f dB\n", mieScaLoss);
    fprintf("  --------------------------------------\n");
    fprintf("  Link margin           : %.4f dB\n", linkMargin);
    if linkMargin > 0
        fprintf("  -> Link Status: SUCCESS (margin > 0)\n\n");
    else
        fprintf("  -> Link Status: FAILED/RISK (margin <= 0)\n\n");
    end
end
end