function cfg = ogs_config()
%OGS_CONFIG Configuration parameters for the real-time weather-linked optical link budget

cfg = struct;

%% ---- 1. Ground Station (GS) Position & Optical Specs ----
cfg.gs.Latitude       = 36.3504;   % deg, Daejeon, South Korea (default; overridden by GUI lat field)
cfg.gs.Longitude      = 127.3845;  % deg, Daejeon, South Korea (default; overridden by GUI lon field)
cfg.gs.Height         = 0.1;       % km, Altitude AMSL (default; overridden by GUI alt field, m->km)
cfg.gs.OpticsEfficiency = 0.8;     % Optical efficiency of the receiver assembly
cfg.gs.ApertureDiameter = 1;       % m, Ground telescope aperture diameter
cfg.gs.PointingError    = 1e-6;    % rad, Static/systematic pointing error (used by snapshot engine only)
cfg.gs.JitterSigma      = 1.0e-6;  % rad, 1-sigma dynamic tracking jitter (used by continuous engine only)

%% ---- 2. Satellite A (Orbital Ground-to-Space Terminal) ----
cfg.satA.Height           = 550;   % km, Orbital altitude (LEO profile configuration)
cfg.satA.OpticsEfficiency = 0.8;   % Optical efficiency of the payload terminal
cfg.satA.ApertureDiameter = 0.07;  % m, Payload lens aperture diameter
cfg.satA.PointingError    = 1e-6;  % rad, Static/systematic pointing error (used by snapshot engine only)
cfg.satA.JitterSigma      = 2.0e-6;  % rad, 1-sigma dynamic tracking jitter (used by continuous engine only)

% Orbital geometry configuration
cfg.orbit.UseTLE = false;
cfg.orbit.WorstCaseElevationAngle = 20; % deg, evaluation angle for ground-space links
cfg.orbit.TLE_Line1 = '';            % reserved for future TLE pass calculations
cfg.orbit.TLE_Line2 = '';

%% ---- 3. Satellite B (Inter-Satellite Mesh Routing, Optional) ----
cfg.satB.OpticsEfficiency = 0.8;
cfg.satB.ApertureDiameter = 0.06;  % m
cfg.satB.PointingError    = 1e-6;  % rad
cfg.satB.JitterSigma      = 2.0e-6; % rad, 1-sigma dynamic tracking jitter

%% ---- 4. Link Layer Operational Parameters ----
cfg.link.Wavelength        = 1550e-9;  % m, core carrier wavelength
cfg.link.TroposphereHeight = 20;       % km, upper edge boundary for atmospheric loss profiles
cfg.link.SatDistance       = 1000;     % km, link distance specific to inter-satellite cross-links
cfg.link.Type              = "downlink"; % "downlink" | "uplink" | "inter-satellite"

cfg.link.Ptx  = 17.5;   % dBm, transmitter power. GUI converts its Watts spinner to dBm before
                         % writing here, so this field is ALWAYS dBm regardless of entry point.
cfg.link.Preq = -35.5;  % dBm, required receiver sensitivity (10 Gbps OOK, BER 1e-12 assumption)
                         % Used as the single outage threshold by BOTH engines (dBm throughout).
cfg.link.AbsorptionLoss = 0.01; % dB, constant molecular absorption overhead at 1550nm (ITU-R P.1621-2)

cfg.link.BoresightBias = 0; % rad, constant systematic pointing offset used only by the continuous
                             % engine's Rician tracking model. Kept at link level (not per-terminal)
                             % since it represents relative tx/rx misalignment, not a single terminal's
                             % property.

%% ---- 5. Atmospheric Data API Gateway ----
cfg.weather.Provider  = "open-meteo";  % Free API service, no access token keys required
cfg.weather.UseLive   = true;          % Set false to bypass API and use manual parameters below
cfg.weather.ContinuousMode = "Past Replay"; % "Past Replay" | "Current Hold"
% Manual fallback defaults for offline evaluation or troubleshooting
cfg.weather.Manual.VisibilityKm      = 10;
cfg.weather.Manual.AttenuationType   = "clear"; % "clear" | "rain" | "snow"

end
