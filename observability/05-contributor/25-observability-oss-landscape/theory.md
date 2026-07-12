# 이론 — 4대 생태계의 거버넌스, OTel SIG 체계, 기여 유형 지도, 건강 평가

> **🌱 17세 눈높이 비유: 네 개의 동아리 연합에 가입하기**
> - **fluent(실용 공방)** = 작지만 단단한 공방 — 장인(메인테이너)들이 도구를 벼리고, 부품(플러그인) 제작은 누구나 환영
> - **prometheus(전통의 합의제 학회)** = 규칙이 명문화된 학회 — 본진은 엄격하지만, 부설 연구회(exporter)는 자기 것을 만들면 됨
> - **open-telemetry(거대 연합 동아리)** = 언어별 분과(SIG)가 수십 개인 연합 — 어느 분과든 문이 열려 있고, 표준(스펙) 분과가 중심을 잡음
> - **grafana(기업 후원 오케스트라)** = 후원 기업이 지휘하는 오케스트라 — 연주(기여)는 열려 있지만 곡목(로드맵)은 지휘자가 정함
> - **핵심** = 같은 "오픈소스"라도 운영 방식이 다릅니다 — 방식을 알고 문을 두드려야 헛걸음이 없습니다 (cncf 49)

---

## 1. fluent 생태계 (fluent-bit·fluentd)

```
구조: CNCF Graduated — fluentd(Ruby)·fluent-bit(C) 두 축
거버넌스: MAINTAINERS 중심의 실용 구조 (K8s식 정교한 ladder보단 간결)
기여 경로:
  본체(C·Ruby): 코어 버그·기능 — C 역량이면 fluent-bit 파서·버퍼 영역
    (06에서 판 CRI 파서·버퍼가 실제 코드로 있는 곳!)
  ★ 플러그인: fluent-bit은 Go 플러그인(output)·WASM 지원,
    fluentd는 Ruby gem 플러그인 — "우리 목적지" output을 만들면
    그 자체가 생태계 기여 (자기 필요 = 기여의 최고 동기)
  문서: docs 저장소 — 06·07에서 헤맨 지점들이 재료
정찰 포인트: 이슈의 응답 속도·플러그인 PR의 처리 흐름
```

## 2. prometheus 생태계

```
구조: 본체(Go·TSDB·PromQL) + Alertmanager + client 라이브러리(언어별)
     + exporter 생태(수백 개 — 대부분 별도 저장소·별도 메인테이너)
거버넌스: 팀 합의제 — GOVERNANCE.md에 멤버십·투표 명문화 (cncf 49 lab-02)
기여 경로:
  본체: 진입 장벽 높음 (TSDB·PromQL은 성숙 코어) — 이슈 트리아지·
    문서·작은 버그부터 (cncf 50의 사다리)
  ★ exporter: 사실상 독립 프로젝트들 — "우리 시스템의 exporter가 없다/
    부실하다"면 만들거나 개선 — 자기 영토라 머지 마찰이 적고,
    03의 노출 형식·라벨 규율 지식이 그대로 설계 역량
  client 라이브러리: 자기 주력 언어 쪽 — 계측 API 개선·버그
  kube-prometheus-stack·Operator(08): prometheus-operator 조직 —
    ServiceMonitor 등 CRD 세계의 개선
```

## 3. open-telemetry — 관측 최대 조직 (K8s급 구조)

```
구조 (cncf 49의 SIG 체계가 그대로):
  GC(Governance Committee)·TC(Technical Committee)
  스펙 SIG: 신호·시맨틱 컨벤션의 표준 (cncf 12의 그것을 만드는 곳)
  언어 SIG × 10+: Java·Python·Go·JS... 각자 SDK·자동 계측
  Collector SIG: 코어 + ★ contrib(컴포넌트 수백 개)
  기타: Operator·Helm·eBPF(profiling)...

기여 동선:
  ① 자기 주력 언어 SIG가 1차 진입로 — 11에서 쓴 자동 계측의
    "미지원 라이브러리"가 곧 이슈·기여 대상
  ② Collector contrib: receiver/processor/exporter 단위 —
    컴포넌트마다 코드오너가 있어 상대적으로 작은 단위 기여 가능
    (11·16에서 쓴 k8sattributes·tail_sampling이 이 세계)
  ③ 스펙·컨벤션: 텍스트 기여 (도메인 경험이 무기 — 운영자의 관점)
  진입 의례: CLA 서명, SIG 회의 공개(캘린더), good-first-issue 라벨
★ 활발함의 대가: 이슈·PR 볼륨이 커서 응답이 느릴 수 있음 —
  SIG 슬랙에서 맥락을 잡고 움직이는 것이 효율적 (cncf 50의 잠복 관찰)
```

## 4. grafana 계열 — 기업 주도 모델의 이해

```
구조: Grafana Labs가 주도하는 오픈소스 (grafana·loki·tempo·mimir·pyroscope)
  라이선스: AGPL 계열 (한때의 라이선스 전환 이력 — cncf 02의 BSL 논의와
  같은 계열의 주제. 사용에는 대체로 문제없으나 재배포 사업엔 검토 필요)
거버넌스: 기업 주도 — 로드맵·머지 권한이 사실상 사내 팀에
  (CNCF 중립형과 다름 — cncf 49의 "기여자 다양성" 렌즈)
기여의 현실:
  버그 수정·문서·플러그인(Grafana 패널/데이터소스 플러그인 생태!)은
  활발히 받음 — 특히 ★ Grafana 플러그인은 독립 배포 가능한 자기 영토
  큰 기능 방향은 기업 로드맵과의 정렬이 필요 — 제안 전 이슈로 타진
판단: "기여가 환영받는가"와 "방향을 함께 정하는가"는 다른 질문 —
  전자는 예, 후자는 제한적. 알고 참여하면 실망이 없습니다
```

## 5. 기여 유형 지도 (파트 경험 → 기여)

```
유형          재료(이 파트에서)                난이도  자기 영토성
문서          모든 모듈의 마찰 지점             낮음    -
이슈·재현     pitfalls의 사고들·kind 재현 기술  낮음    -
트리아지      needs-repro 이슈에 재현 붙이기    낮음    -
exporter      03의 노출 형식+운영 시스템 지식   중간    ★ 높음
FB 플러그인   06의 파이프라인+Go               중간    ★ 높음
Grafana 플러그인 09의 패널 이해+TS             중간    ★ 높음
Collector 컴포넌트 11·16의 파이프라인 지식      중상    코드오너제
계측 라이브러리 11의 SDK·주입 이해             중상    언어 SIG
본체 코드     각 theory의 내부 이해            높음    사다리 필요

★ "자기 영토성"이 높은 경로(exporter·플러그인)는 머지 대기·조율이
  적어 첫 성취가 빠릅니다 — cncf 50의 "작게 시작"과 결합하면:
  문서/재현으로 이름을 알리고, 자기 영토에서 첫 작품을, 본체는 그 다음
```

## 6. 건강 평가 — cncf 49 정찰 시트의 관측판

```
공통 체크 (49 그대로): GOVERNANCE·CONTRIBUTING·ladder·이슈 응답·
  good-first-issue의 신선도·메인테이너 다양성
관측 특화 체크:
  플러그인/컴포넌트의 기여 절차가 명문화돼 있나 (자기 영토의 문)
  스펙/호환성 정책 (OTel 스펙 안정성·Prometheus 포맷 보장 —
    내 기여가 깨질 토대인가)
  기업 주도면: 외부 기여의 실제 머지율 (문서만이 아니라 코드가)
```

## 7. 소스/도구에서 확인하기

- github.com/fluent · github.com/prometheus · github.com/open-telemetry · github.com/grafana
- OTel 커뮤니티: opentelemetry.io/community (SIG 목록·캘린더)
- CLOTributor(cncf 50)에서 관측 프로젝트 필터
- cncf 49(거버넌스 읽기)·50(기여의 길) — 이 모듈의 방법론 원천

## 요약 카드

| 질문 | 답 |
|------|----|
| fluent 특징? | 메인테이너 실용 구조 — 플러그인(Go·Ruby)이 1급 기여 경로 |
| prometheus 특징? | 팀 합의제 — 본체는 높은 벽, exporter는 자기 영토 |
| OTel 특징? | 관측 최대 조직(K8s급 SIG) — 언어 SIG가 1차 진입로, contrib는 컴포넌트 단위 |
| grafana 특징? | 기업 주도 — 기여 환영 but 방향은 제한적, 플러그인은 자기 영토 |
| 기여 유형 순서? | 문서·재현(이름) → 자기 영토(exporter·플러그인 — 첫 작품) → 본체(사다리) |
| 파트 경험의 가치? | 마찰=문서 재료, 사고=재현 재료, 운영 관점=스펙 텍스트 기여 무기 |
| 건강 평가? | 49 시트 + 관측 특화(플러그인 절차·스펙 정책·외부 머지율) |
| 산출물? | 관심×역량×건강의 교집합 — 26의 대상 하나 |
