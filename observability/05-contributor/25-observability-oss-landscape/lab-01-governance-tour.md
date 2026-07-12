# Lab 01 — 4대 생태계 거버넌스 실제 탐방

> cncf 49 lab-01(TOC 탐방)의 방식으로, 관측 4대 생태계의 1차 자료(저장소·거버넌스 문서·회의)를 직접 탐방합니다. 브라우저만 있으면 됩니다. 각 탐방의 목표는 "이 동네의 규칙과 분위기"를 몸으로 아는 것.

## 1. fluent 탐방

```
github.com/fluent/fluent-bit:
  □ MAINTAINERS.md — 몇 명, 소속 분포는? (기여자 다양성 렌즈)
  □ CONTRIBUTING.md — 빌드 요구사항(C 툴체인)·PR 절차
  □ 이슈 라벨 훑기 — good first issue의 신선도(최근 처리됐나)
  □ DEVELOPER_GUIDE.md — 플러그인 개발 문서의 존재(자기 영토의 문)
  □ 최근 머지된 외부 PR 3개 — 리뷰 온도(며칠? 몇 라운드?)

관찰 기록(예시 양식):
  "메인테이너 N명, 주도 회사 편중 있음/없음, 외부 PR 평균 O일,
   플러그인 절차 명문화 O/X" — lab-02 시트의 재료
```

## 2. prometheus 탐방

```
github.com/prometheus/prometheus:
  □ GOVERNANCE.md — 팀 멤버 자격·투표 (cncf 49에서 봤던 것 재확인)
  □ 이슈에서 "help wanted" — 본체의 열린 일감 성격
github.com/prometheus/node_exporter (exporter 세계의 대표):
  □ collector 추가의 PR 사례 — exporter 생태의 기여 형태
prometheus-operator/kube-prometheus:
  □ 08에서 쓴 스택의 뒷마당 — 이슈의 성격(운영 질문 다수)
★ exporter 목록(prometheus.io/docs/instrumenting/exporters):
  □ 자기 회사/관심 시스템의 exporter가 있나요? 없다면 — 그것이 후보
```

## 3. open-telemetry 탐방 (가장 큰 동네)

```
opentelemetry.io/community:
  □ SIG 목록과 회의 캘린더 — 자기 언어 SIG의 회의 시간 확인
github.com/open-telemetry/community:
  □ 거버넌스(GC·TC) 구조 문서
github.com/open-telemetry/opentelemetry-collector-contrib:
  □ ★ 컴포넌트 디렉터리 훑기 — 11·16에서 쓴 k8sattributes·
    tail_sampling의 실제 코드 위치 확인
  □ CODEOWNERS — 컴포넌트별 오너 (작은 단위 기여의 구조)
  □ "Sponsor 필요" 라벨 — 신규 컴포넌트의 진입 절차
자기 언어 저장소(예: opentelemetry-python):
  □ instrumentation 디렉터리 — 지원 라이브러리 목록
  □ ★ 11에서 아쉬웠던 미지원 라이브러리가 이슈에 있나요? (기여 후보!)
```

## 4. grafana 탐방 (기업 주도 모델 관찰)

```
github.com/grafana/grafana:
  □ CONTRIBUTING.md — CLA·절차
  □ 최근 머지된 PR의 작성자 분포 — 사내 vs 외부 비율 감 잡기
    (기업 주도 모델의 실제 — 판단 재료이지 비난이 아님)
  □ 플러그인 개발 문서(grafana.com/developers) — 자기 영토의 문
github.com/grafana/loki:
  □ 12에서 쓴 라벨 규율 관련 이슈들 — 도메인 지식이 이슈를 읽게 합니다
```

## 5. 탐방 종합 — 온도표

| 생태계 | 거버넌스 | 외부 PR 온도 | 자기 영토 경로 | 나와의 언어 정합 |
|--------|----------|--------------|----------------|------------------|
| fluent | 메인테이너제 | (기록) | 플러그인(Go/Ruby/C) | (기록) |
| prometheus | 팀 합의제 | (기록) | exporter(Go) | (기록) |
| open-telemetry | SIG 체계 | (기록) | contrib 컴포넌트·계측 | (기록) |
| grafana | 기업 주도 | (기록) | 패널/데이터소스 플러그인(TS) | (기록) |

**기록 규칙** — 각 칸을 "직접 본 근거"로 채웁니다(cncf 49의 정찰 원칙: 문서가 아니라 실제 동작). 이 표가 lab-02 대상 선정의 1차 자료입니다.

## 정리

- 4대 생태계의 규칙·분위기를 1차 자료로 — 문서와 실제(PR 처리·이슈 온도)를 함께
- OTel contrib의 CODEOWNERS 구조 = 작은 단위 기여의 문, 언어 SIG = 1차 진입로
- exporter·플러그인 문서의 존재 여부 = 자기 영토 경로의 열림 정도
- 기업 주도(grafana)는 장단을 알고 참여 — 기여 환영과 방향 주도는 다른 질문
- **★ 온도표의 근거는 전부 "직접 본 것" — 25의 정찰이 26의 헛걸음을 없앱니다**
