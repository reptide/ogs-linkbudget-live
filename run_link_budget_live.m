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
%
% Reads the unified cfg schema defined in ogs_config.m (cfg.gs/satA/satB/
% orbit/link/weather). See compute_atmospheric_loss.m for the shared
% atmosphere physics also used by run_link_budget_continuous.m.

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
% NOTE: FixedElevationAngle is used as the fixed elevation angle for the
% whole snapshot, not a minimum threshold (see ogs_config.m comment).
% TLE-based time-varying elevation is not yet implemented.
if isfield(cfg.orbit, 'UseTLE') && cfg.orbit.UseTLE
    error("TLE-based elevation tracking is not implemented yet. Set cfg.orbit.UseTLE = false.");
end
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
    dGS = slantRangeCircularOrbit(link.ElevationAngle, satA.Height*1e3, gs.Height*1e3);
    pathLoss = fspl(dGS, link.Wavelength);

    [atmLossDB, geoScaLoss, mieScaLoss] = compute_atmospheric_loss( ...
        visibility, link.AttenuationType, link.ElevationAngle, gs.Height, ...
        link.Wavelength, link.TroposphereHeight, link.AbsorptionLoss);

    linkMargin = link.Ptx + 10*log10(tx.OpticsEfficiency) + 10*log10(rx.OpticsEfficiency) + ...
        Gtx + Grx - txPointingLoss - rxPointingLoss - pathLoss - atmLossDB - link.Preq;

    fprintf("\n===== LINK BUDGET SNAPSHOT RESULTS (%s) =====\n", upper(link.Type));
    fprintf("  Ground station coords : %.4f N, %.4f E\n", gs.Latitude, gs.Longitude);
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
