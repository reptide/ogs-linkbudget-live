function w = fetch_live_weather(lat, lon)
%FETCH_LIVE_WEATHER Open-Meteo API에서 지상국 위치의 실시간 기상을 가져온다
%
%   w = FETCH_LIVE_WEATHER(lat, lon)
%
%   입력:
%     lat, lon - 지상국 위도/경도 (deg)
%
%   출력 (struct w):
%     w.VisibilityKm      - 실측 시정 (km). 링크 버짓의 visibility 항에
%                            직접 대입되는 핵심 값.
%     w.CloudCoverPct      - 전운량 (%)
%     w.CloudCoverLowPct   - 저층운량 (%)
%     w.WindSpeedMs        - 풍속 (m/s)
%     w.TemperatureC        - 기온 (°C)
%     w.WeatherCode         - WMO 날씨 코드
%     w.AttenuationType     - "clear"|"fog"|"rain"|"snow" (WeatherCode에서 자동 분류)
%     w.FetchTimeUTC        - 데이터 조회 시각
%
%   API는 키가 필요 없는 무료 서비스입니다 (Open-Meteo, CC BY 4.0).
%   호출 실패 시 에러를 던지지 않고 warning 후 안전한 기본값(clear, 10km)을
%   반환합니다 - 필드 관측 중 네트워크가 끊겨도 시뮬레이션이 죽지 않도록.

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
        % Open-Meteo visibility 단위는 m -> km로 변환
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
            "실시간 기상 API 호출 실패 (%s). 기본값(clear, 10km)으로 대체합니다.", ...
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
