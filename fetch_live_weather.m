function w = fetch_live_weather(lat, lon)
%FETCH_LIVE_WEATHER Retrieves real-time atmospheric data from Open-Meteo API for ground stations
%
%   w = FETCH_LIVE_WEATHER(lat, lon)
%
%   Inputs:
%     lat, lon - Ground station coordinates in degrees
%
%   Outputs (struct w):
%     w.VisibilityKm      - Measured visibility in km (directly mapped to link budget equation calculations)
%     w.CloudCoverPct      - Total cloud cover percentage (%)
%     w.CloudCoverLowPct   - Low-level cloud cover percentage (%)
%     w.WindSpeedMs        - Wind speed in m/s
%     w.TemperatureC        - Surface air temperature (°C)
%     w.WeatherCode         - WMO weather state code
%     w.AttenuationType     - Categorized link mode ("clear" | "rain" | "snow")
%     w.FetchTimeUTC        - Query execution timestamp
%
%   The API requires no access keys. On network or API failure, a warning is thrown
%   and safe baseline defaults are applied (clear, 10km visibility) to avoid crashing active workflows.

    url = "https://api.open-meteo.com/v1/forecast";
    params = {
        "latitude",  num2str(lat), ...
        "longitude", num2str(lon), ...
        "current", strjoin([ ...
            "temperature_2m", "wind_speed_10m", "weather_code", ...
            "cloud_cover", "cloud_cover_low", "visibility"], ",") ...
        "timezone", "auto"
    };

    try
        opts = weboptions('Timeout', 10, 'ContentType', 'json');
        resp = webread(url, params{:}, opts);
        cur = resp.current;

        w = struct;
        % Convert Open-Meteo visibility from meters to kilometers
        w.VisibilityKm    = cur.visibility / 1000;
        w.CloudCoverPct   = cur.cloud_cover;
        w.CloudCoverLowPct = cur.cloud_cover_low;
        w.WindSpeedMs     = cur.wind_speed_10m;
        w.TemperatureC    = cur.temperature_2m;
        w.WeatherCode     = cur.weather_code;
        w.AttenuationType = classify_attenuation(cur.weather_code);
        w.FetchTimeUTC    = cur.time;
        w.Source          = "open-meteo-live";

    catch ME
        warning("fetch_live_weather:apiFailed", ...
            "Real-time weather API request failed (%s). Falling back to safe defaults (clear, 10km).", ...
            ME.message);
        w = struct;
        w.VisibilityKm     = 10;
        w.CloudCoverPct    = NaN;
        w.CloudCoverLowPct = NaN;
        w.WindSpeedMs      = NaN;
        w.TemperatureC     = NaN;
        w.WeatherCode      = NaN;
        w.AttenuationType  = "clear";
        w.FetchTimeUTC     = string(datetime('now', 'TimeZone', 'UTC'));
        w.Source           = "fallback-default";
    end
end