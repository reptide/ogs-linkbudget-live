function tests = test_resolve_trajectory
%TEST_RESOLVE_TRAJECTORY Verifies fixed and two-body trajectory generation.

    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
%SETUPONCE Makes the project functions available while tests run from this folder.

    projectRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(projectRoot);
    testCase.TestData.ProjectRoot = projectRoot;
end

function teardownOnce(testCase)
%TEARDOWNONCE Restores the MATLAB path after the suite finishes.

    rmpath(testCase.TestData.ProjectRoot);
end

function testFixedGeometryRemainsConstant(testCase)
    cfg = ogs_config();
    cfg.orbit.Mode = "fixed";
    cfg.orbit.WorstCaseElevationAngle = 20;
    times = 0:10:60;

    geometry = resolve_trajectory(cfg, times, stableEpoch());

    verifyEqual(testCase, geometry.ElevationDeg, 20*ones(size(times)));
    verifyEqual(testCase, geometry.RangeM, geometry.RangeM(1)*ones(size(times)));
    verifyTrue(testCase, all(geometry.Visible));
end

function testKeplerianOrbitStartsAtConfiguredPeriapsis(testCase)
    cfg = ogs_config();
    cfg.orbit.Mode = "keplerian";
    cfg.orbit.Keplerian.SemiMajorAxisKm = 7000;
    cfg.orbit.Keplerian.Eccentricity = 0.01;
    cfg.orbit.Keplerian.TrueAnomalyDeg = 0;
    times = 0:60:600;

    geometry = resolve_trajectory(cfg, times, stableEpoch());
    radiusKm = vecnorm(geometry.PositionECIM)/1e3;

    verifyEqual(testCase, radiusKm(1), 6930, 'AbsTol', 1e-8);
    verifyGreaterThan(testCase, radiusKm(end), radiusKm(1));
    verifyGreaterThan(testCase, max(geometry.RangeM)-min(geometry.RangeM), 1e3);
    verifySize(testCase, geometry.Visible, size(times));
end

function testStateVectorPreservesCircularOrbitRadius(testCase)
    cfg = ogs_config();
    cfg.orbit.Mode = "state-vector";
    earthMuKm = 398600.4418;
    radiusKm = 7000;
    cfg.orbit.StateVector.PositionECIKm = [radiusKm, 0, 0];
    cfg.orbit.StateVector.VelocityECIKmS = [0, sqrt(earthMuKm/radiusKm), 0];

    geometry = resolve_trajectory(cfg, 0:10:600, stableEpoch());
    propagatedRadiusKm = vecnorm(geometry.PositionECIM)/1e3;

    verifyLessThan(testCase, max(abs(propagatedRadiusKm-radiusKm)), 1e-5);
    verifyEqual(testCase, geometry.PositionECIM(:, 1), [radiusKm; 0; 0]*1e3, ...
        'AbsTol', 1e-8);
end

function testRejectsEarthIntersectingKeplerianOrbit(testCase)
    cfg = ogs_config();
    cfg.orbit.Mode = "keplerian";
    cfg.orbit.Keplerian.SemiMajorAxisKm = 6500;
    cfg.orbit.Keplerian.Eccentricity = 0.1;

    verifyError(testCase, ...
        @() resolve_trajectory(cfg, 0, stableEpoch()), ...
        'ogs:trajectory:EarthIntersection');
end

function epoch = stableEpoch()
%STABLEEPOCH Supplies a stable UTC epoch for coordinate transformations.

    epoch = datetime(2026, 1, 1, 0, 0, 0, 'TimeZone', 'UTC');
end
