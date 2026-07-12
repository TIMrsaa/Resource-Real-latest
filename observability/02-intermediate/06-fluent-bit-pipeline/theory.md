# 이론 — 파이프라인 문법, CRI 파싱, k8s 필터, 버퍼·백프레셔, 라우팅, 자기 관측

> **🌱 17세 눈높이 비유: 아파트 단지의 분리수거 시스템**
> - **각 세대의 배출(앱 로그)** = 매일 쏟아지는 쓰레기(로그) — 세대는 그냥 내놓기만(stdout)
> - **동별 수거함(/var/log/pods)** = 일단 동 앞에 모임 — 넘치면 오래된 것부터 버려짐(로테이션)
> - **수거 차량(Fluent Bit, 동마다 1대 = DaemonSet)** = 동 앞 수거함을 돌며 수거
>   - **분류(파서)** = 봉투 겉면 라벨(CRI 접두어)을 읽고, 내용물(JSON)을 품목별로
>   - **동 정보 스티커(kubernetes 필터)** = "어느 동·몇 호(네임스페이스·Pod)"를 부착
>   - **반입 금지(필터링)** = 재활용 안 되는 것(헬스체크 소음)은 현장에서 걸러 비용 절약
> - **차량 적재함(버퍼)** = 처리장(목적지)이 막히면 적재함에 보관 — 적재함이 넘치면? 노상 적치(filesystem 버퍼)로 버티거나, 수거를 잠시 멈춤(백프레셔 pause) — 안 그러면 쓰레기 유실
> - **차량 운행 일지(내장 메트릭)** = 수거량·드롭·재시도를 기록 — 차량 자체도 감시 대상

---

## 1. 아키텍처 — DaemonSet 수집기

```
노드마다 Fluent Bit 1개 (DaemonSet):
  hostPath로 /var/log 마운트 → 그 노드의 모든 Pod 로그 접근
  노드 수 = 수집기 수 (수평 확장이 자동)

vs 사이드카(02의 ③): Pod마다 수집기 — 무겁고 예외용
vs 중앙 1개: 모든 노드 로그를 원격으로? — 불가(파일은 노드에)
→ 로그 수집의 표준 형태 = DaemonSet (쿠버네티스가 만든 형태)
```

## 2. 파이프라인 문법 — tag/match 라우팅

```
[SERVICE]                     # 전역: flush 주기·로그 레벨·HTTP 서버(메트릭)
[INPUT]                       # 소스 → 레코드에 tag 부여
    Name              tail
    Path              /var/log/containers/*.log
    Tag               kube.*            # 파일 경로가 tag에 (kube.var.log...)
    multiline.parser  cri               # ★ CRI 포맷 + P/F 재조립 (02!)
    DB                /var/log/fb.db    # ★ 읽던 위치 기억 (재시작 대비)
    Mem_Buf_Limit     50MB
[FILTER]
    Name              kubernetes        # ★ 메타데이터 부착
    Match             kube.*            # 이 태그들만
    Merge_Log         On                # ★ 앱 JSON을 필드로 승격 (02 구조화!)
    Keep_Log          Off
[FILTER]
    Name              grep              # 소음 제거 (비용의 첫 수문)
    Match             kube.*
    Exclude           $log /healthz
[OUTPUT]
    Name              loki              # (12에서) — 목적지별 플러그인
    Match             kube.*            # 태그 라우팅
    ...

동작 순서: INPUT(tag 부여) → FILTER들(match 순서대로) → OUTPUT(match)
★ tag = 레코드의 주소, match = 라우팅 규칙
  kube.* → Loki로, host.* → S3로 같은 분기가 이걸로
```

## 3. 파싱의 두 층 (02의 복습이 설정이 됩니다)

```
층 1 — CRI 포맷 벗기기:
  원문: 2026-...Z stdout F {"level":"error",...}
  multiline.parser cri가:
    시각/스트림/플래그 분리 + ★ P 조각들을 F까지 모아 재조립
  → 이걸 안 하면: 시각·스트림이 본문에 섞이고, 긴 JSON이 조각남

층 2 — 앱 로그 파싱:
  kubernetes 필터의 Merge_Log On:
    log 필드가 JSON이면 → 필드로 승격 (level, event, user_id...)
  비JSON(레거시)이면: 정규식 파서를 지정하거나 통째로 log 필드
  → 02에서 "구조화는 앱에서"라고 한 이유 — 여기서 JSON이면 공짜,
    아니면 정규식 유지보수 지옥

층 3(선택) — 앱 멀티라인 (스택트레이스):
  Java 스택트레이스는 여러 줄 = 여러 레코드로 쪼개짐
  multiline 파서(정규식으로 시작줄 정의)로 한 레코드로 합침
```

## 4. kubernetes 필터 — 메타데이터의 마법과 비용

```
하는 일:
  레코드의 tag에서 Pod 이름·네임스페이스 추출
  → kubelet/API로 Pod 정보 조회 (라벨·어노테이션·컨테이너명)
  → 레코드에 kubernetes.* 필드로 부착

효과: "어느 앱의 로그인가"가 쿼리 가능해짐
  {namespace="prod", app="payment"} 같은 필터 (12의 Loki 라벨!)
  02의 "서비스 식별 필드"를 수집기가 무료로

비용·주의:
  API 조회 → 캐시하지만 대규모에서 API 부하 (Use_Kubelet On으로 로컬 조회)
  어노테이션 전체 부착은 레코드 비대 → Labels/Annotations Off 선별
```

## 5. 버퍼·백프레셔 — 유실의 물리를 설정으로 (cncf 14 → 실전)

```
경로: [tail] → [엔진 처리] → [출력 버퍼] → [목적지]

시나리오 A: 목적지 느림/다운
  출력 버퍼(chunk)가 쌓임 → Mem_Buf_Limit 도달 → ?
  storage.type memory (기본): 새 chunk 못 만듦 → tail pause
    = ★ 백프레셔: 소스가 "파일"이라 멈춰도 파일은 남아있음 (유리한 조건!)
    단, pause 동안 로테이션이 파일을 지우면 → 유실 (02의 물리)
  storage.type filesystem: 디스크에 chunk 저장 → 훨씬 큰 완충
    + 재시작에도 생존 → ★ 프로덕션 표준

시나리오 B: Fluent Bit 재시작
  mem 버퍼: 미전송분 소멸 / fs 버퍼: 생존
  tail DB: 읽던 오프셋 기억 → 이어 읽기 (없으면 처음부터/끝부터 혼란)

시나리오 C: 영구 실패 (4xx 등)
  Retry_Limit: 재시도 상한 → 초과 시 드롭 (기록됨 — 메트릭!)
  무한 재시도는 버퍼를 영원히 잡음 → 상한 + 알림이 현실적

핵심 설정 요약:
  storage.type filesystem + storage.path        # 영속 버퍼
  storage.total_limit_size (출력별)             # 디스크 한도
  Mem_Buf_Limit (input별)                       # 메모리 한도
  DB (tail)                                     # 오프셋 영속
  Retry_Limit (output별)                        # 재시도 상한
```

## 6. 수집기의 자기 관측 (관측의 관측 — 22 예고)

```
[SERVICE]의 HTTP_Server On → :2020/api/v1/metrics/prometheus

봐야 할 메트릭:
  fluentbit_input_records_total     읽은 양
  fluentbit_output_proc_records_total  보낸 양
  fluentbit_output_retries_total    재시도 (목적지 불안 신호)
  fluentbit_output_dropped_records_total  ★ 드롭 = 유실 발생!
  storage 관련: chunk 수·fs 사용량 (버퍼 적체 신호)

원칙: "드롭 0"이 아니라 "드롭이 보이는 상태"가 목표
  드롭 메트릭에 알림(10) → 유실을 아는 유실로
  (08에서 Prometheus가 이 엔드포인트를 scrape)
```

## 7. 소스/도구에서 확인하기

- Fluent Bit 문서: docs.fluentbit.io — tail·kubernetes filter·buffering·monitoring
- cncf 14: 버퍼·백프레셔의 내부 원리 (이 모듈의 이론적 기반)
- helm 차트: fluent/fluent-bit (lab에서 사용)

## 요약 카드

| 질문 | 답 |
|------|----|
| 배치 형태? | DaemonSet(노드마다) + hostPath /var/log — 로그 수집의 표준형 |
| 파이프라인? | INPUT(tag)→FILTER(match)→OUTPUT(match) — tag가 주소, match가 라우팅 |
| CRI 파싱? | multiline.parser cri — 접두어 벗기기+P/F 재조립 (02) |
| JSON 승격? | kubernetes 필터 Merge_Log On — 구조화 로그가 필드로 |
| 메타데이터? | kubernetes 필터가 네임스페이스·라벨 부착 (Use_Kubelet로 API 부하↓) |
| 유실 방어? | fs 버퍼(재시작 생존)+DB(오프셋)+한도+Retry_Limit |
| 백프레셔? | 버퍼 차면 tail pause — 파일 소스라 가능, 단 로테이션 경주 |
| 자기 관측? | :2020 메트릭 — dropped_records에 알림 ("아는 유실"로) |
