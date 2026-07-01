function cfg = ogs_config()
%OGS_CONFIG Configuration file for the real-time weather-linked optical link budget
%
%   This file serves as the single source of truth for configuration. 
%   Modify ground station parameters, orbit attributes, hardware specifications, 
%   and link options here. You do not need to modify run_link_budget_live.m.
%
%   The data structure mirrors the MathWorks "Optical Satellite Communication 
%   Link Budget Analysis" example (gs / satA / satB / link structs) to maintain 
%   100% compatibility with verified link budget equations.

cfg = struct;

%% ---- 1. Ground Station (GS) Position & Optics ----
cfg.gs.Latitude       = 36.3504;   % deg, Daejeon, South Korea
cfg.gs.Longitude      = 127.3845;  % deg, Daejeon, South Korea
cfg.gs.Height         = 0.1;       % km, Altitude above sea level (~100m average)
cfg.gs.OpticsEfficiency = 0.8;     % Optical efficiency
cfg.gs.ApertureDiameter = 1;       % m, Receiver telescope aperture diameter
cfg.gs.PointingError    = 1e-6;    % rad, Pointing error

%% ---- 2. Satellite A (Downlink/Uplink Target) ----
cfg.satA.Height           = 550;   % km, Orbital altitude (LEO example)
cfg.satA.OpticsEfficiency = 0.8;
cfg.satA.ApertureDiameter = 0.07;  % m
cfg.satA.PointingError    = 1e-6;  % rad

% Orbit geometry path (Circular orbit assumption)
cfg.orbit.FixedElevationAngle = 50;  % deg, Static elevation angle used for the link

%% ---- 3. Satellite B (Inter-satellite Link, Optional) ----
cfg.satB.OpticsEfficiency = 0.8;
cfg.satB.ApertureDiameter = 0.06;  % m
cfg.satB.PointingError    = 1e-6;  % rad

%% ---- 4. Link Parameters ----
cfg.link.Wavelength        = 1550e-9;  % m
cfg.link.TroposphereHeight = 20;       % km
cfg.link.SatDistance       = 1000;     % km, Path distance used only for inter-satellite links
cfg.link.Type              = "downlink"; % "downlink" | "uplink" | "inter-satellite"

cfg.link.Ptx  = 17.5;   % dBm, Transmitter power
cfg.link.Preq = -35.5;  % dBm, Required sensitivity (Assuming 10 Gbps OOK, BER 1e-12)
cfg.link.AbsorptionLoss = 0.01; % dB, Constant value at 1550nm (ITU-R P.1621-2)

%% ---- 5. Real-Time Weather API Settings ----
cfg.weather.Provider  = "open-meteo";  % Free weather provider (No API key needed)
cfg.weather.UseLive   = true;          % If false, falls back to manual values below
% Manual overrides for offline debugging/testing
cfg.weather.Manual.VisibilityKm      = 10;
cfg.weather.Manual.AttenuationType   = "clear"; % "clear"|"rain"|"snow"

end