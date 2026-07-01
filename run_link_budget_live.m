%% RUN_LINK_BUDGET_LIVE
% 실시간 기상 API 연동 광통신 링크 버짓 계산
%
% MathWorks "Optical Satellite Communication Link Budget Analysis" 예제의
% 수식을 그대로 사용하되, 다음 두 가지를 실측 실시간 데이터로 대체한다:
%   1) CloudType 표 기반 visibility 역산 -> Open-Meteo 실측 visibility 직접 사용
%   2) 고정 AttenuationType 수동 선택   -> WMO weather code 기반 자동 분류
%
% 필요 라이브러리: Satellite Communications Toolbox (fspl, slantRangeCircularOrbit)
% 설정을 바꾸려면 이 파일이 아니라 ogs_config.m 을 수정하세요.

clear; clc;

cfg = ogs_config();
gs   = cfg.gs;
satA = cfg.satA;
satB = cfg.satB;
link = cfg.link;

%% ---- 1. 실시간 기상 데이터 조회 ----
if cfg.weather.UseLive
    fprintf("실시간 기상 조회 중 (lat=%.4f, lon=%.4f)...\n", gs.Latitude, gs.Longitude);
    w = fetch_live_weather(gs.Latitude, gs.Longitude);
    fprintf("  -> 조회 시각(UTC): %s | 출처: %s\n", string(w.FetchTimeUTC), w.Source);
    fprintf("  -> 시정: %.2f km | 전운량: %.0f%% | 날씨코드: %g -> 감쇄타입: %s\n", ...
        w.VisibilityKm, w.CloudCoverPct, w.WeatherCode, w.AttenuationType);
else
    w = struct;
    w.VisibilityKm    = cfg.weather.Manual.VisibilityKm;
    w.AttenuationType = cfg.weather.Manual.AttenuationType;
    fprintf("수동 기상값 사용: 시정=%.2f km, 감쇄타입=%s\n", w.VisibilityKm, w.AttenuationType);
end

visibility = w.VisibilityKm;               % km - 원본의 역산값을 대체하는 실측값
link.AttenuationType = w.AttenuationType;   % "clear"|"rain"|"snow" (자동 판별)

%% ---- 2. 궤도 기하 (elevation angle) ----
% Step 2에서 TLE 기반 실시간 pass 계산으로 교체 예정. 지금은 config의
% 고정값을 사용한다.
if cfg.orbit.UseTLE
    error("TLE 기반 elevation 계산은 아직 구현되지 않았습니다 (Step 2). ogs_config.m에서 UseTLE=false로 두세요.");
else
    link.ElevationAngle = cfg.orbit.FixedElevationAngle;
end

%% ---- 3. 송수신단 결정 ----
if link.Type=="downlink"
    tx = satA; rx = gs;
elseif link.Type=="uplink"
    tx = gs; rx = satA;
else % inter-satellite
    tx = satA; rx = satB;
end

%% ---- 4. 공통: 안테나 이득 / 포인팅 손실 ----
txGain = (pi*tx.ApertureDiameter/link.Wavelength)^2;
Gtx = 10*log10(txGain);
rxGain = (pi*rx.ApertureDiameter/link.Wavelength)^2;
Grx = 10*log10(rxGain);
txPointingLoss = 4.3429*(txGain*(tx.PointingError)^2);
rxPointingLoss = 4.3429*(rxGain*(rx.PointingError)^2);

%% ---- 5. 링크 마진 계산 ----
if link.Type=="inter-satellite"
    pathLoss = fspl(link.SatDistance*1e3, link.Wavelength);
    linkMargin = link.Ptx + 10*log10(tx.OpticsEfficiency) + 10*log10(rx.OpticsEfficiency) + ...
        Gtx + Grx - txPointingLoss - rxPointingLoss - pathLoss - link.Preq;
    fprintf("\nLink margin (inter-satellite): %.4f dB\n", linkMargin);

else % uplink / downlink
    dT  = (link.TroposphereHeight - gs.Height) .* cscd(link.ElevationAngle);
    dGS = slantRangeCircularOrbit(link.ElevationAngle, satA.Height*1e3, gs.Height*1e3);
    pathLoss = fspl(dGS, link.Wavelength);

    % --- 기하학적 산란 손실 (실측 visibility + 자동 판별 AttenuationType) ---
    if link.AttenuationType == "rain"
        geoCoeff = 2.8/visibility;
    elseif link.AttenuationType == "snow"
        geoCoeff = 58/visibility;
    else % "clear" - 범용 Kim 모델 (원본의 fog 분기와 동일 공식)
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
        geoCoeff = (3.91/visibility) * ((link.Wavelength*1e9/550)^-delta);
    end
    geoScaLoss = 4.3429*geoCoeff*dT;

    % --- Mie 산란 손실 (원본과 동일, 물리 파라미터만 사용하므로 변경 없음) ---
    lambda_mu = link.Wavelength*1e6;
    a = (0.000487*lambda_mu^3) - (0.002237*lambda_mu^2) + (0.003864*lambda_mu) - 0.004442;
    b = (-0.00573*lambda_mu^3) + (0.02639*lambda_mu^2) - (0.04552*lambda_mu) + 0.05164;
    c = (0.02565*lambda_mu^3) - (0.1191*lambda_mu^2) + (0.20385*lambda_mu) - 0.216;
    d = (-0.0638*lambda_mu^3) + (0.3034*lambda_mu^2) - (0.5083*lambda_mu) + 0.425;
    mieER = a*(gs.Height^3) + b*(gs.Height^2) + c*gs.Height + d;
    mieScaLoss = (4.3429*mieER) ./ sind(link.ElevationAngle);

    linkMargin = link.Ptx + 10*log10(tx.OpticsEfficiency) + 10*log10(rx.OpticsEfficiency) + ...
        Gtx + Grx - txPointingLoss - rxPointingLoss - pathLoss - ...
        link.AbsorptionLoss - geoScaLoss - mieScaLoss - link.Preq;

    fprintf("\n===== 링크 버짓 결과 (%s) =====\n", link.Type);
    fprintf("  Elevation angle       : %.1f deg\n", link.ElevationAngle);
    fprintf("  Slant range           : %.1f km\n", dGS/1e3);
    fprintf("  Visibility (실측)      : %.2f km\n", visibility);
    fprintf("  Attenuation type      : %s\n", link.AttenuationType);
    fprintf("  Free-space path loss  : %.2f dB\n", pathLoss);
    fprintf("  Geometrical scattering: %.2f dB\n", geoScaLoss);
    fprintf("  Mie scattering loss   : %.2f dB\n", mieScaLoss);
    fprintf("  ------------------------------\n");
    fprintf("  Link margin           : %.4f dB\n", linkMargin);
    if linkMargin > 0
        fprintf("  -> 링크 성립 (margin > 0)\n");
    else
        fprintf("  -> 링크 실패 위험 (margin <= 0)\n");
    end
end
