function geometry = resolve_trajectory(cfg, elapsedSeconds, startTimeUTC)
%RESOLVE_TRAJECTORY Produces ground-relative geometry for the selected orbit mode.
% Fixed mode returns the conservative configured elevation and slant range.
% Keplerian and state-vector modes propagate an Earth-centered inertial
% trajectory from the simulation start and transform it to ground-station AER.

    if nargin < 2 || isempty(elapsedSeconds)
        elapsedSeconds = 0;
    end
    if nargin < 3 || isempty(startTimeUTC)
        startTimeUTC = datetime('now', 'TimeZone', 'UTC');
    end
    startTimeUTC.TimeZone = 'UTC';

    elapsedSeconds = double(elapsedSeconds(:).');
    if any(~isfinite(elapsedSeconds)) || any(elapsedSeconds < 0) || ...
            any(diff(elapsedSeconds) < 0) || elapsedSeconds(1) ~= 0
        error('Trajectory times must be finite, nonnegative, increasing, and start at zero.');
    end
    if ~isscalar(cfg.orbit.MinElevationAngle) || ...
            ~isfinite(cfg.orbit.MinElevationAngle) || ...
            cfg.orbit.MinElevationAngle < 0 || cfg.orbit.MinElevationAngle > 90
        error('Minimum elevation must be a finite angle from 0 to 90 degrees.');
    end

    mode = lower(string(cfg.orbit.Mode));
    sampleTimesUTC = startTimeUTC + seconds(elapsedSeconds);
    if mode == "fixed"
        elevationDeg = repmat(cfg.orbit.WorstCaseElevationAngle, size(elapsedSeconds));
        rangeM = repmat(slantRangeCircularOrbit( ...
            cfg.orbit.WorstCaseElevationAngle, cfg.satA.Height*1e3, ...
            cfg.gs.Height*1e3), size(elapsedSeconds));
        azimuthDeg = nan(size(elapsedSeconds));
        positionECIM = nan(3, numel(elapsedSeconds));
        source = "Fixed worst-case geometry";
    elseif mode == "keplerian"
        positionECIM = propagateKeplerian(cfg.orbit.Keplerian, elapsedSeconds);
        [azimuthDeg, elevationDeg, rangeM] = groundRelativeGeometry( ...
            positionECIM, sampleTimesUTC, cfg.gs);
        source = "Two-body Keplerian elements";
    elseif mode == "state-vector"
        positionECIM = propagateStateVector(cfg.orbit.StateVector, elapsedSeconds);
        [azimuthDeg, elevationDeg, rangeM] = groundRelativeGeometry( ...
            positionECIM, sampleTimesUTC, cfg.gs);
        source = "Two-body ECI state vector";
    else
        error('Unsupported trajectory mode: %s', cfg.orbit.Mode);
    end

    visible = elevationDeg >= cfg.orbit.MinElevationAngle;
    geometry = struct( ...
        'Mode', mode, ...
        'Source', source, ...
        'TimeUTC', sampleTimesUTC, ...
        'ElapsedSeconds', elapsedSeconds, ...
        'PositionECIM', positionECIM, ...
        'RangeM', rangeM, ...
        'AzimuthDeg', azimuthDeg, ...
        'ElevationDeg', elevationDeg, ...
        'Visible', visible);
end

function positionECIM = propagateKeplerian(elements, elapsedSeconds)
%PROPAGATEKEPLERIAN Evaluates an elliptic two-body orbit from classical elements.

    earthMu = 3.986004418e14;
    earthRadiusM = 6378137;
    semiMajorAxisM = elements.SemiMajorAxisKm*1e3;
    eccentricity = elements.Eccentricity;
    if ~isfinite(semiMajorAxisM) || semiMajorAxisM <= earthRadiusM
        error('Semi-major axis must exceed the Earth equatorial radius.');
    end
    if ~isfinite(eccentricity) || eccentricity < 0 || eccentricity >= 1
        error('Eccentricity must be in the range [0, 1).');
    end
    if semiMajorAxisM*(1-eccentricity) <= earthRadiusM
        error('ogs:trajectory:EarthIntersection', ...
            'The configured Keplerian orbit intersects the Earth.');
    end

    inclination = deg2rad(elements.InclinationDeg);
    raan = deg2rad(elements.RAANDeg);
    argumentOfPeriapsis = deg2rad(elements.ArgumentOfPeriapsisDeg);
    trueAnomaly = deg2rad(elements.TrueAnomalyDeg);
    if any(~isfinite([inclination, raan, argumentOfPeriapsis, trueAnomaly]))
        error('Keplerian angular elements must be finite.');
    end
    eccentricAnomaly0 = 2*atan2( ...
        sqrt(1-eccentricity)*sin(trueAnomaly/2), ...
        sqrt(1+eccentricity)*cos(trueAnomaly/2));
    meanAnomaly0 = eccentricAnomaly0 - eccentricity*sin(eccentricAnomaly0);
    meanMotion = sqrt(earthMu/semiMajorAxisM^3);
    meanAnomaly = meanAnomaly0 + meanMotion*elapsedSeconds;
    eccentricAnomaly = meanAnomaly;
    for iteration = 1:20
        correction = ...
            (eccentricAnomaly - eccentricity*sin(eccentricAnomaly) - meanAnomaly) ./ ...
            (1 - eccentricity*cos(eccentricAnomaly));
        eccentricAnomaly = eccentricAnomaly-correction;
        if all(abs(correction) < 1e-12)
            break;
        end
    end

    perifocalPosition = [ ...
        semiMajorAxisM*(cos(eccentricAnomaly)-eccentricity); ...
        semiMajorAxisM*sqrt(1-eccentricity^2)*sin(eccentricAnomaly); ...
        zeros(size(eccentricAnomaly))];
    rotation = rotationZ(raan)*rotationX(inclination)*rotationZ(argumentOfPeriapsis);
    positionECIM = rotation*perifocalPosition;
end

function positionECIM = propagateStateVector(stateVector, elapsedSeconds)
%PROPAGATESTATEVECTOR Integrates a two-body ECI state with RK4 steps.

    earthMu = 3.986004418e14;
    earthRadiusM = 6378137;
    position = double(stateVector.PositionECIKm(:))*1e3;
    velocity = double(stateVector.VelocityECIKmS(:))*1e3;
    if numel(position) ~= 3 || numel(velocity) ~= 3 || ...
            any(~isfinite(position)) || any(~isfinite(velocity))
        error('Initial ECI position and velocity must each contain three finite values.');
    end
    if norm(position) <= earthRadiusM
        error('Initial ECI position must be above the Earth surface.');
    end
    specificEnergy = dot(velocity, velocity)/2 - earthMu/norm(position);
    if specificEnergy >= 0
        error('Initial state must describe a bound elliptic orbit.');
    end

    positionECIM = zeros(3, numel(elapsedSeconds));
    positionECIM(:, 1) = position;
    state = [position; velocity];
    for sampleIndex = 2:numel(elapsedSeconds)
        interval = elapsedSeconds(sampleIndex) - elapsedSeconds(sampleIndex-1);
        substepCount = max(1, ceil(interval));
        step = interval/substepCount;
        for substepIndex = 1:substepCount
            state = rk4Step(state, step, earthMu);
        end
        if norm(state(1:3)) <= earthRadiusM
            error('The propagated state-vector trajectory intersects the Earth.');
        end
        positionECIM(:, sampleIndex) = state(1:3);
    end
end

function nextState = rk4Step(state, step, earthMu)
%RK4STEP Advances one Cartesian two-body integration step.

    derivative = @(value) [value(4:6); ...
        -earthMu*value(1:3)/(norm(value(1:3))^3)];
    k1 = derivative(state);
    k2 = derivative(state + 0.5*step*k1);
    k3 = derivative(state + 0.5*step*k2);
    k4 = derivative(state + step*k3);
    nextState = state + step*(k1 + 2*k2 + 2*k3 + k4)/6;
end

function [azimuthDeg, elevationDeg, rangeM] = groundRelativeGeometry(positionECIM, timeUTC, gs)
%GROUNDRELATIVEGEOMETRY Converts ECI positions to topocentric azimuth/elevation/range.

    julianDate = posixtime(timeUTC)/86400 + 2440587.5;
    centuries = (julianDate-2451545.0)/36525;
    gmstDeg = 280.46061837 + 360.98564736629*(julianDate-2451545.0) + ...
        0.000387933*centuries.^2 - centuries.^3/38710000;
    earthRotation = deg2rad(mod(gmstDeg, 360));
    cosineRotation = cos(earthRotation);
    sineRotation = sin(earthRotation);
    positionECEFM = [ ...
        cosineRotation.*positionECIM(1,:) + sineRotation.*positionECIM(2,:); ...
        -sineRotation.*positionECIM(1,:) + cosineRotation.*positionECIM(2,:); ...
        positionECIM(3,:)];

    groundECEFM = geodeticToECEF(gs.Latitude, gs.Longitude, gs.Height*1e3);
    relative = positionECEFM-groundECEFM;
    latitude = deg2rad(gs.Latitude);
    longitude = deg2rad(gs.Longitude);
    east = -sin(longitude)*relative(1,:) + cos(longitude)*relative(2,:);
    north = -sin(latitude)*cos(longitude)*relative(1,:) - ...
        sin(latitude)*sin(longitude)*relative(2,:) + cos(latitude)*relative(3,:);
    up = cos(latitude)*cos(longitude)*relative(1,:) + ...
        cos(latitude)*sin(longitude)*relative(2,:) + sin(latitude)*relative(3,:);

    rangeM = sqrt(east.^2+north.^2+up.^2);
    azimuthDeg = mod(rad2deg(atan2(east, north)), 360);
    elevationDeg = rad2deg(atan2(up, hypot(east, north)));
end

function positionECEFM = geodeticToECEF(latitudeDeg, longitudeDeg, heightM)
%GEODETICTOECEF Converts WGS-84 geodetic coordinates to ECEF metres.

    semiMajorAxisM = 6378137;
    flattening = 1/298.257223563;
    eccentricitySquared = flattening*(2-flattening);
    latitude = deg2rad(latitudeDeg);
    longitude = deg2rad(longitudeDeg);
    primeVerticalRadius = semiMajorAxisM/sqrt( ...
        1-eccentricitySquared*sin(latitude)^2);
    positionECEFM = [ ...
        (primeVerticalRadius+heightM)*cos(latitude)*cos(longitude); ...
        (primeVerticalRadius+heightM)*cos(latitude)*sin(longitude); ...
        (primeVerticalRadius*(1-eccentricitySquared)+heightM)*sin(latitude)];
end

function matrix = rotationX(angle)
%ROTATIONX Returns an active right-handed rotation about x.

    matrix = [1, 0, 0; 0, cos(angle), -sin(angle); 0, sin(angle), cos(angle)];
end

function matrix = rotationZ(angle)
%ROTATIONZ Returns an active right-handed rotation about z.

    matrix = [cos(angle), -sin(angle), 0; sin(angle), cos(angle), 0; 0, 0, 1];
end
