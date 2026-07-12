# 이론 — 세 갈래 빌드, 개발 루프, 기여 형태별 절차, 검증 가능한 기여

> **🌱 17세 눈높이 비유: 악기를 연주하다 악기를 만드는 공방에 들어가입니다**
> - **지금까지** = 악기(도구)를 연주(사용)하는 법을 배웠습니다 — 소리의 물리(버퍼·카디널리티)까지 이해하며
> - **빌드** = 공방에서 악기를 직접 조립해 보는 것 — 조립되는 순간 "만드는 사람"의 시야가 열림
> - **Collector builder(조립 키트)** = 부품(컴포넌트)을 골라 나만의 악기를 조립하는 공식 키트
> - **개발 루프** = 부품을 깎고(수정) → 조립(빌드) → 연주해 보고(kind 배포) → 튜너로 확인(자기 관측!)
> - **검증 가능한 기여** = "고쳤어요"가 아니라 "고쳤고, 튜너 수치가 이렇게 좋아졌어요" — 장인들이 좋아하는 제자
> - **첫 작품은 작게** = 첫날부터 바이올린 몸통을 깎지 않습니다 — 활 털갈이(문서·재현)부터

---

## 1. 갈래 ① — fluent-bit (C·CMake)

```
빌드: git clone → cmake → make (CONTRIBUTING의 의존성 설치 후)
  산출물: bin/fluent-bit — 즉시 실행 가능 (-c 설정으로)
코드 지도 (06의 theory가 코드로):
  plugins/in_tail/       ← tail input (DB·로테이션 추적)
  plugins/filter_kubernetes/  ← 그 kubernetes 필터
  plugins/out_*/         ← output들 (★ 새 플러그인의 참고 틀)
  src/flb_input_chunk.c 등 ← 버퍼·청크 (06 lab-02의 물리)
개발 루프: 수정 → make → 로컬 실행(-c 테스트 설정) →
  도커 이미지 → kind의 06 구성에 교체 → 시나리오 재현
Go output 플러그인: 별도 프로젝트로 .so 빌드 — 본체 수정 없는 자기 영토
```

## 2. 갈래 ② — Prometheus·exporter (Go)

```
본체 빌드: make build → ./prometheus (promtool도 함께 — 룰 검증 도구!)
  promtool: check rules·test rules — 08·10·21의 룰을 CI에서 검증하는
  도구이기도 (기여 전에 실무 도구로도 익혀둘 것)
exporter 개발 (자기 영토의 정석):
  client_golang의 스캐폴드: Collector 인터페이스 구현
  (Describe/Collect) — 03의 4형·라벨 규율이 설계 지침
  기존 exporter(node_exporter의 collector 패키지)가 최고의 교과서
개발 루프: go build → 로컬 실행 → curl :9xxx/metrics (03의 형식 확인)
  → kind + ServiceMonitor(08)로 수집 → 카디널리티 자기 검증(tsdb_head_series)
```

## 3. 갈래 ③ — OTel Collector (builder — 조립형)

```
ocb(OpenTelemetry Collector Builder):
  builder-config.yaml에 담을 컴포넌트를 선언:
    receivers: [otlp]
    processors: [batch, 내가 만든 것!]
    exporters: [debug, otlphttp]
  → ocb --config builder-config.yaml → 나만의 Collector 바이너리

의미 둘:
  실무: 필요한 컴포넌트만 담은 경량 배포판 (contrib 전체는 무겁습니다)
  기여: ★ 새 컴포넌트의 개발 루프 — 로컬 모듈을 replace로 끼워
       조립·실행·검증 (contrib에 내기 전의 실험실)
contrib 기여 절차: 이슈(제안) → Sponsor(기존 오너의 지지) 확보 →
  스켈레톤 PR → 기능 PR (분할 제출이 관례 — "작게"의 구조화)
개발 루프: 컴포넌트 수정 → ocb 빌드 → 11 lab의 구성으로 kind 배포
  → 텔레메트리로 자기 검증 (otelcol_* 메트릭)
```

## 4. 기여 형태별 절차 요약 (cncf 50 + 25의 결합)

```
문서: 마찰 지점 → 해당 docs 저장소 → 작은 PR (DCO!)
재현 이슈: pitfalls급 이상 동작 → kind 최소 재현(이 파트의 기술) →
  템플릿대로 (버전·기대vs실제·재현 절차·로그)
작은 수정: good-first-issue 또는 자기 재현 이슈 → "제가 해볼게요" →
  테스트 동반 소형 PR
자기 영토 (exporter·플러그인·컴포넌트):
  존재 확인(중복?) → 설계(03·06·11의 규율이 지침) → 구현+문서+테스트
  → (contrib면 Sponsor 절차 / 독립 저장소면 등록·공개)
  → ★ 유지 계획 (25의 책임 — 코드오너로서의 응답)

공통 규율(50): 작게 / DCO(-s) / CONTRIBUTING 숙지 / 큰 것은 이슈 먼저 /
  리뷰 예절(배움·인내·감사) / 완료 기준은 머지가 아니라 신뢰의 시작
```

## 5. 검증 가능한 기여 — 이 파트 졸업생의 무기

```
PR 설명의 품질 공식:
  무엇을(변경) + 왜(이슈·마찰) + ★ 어떻게 확인했나(측정!)

측정의 예:
  버퍼 관련 수정 → 06 lab-02 시나리오 재현 전후의 dropped/retries 비교
  exporter 신규 → 노출 형식 검증 + 카디널리티 계산(03) 명시
  processor 수정 → 처리율·메모리(otelcol_*)와 오버헤드(20의 프로파일!)
  문서 수정 → "실제로 이 절차로 재현/해결됨" (kind 로그 첨부)
→ "측정이 붙은 PR"은 리뷰어의 검증 부담을 덜어 빠르게 흐릅니다 —
  이 파트 전체가 그 측정 능력의 훈련이었습니다
```

## 6. 소스/도구에서 확인하기

- fluent-bit DEVELOPER_GUIDE / prometheus의 CONTRIBUTING·promtool
- opentelemetry.io/docs/collector/custom-collector (ocb)
- contrib의 CONTRIBUTING(신규 컴포넌트 절차·Sponsor)
- cncf 50(기여 규율·예절·지속 로드맵) — 이 모듈의 상위 문서

## 요약 카드

| 질문 | 답 |
|------|----|
| 세 갈래? | fluent-bit(C·CMake)·Prometheus/exporter(Go)·Collector(ocb 조립형) |
| ocb의 두 의미? | 실무(경량 커스텀 배포판) + 기여(새 컴포넌트의 실험실) |
| 개발 루프? | 수정→빌드→이미지→kind(파트의 실습 구성 재사용)→관측으로 검증 |
| exporter 설계 지침? | 03의 4형·라벨 규율 — node_exporter가 교과서 |
| contrib 신규 절차? | 이슈 제안→Sponsor→스켈레톤 PR→기능 PR (분할이 관례) |
| PR 품질 공식? | 무엇을+왜+어떻게 확인했나(측정) — 측정 붙은 PR이 빠릅니다 |
| promtool? | 룰 검증 도구 — 기여 도구이자 실무(08·10·21 룰의 CI) 도구 |
| 완료 기준? | 머지가 아니라 신뢰의 시작 — 그리고 유지의 응답 (사다리) |
