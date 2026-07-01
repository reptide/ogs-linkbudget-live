function attType = classify_attenuation(weatherCode)
%CLASSIFY_ATTENUATION WMO 날씨 코드를 링크 버짓의 감쇄 타입으로 매핑
%
%   attType = CLASSIFY_ATTENUATION(weatherCode)
%
%   Open-Meteo는 WMO 표준 weather code(0~99)를 반환한다. 이를 원본
%   MATLAB 예제가 요구하는 세 가지 감쇄 모드로 매핑한다:
%     "rain"  - 강수 계수 공식 (Ageo = 2.8/V) 사용, 강우/소나기/뇌우일 때만
%     "snow"  - 강설 계수 공식 (Ageo = 58/V) 사용, 강설/눈보라일 때만
%     "clear" - 범용 Kim 산란 모델 (원본의 "fog" 공식) 사용.
%               맑음/흐림/옅은 안개/실측 visibility만 낮은 경우 등
%               강수가 없는 모든 상황에 적용. 원본 예제가 "fog"라고
%               이름 붙인 공식은 사실 안개 전용이 아니라 파장·visibility
%               기반의 일반 대기 산란 모델이라 이렇게 쓰는 것이 더 정확함.
%
%   run_link_budget_live.m에서 attType=="clear"인 경우 원본의 fog 분기
%   (piecewise delta + Kim 공식)를 그대로 재사용한다.

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
        % 0-3 (맑음~흐림), 45/48 (안개), 51-57 (이슬비) 등은 모두
        % visibility 기반 범용 모델로 처리 - 실측 visibility가 이미
        % 감쇄 정도를 반영하고 있으므로 별도 특수 공식이 필요 없음.
        attType = "clear";
    end
end
