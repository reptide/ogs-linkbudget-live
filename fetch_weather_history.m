function w = fetch_weather_history(lat, lon, durationSeconds)
%FETCH_WEATHER_HISTORY Retrieves recent 15-minute weather for a replay window.
%
%   w = FETCH_WEATHER_HISTORY(lat, lon, durationSeconds)
%
%   The returned samples span the requested duration and end at the latest
%   available Open-Meteo 15-minute timestep.
%
%   Outputs (struct w):
%     w.TimeUTC             - sample timestamps in UTC
%     w.RelativeTimeSeconds - simulation time from 0 to durationSeconds
%     w.VisibilityKm        - visibility in km
%     w.WeatherCode         - WMO weather code
%     w.AttenuationType     - "clear" | "rain" | "snow"
%     w.Source              - data source identifier

    arguments
        lat (1,1) double
        lon (1,1) double
        durationSeconds (1,1) double {mustBePositive}
    end

    samplePeriodSeconds = 15 * 60;
    pastSamples = ceil(durationSeconds / samplePeriodSeconds);

    url = "https://api.open-meteo.com/v1/forecast";
    params = {
        "latitude", num2str(lat), ...
        "longitude", num2str(lon), ...
        "minutely_15", "visibility,weather_code", ...
        "past_minutely_15", num2str(pastSamples), ...
        "forecast_minutely_15", "1", ...
        "timezone", "UTC"
    };

    try
        opts = weboptions('Timeout', 10, 'ContentType', 'json');
        resp = webread(url, params{:}, opts);
        series = resp.minutely_15;

        sampleTime = datetime(string(series.time), ...
            'InputFormat', "yyyy-MM-dd'T'HH:mm", 'TimeZone', 'UTC');
        visibilityKm = double(series.visibility(:)) / 1000;
        weatherCode = double(series.weather_code(:));

        sampleTime = sampleTime(:);
        windowEnd = sampleTime(end);
        windowStart = windowEnd - seconds(durationSeconds);
        relativeTime = seconds(sampleTime - windowStart);

        attenuationType = strings(size(weatherCode));
        for k = 1:numel(weatherCode)
            attenuationType(k) = classify_attenuation(weatherCode(k));
        end

        w = struct;
        w.TimeUTC = sampleTime;
        w.RelativeTimeSeconds = relativeTime;
        w.VisibilityKm = visibilityKm;
        w.WeatherCode = weatherCode;
        w.AttenuationType = attenuationType;
        w.Source = "open-meteo-15-minute-history";

    catch ME
        warning("fetch_weather_history:apiFailed", ...
            "Weather history request failed (%s). Using clear, 10 km visibility.", ...
            ME.message);

        endTime = datetime('now', 'TimeZone', 'UTC');
        w = struct;
        w.TimeUTC = [endTime - seconds(durationSeconds); endTime];
        w.RelativeTimeSeconds = [0; durationSeconds];
        w.VisibilityKm = [10; 10];
        w.WeatherCode = [NaN; NaN];
        w.AttenuationType = ["clear"; "clear"];
        w.Source = "fallback-default";
    end
end
