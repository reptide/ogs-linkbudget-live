function attType = classify_attenuation(weatherCode)
%CLASSIFY_ATTENUATION Maps WMO weather codes to link budget attenuation types
%
%   attType = CLASSIFY_ATTENUATION(weatherCode)
%
%   Open-Meteo returns the WMO standard weather codes (0-99). This function maps
%   them into three distinct attenuation models required for optical calculations:
%     "rain"  - Uses the precipitation formula (Ageo = 2.8/V) for rain/showers/thunderstorms
%     "snow"  - Uses the snowfall formula (Ageo = 58/V) for snow/ice pellets
%     "clear" - Uses the generalized Kim scattering model (corresponds to the baseline "fog" formula)
%               Applied to clear sky, cloudy conditions, light haze, or purely visibility-based drop.
%
%   If attType is "clear", the logic seamlessly applies the piecewise delta + Kim formulation.

    if isnan(weatherCode)
        attType = "clear";
        return
    end

    code = round(weatherCode);

    if ismember(code, [61 63 65 66 67 80 81 82 95 96 99])
        attType = "rain";
    elseif ismember(code, [71 73 75 77 85 86])
        attType = "snow";
    else
        % Codes 0-3 (clear to overcast), 45/48 (fog), 51-57 (drizzle) map to visibility-based generalized models.
        % Measured visibility already dynamically accounts for attenuation, meaning specialized formulas are omitted here.
        attType = "clear";
    end
end