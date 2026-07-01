function [totalLossDB, geoScaLossDB, mieScaLossDB] = compute_atmospheric_loss(...
    visibility, attenuationType, elevationAngleDeg, gsHeightKm, wavelengthM, ...
    troposphereHeightKm, absorptionLossDB)
%COMPUTE_ATMOSPHERIC_LOSS Shared geometric + Mie scattering loss model
%
%   [totalLossDB, geoScaLossDB, mieScaLossDB] = COMPUTE_ATMOSPHERIC_LOSS( ...
%       visibility, attenuationType, elevationAngleDeg, gsHeightKm, ...
%       wavelengthM, troposphereHeightKm, absorptionLossDB)
%
%   This is the SAME physics used in the MathWorks Optical Satellite
%   Communication Link Budget Analysis example, ported to use live
%   measured visibility instead of the CloudType lookup table.
%
%   Both run_link_budget_live.m (single snapshot) and
%   run_link_budget_continuous.m (time-series) call this function so the
%   atmosphere model cannot silently diverge between the two engines again
%   (previously the continuous engine used a hardcoded -3.0 dB placeholder
%   instead of this model).
%
%   Inputs:
%     visibility          - measured visibility, km
%     attenuationType      - "clear" | "rain" | "snow"
%     elevationAngleDeg    - pass elevation angle, deg
%     gsHeightKm            - ground station altitude AMSL, km
%     wavelengthM           - carrier wavelength, m
%     troposphereHeightKm   - upper boundary of atmospheric loss region, km
%     absorptionLossDB      - constant molecular absorption term, dB
%
%   Outputs:
%     totalLossDB   - absorptionLossDB + geoScaLossDB + mieScaLossDB
%     geoScaLossDB  - geometric scattering loss (rain/snow/generalized Kim model)
%     mieScaLossDB  - Mie scattering loss

    dT = (troposphereHeightKm - gsHeightKm) .* cscd(elevationAngleDeg);

    % --- Geometrical scattering loss (empirical visibility framework) ---
    if attenuationType == "rain"
        geoCoeff = 2.8/visibility;
    elseif attenuationType == "snow"
        geoCoeff = 58/visibility;
    else % "clear" - generalized Kim scattering model (matches baseline "fog" formula)
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
        geoCoeff = (3.91/visibility) * ((wavelengthM*1e9/550)^-delta);
    end
    geoScaLossDB = 4.3429*geoCoeff*dT;

    % --- Mie scattering loss (pure physical constraints, unchanged from original) ---
    lambda_mu = wavelengthM*1e6;
    a = (0.000487*lambda_mu^3) - (0.002237*lambda_mu^2) + (0.003864*lambda_mu) - 0.004442;
    b = (-0.00573*lambda_mu^3) + (0.02639*lambda_mu^2) - (0.04552*lambda_mu) + 0.05164;
    c = (0.02565*lambda_mu^3) - (0.1191*lambda_mu^2) + (0.20385*lambda_mu) - 0.216;
    d = (-0.0638*lambda_mu^3) + (0.3034*lambda_mu^2) - (0.5083*lambda_mu) + 0.425;
    mieER = a*(gsHeightKm^3) + b*(gsHeightKm^2) + c*gsHeightKm + d;
    mieScaLossDB = (4.3429*mieER) ./ sind(elevationAngleDeg);

    totalLossDB = absorptionLossDB + geoScaLossDB + mieScaLossDB;
end
