function cfg = ogs_config()
%OGS_CONFIG 실시간 기상 연동 광통신 링크 버짓의 모든 설정값
%
%   이 파일이 유일한 설정 지점입니다. 지상국 위치, 위성 궤도, 렌즈/광학계
%   스펙, 링크 파라미터를 여기서만 바꾸면 run_link_budget_live.m은 손댈
%   필요가 없습니다.
%
%   구조는 MathWorks Optical Satellite Communication Link Budget Analysis
%   예제(gs / satA / satB / link 구조체)를 그대로 따릅니다. 즉 기존에
%   검증된 링크 버짓 수식과 100% 호환됩니다.

cfg = struct;

%% ---- 1. 지상국(GS) 위치 및 광학계 ----
cfg.gs.Latitude       = 36.3504;   % deg, 대전
cfg.gs.Longitude      = 127.3845;  % deg, 대전
cfg.gs.Height         = 0.1;       % km, 해발고도 (대전 평균 ~100m)
cfg.gs.OpticsEfficiency = 0.8;     % 광학 효율
cfg.gs.ApertureDiameter = 1;       % m, 망원경 개구경 (렌즈 지름)
cfg.gs.PointingError    = 1e-6;    % rad, 포인팅 오차

%% ---- 2. 위성 A (GS와 직접 통신하는 위성) ----
cfg.satA.Height           = 550;   % km, 궤도 고도 (LEO 예시)
cfg.satA.OpticsEfficiency = 0.8;
cfg.satA.ApertureDiameter = 0.07;  % m
cfg.satA.PointingError    = 1e-6;  % rad

% 궤도 경로 (원궤도 가정, slantRangeCircularOrbit와 호환)
% ElevationAngle을 고정값으로 줄 수도 있고, TLE 기반 실제 pass를 쓰려면
% cfg.orbit.UseTLE = true 로 바꾸고 TLE를 입력하세요 (Step 2에서 구현 예정).
cfg.orbit.UseTLE = false;
cfg.orbit.FixedElevationAngle = 50;  % deg, UseTLE=false일 때 사용
cfg.orbit.TLE_Line1 = '';  % Step 2: TLE 기반 실시간 pass 계산용
cfg.orbit.TLE_Line2 = '';

%% ---- 3. 위성 B (inter-satellite 링크용, 필요할 때만 사용) ----
cfg.satB.OpticsEfficiency = 0.8;
cfg.satB.ApertureDiameter = 0.06;  % m
cfg.satB.PointingError    = 1e-6;  % rad

%% ---- 4. 링크 파라미터 ----
cfg.link.Wavelength        = 1550e-9;  % m
cfg.link.TroposphereHeight = 20;       % km
cfg.link.SatDistance       = 1000;     % km, inter-satellite 링크 거리
cfg.link.Type              = "downlink"; % "downlink" | "uplink" | "inter-satellite"

cfg.link.Ptx  = 17.5;   % dBm, 송신 전력
cfg.link.Preq = -35.5;  % dBm, 요구 수신 감도 (10 Gbps OOK, BER 1e-12 기준)
cfg.link.AbsorptionLoss = 0.01; % dB, 1550nm 기준 고정값 (ITU-R P.1621-2)

%% ---- 5. 실시간 기상 API 설정 ----
cfg.weather.Provider  = "open-meteo";  % 무료, API 키 불필요
cfg.weather.UseLive   = true;          % false면 수동 입력값 사용 (아래)
% UseLive=false일 때 수동으로 넣을 대체값 (오프라인 테스트/디버깅용)
cfg.weather.Manual.VisibilityKm      = 10;
cfg.weather.Manual.AttenuationType   = "clear"; % "clear"|"fog"|"rain"|"snow"

end
