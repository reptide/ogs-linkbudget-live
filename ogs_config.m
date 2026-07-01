function cfg = ogs_config()
%OGS_CONFIG Configuration parameters for the real-time weather-linked optical link budget
%
%   This file acts as the single point of configuration for the entire suite.
%   Modifying ground station locations, orbital parameters, lens metrics, or link configurations
%   here will apply across all snapshot and continuous engines without altering execution scripts.
%
%   Structure follows the MathWorks Optical Satellite Communication Link Budget Analysis 
%   convention (gs / satA / satB / link structures) ensuring 100% downstream mathematical compatibility.

cfg = struct;

%% ---- 1. Ground Station (GS) Position & Optical Specs ----
cfg.gs.Latitude       = 36.3504;   % deg, Daejeon, South Korea
cfg.gs.Longitude      = 127.3845;  % deg, Daejeon, South Korea
cfg.gs.Height         = 0.1;       % km, Altitude above sea level (~100m average for Daejeon)
cfg.gs.OpticsEfficiency = 0.8;     % Optical efficiency of the receiver assembly
cfg.gs.ApertureDiameter = 1;       % m, Telescope primary aperture diameter
cfg.gs.PointingError    = 1e-6;    % rad, Baseline static pointing error offset
cfg.gs.JitterSigma      = 1.5e-6;  % rad, 1-sigma random tracking vibration for time-series analysis
cfg.gs.BoresightBias    = 0.5e-6;  % rad, Constant systematic alignment bias for Rician model simulation

%% ---- 2. Satellite A (Orbital Ground-to-Space Terminal) ----
cfg.satA.Height           = 550;   % km, Orbital altitude (LEO profile configuration)
cfg.satA.OpticsEfficiency = 0.8;   % Optical efficiency of the payload terminal
cfg.satA.ApertureDiameter = 0.07;  % m, Payload lens aperture diameter
cfg.satA.PointingError    = 1e-6;  % rad, Baseline static pointing error offset
cfg.satA.JitterSigma      = 3.0e-6;  % rad, 1-sigma tracking vibration of fine-pointing mechanisms
cfg.satA.BoresightBias    = 1.0e-6;  % rad, Constant payload alignment bias for Rician model simulation

% Orbital Geometry Configuration
cfg.orbit.UseTLE = false;
cfg.orbit.FixedElevationAngle = 50;  % deg, Static fallback target when UseTLE is disabled
cfg.orbit.TLE_Line1 = '';            % Reserved for future TLE pass calculations
cfg.orbit.TLE_Line2 = '';

%% ---- 3. Satellite B (Inter-Satellite Mesh Routing, Optional) ----
cfg.satB.OpticsEfficiency = 0.8;
cfg.satB.ApertureDiameter = 0.06;  % m
cfg.satB.PointingError    = 1e-6;  % rad

%% ---- 4. Link Layer Operational Parameters ----
cfg.link.Wavelength        = 1550e-9;  % m, Core carrier wavelength
cfg.link.TroposphereHeight = 20;       % km, Upper edge boundary for atmospheric loss profiles
cfg.link.SatDistance       = 1000;     % km, Link distance specific to inter-satellite cross-links
cfg.link.Type              = "downlink"; % "downlink" | "uplink" | "inter-satellite"

cfg.link.Ptx  = 17.5;   % dBm, Total optical output transmitter power
cfg.link.Preq = -35.5;  % dBm, Required sensitivity threshold (Assuming 10 Gbps OOK, BER 1e-12)
cfg.link.AbsorptionLoss = 0.01; % dB, Constant molecular absorption overhead at 1550nm (ITU-R P.1621-2)

%% ---- 5. Atmospheric Data API Gateway ----
cfg.weather.Provider  = "open-meteo";  % Free API service, no access token keys required
cfg.weather.UseLive   = true;          % Set false to bypass API and use manual parameters below
% Manual fallback defaults for offline evaluation or troubleshooting
cfg.weather.Manual.VisibilityKm      = 10;
cfg.weather.Manual.AttenuationType   = "clear"; % "clear" | "rain" | "snow"

end