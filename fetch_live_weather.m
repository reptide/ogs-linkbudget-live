function w = fetch_live_weather(lat, lon)
%FETCH_LIVE_WEATHER Fetches real-time weather data for the ground station via Open-Meteo API
%
%   w = FETCH_LIVE_WEATHER(lat, lon)
%
%   Inputs:
%     lat, lon - Ground station latitude and longitude (deg)
%
%   Outputs (struct w):
%     w.VisibilityKm      - Measured visibility (km). Core value fed into the link budget.
%     w.CloudCoverPct      - Total cloud cover (%)
%     w.CloudCoverLowPct   - Low cloud cover (%)
%     w.WindSpeedMs        - Wind speed (m/s)
%     w.TemperatureC        - Temperature (°C)
%     w.WeatherCode         - WMO weather code
%     w.AttenuationType     - "clear"|"rain"|"snow" (Auto-classified from WeatherCode)
%     w.FetchTimeUTC        - Data retrieval timestamp
%
%   The API is a free service that does not require an API key (Open-Meteo, CC BY 4.0).
%   If the call fails, a warning is issued and safe defaults are used (clear, 10km)
%   so that simulations do not crash during field tracking due to network drops.

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
            "Real-time weather API call failed (%s). Falling back to default (clear, 10km).", ...
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