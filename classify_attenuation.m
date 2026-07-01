function attType = classify_attenuation(weatherCode)
%CLASSIFY_ATTENUATION Maps WMO weather codes to link budget attenuation types
%
%   attType = CLASSIFY_ATTENUATION(weatherCode)
%
%   Open-Meteo returns standard WMO weather codes (0-99). This function 
%   maps them into three attenuation modes required by the link budget:
%     "rain"  - Uses the rain coefficient formula (Ageo = 2.8/V) for rain/showers/thunderstorms.
%     "snow"  - Uses the snow coefficient formula (Ageo = 58/V) for snow/blizzards.
%     "clear" - Uses the general Kim scattering model. Applied to all situations without 
%               precipitation (e.g., clear, cloudy, fog, or when visibility is low).
%               The original MathWorks example labels this formula as "fog", but it is actually 
%               a general atmospheric scattering model based on wavelength and visibility.

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
        % 0-3 (Clear to Cloudy), 45/48 (Fog), 51-57 (Drizzle), etc.
        % Processed via the visibility-based general scattering model. Since measured 
        % visibility already reflects the attenuation level, no special formulas are needed.
        attType = "clear";
    end
end