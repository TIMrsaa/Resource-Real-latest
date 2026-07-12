# 이론 — 로그의 경로, 파이프라인 5단, 버퍼와 백프레셔, 두 프로젝트, 상관

> **🌱 17세 눈높이 비유: 학교 신문 배달**
> - **앱의 stdout** = 학생이 쪽지를 씁니다
> - **CRI 로그 파일** = 쪽지가 교실 우편함에 쌓입니다 (`/var/log/pods/...`)
> - **Fluent Bit(에이전트)** = 층마다 있는 배달원 — 우편함을 계속 확인(tail)하고, 봉투를 뜯어 형식을 확인(parse)하고, 필요 없는 것은 버리고(filter), 손수레에 담습니다(buffer)
> - **백프레셔** = 학교 우체국(백엔드)이 밀려서 못 받습니다 → 손수레가 찹니다 → 배달원의 선택: 쪽지를 버리거나(drop), 서서 기다리거나(block), 창고에 임시 보관(디스크 버퍼)
> - **유실의 잔인함** = 버려지는 쪽지는 하필 "불이야!"라고 쓰인 것일 수 있습니다. 그리고 아무도 버려진 걸 모릅니다
> - **Fluentd(애그리게이터)** = 중앙 우체국 — 복잡한 분류·변환을 맡습니다. 크고 느리지만 유능
> - **trace_id 필드** = 쪽지마다 주문번호를 적어두는 것 — 나중에 여정(트레이스)과 대조 가능

---

## 1. 컨테이너 로그의 실제 경로

```
앱 프로세스 stdout/stderr
   │ (컨테이너 런타임이 가로챔 — 03의 그 체인)
   ▼
/var/log/pods/<ns>_<pod>_<uid>/<container>/0.log     ← CRI 로그 형식(JSON 또는 CRI 텍스트)
   │ (심볼릭 링크: /var/log/containers/*.log)
   │ ★ kubelet이 로테이션 관리 (containerLogMaxSize, 기본 10Mi × 5)
   ▼
Fluent Bit / Fluentd (DaemonSet — hostPath로 마운트)
   │ tail → parse → filter(kubernetes 메타 부착) → buffer → output
   ▼
백엔드 (Loki / Elasticsearch / S3 / CloudWatch ...)
```

핵심 사실 둘:

- **kubelet의 로테이션이 첫 유실 지점**: 10Mi × 5 = 50Mi를 넘으면 오래된 파일이 삭제됩니다. 에이전트가 못 따라가면(백엔드 느림·에이전트 다운) **읽기 전에 파일이 사라집니다**
- **`kubectl logs`는 그 파일을 읽는 것**입니다 — 로테이션되면 과거 로그가 없는 이유

## 2. 파이프라인 5단계와 실패 모드

| 단계 | 하는 일 | 대표 실패 |
|---|---|---|
| **input(tail)** | 파일을 추적, 오프셋(DB) 관리 | 오프셋 손실 → 중복/누락, inode 재사용 |
| **parser** | CRI 형식·JSON·정규식 파싱, **멀티라인 병합** | 스택트레이스가 줄마다 조각남 |
| **filter** | k8s 메타 부착, 재작성, 드롭 | k8s API 부하(메타 조회), 과도한 필터 CPU |
| **buffer** | 메모리/파일 큐, 청크·재시도 | **백프레셔 → 유실** (§3) |
| **output** | 백엔드 전송, 재시도·백오프 | 백엔드 느림·429, 부분 실패 |

```
멀티라인의 함정:
  Java 스택트레이스 30줄 → 30개의 로그 레코드로 저장 → 검색·상관 불가
  해결: multiline parser (첫 줄 패턴으로 시작 감지)
  더 나은 해결: 앱이 처음부터 JSON 한 줄로 (구조화 로깅 — §5)
```

## 3. 버퍼와 백프레셔 — 로그를 잃는 세 가지 방식

```
백엔드가 느려집니다 → 버퍼가 찹니다 → 셋 중 하나:

① drop (기본값인 경우가 많습니다)
   Fluent Bit: Mem_Buf_Limit 초과 시 새 데이터 폐기 (또는 input 일시정지)
   → 파이프라인은 살고, 로그는 조용히 사라진다 ⚠️ 가장 흔한 유실

② block (파이프라인 정지)
   input이 멈춥니다 → 파일은 계속 쌓입니다 → kubelet 로테이션이 삭제 → 결국 유실
   극단적으로 컨테이너의 stdout 쓰기가 블록될 수 있습니다(런타임 구성에 따라)

③ 디스크 버퍼로 흘림 (storage.type filesystem)
   메모리 초과분을 디스크에 → 여유를 벌지만 디스크가 차면 다시 ①/②
   대가: I/O, 노드 디스크 압박
```

**핵심 통찰**: 유실은 백엔드가 느려진 순간, 즉 **장애 중에** 최대가 됩니다 — 로그가 가장 필요한 순간에 가장 많이 잃습니다. 그래서 설계는 "잃지 않기"가 아니라 "**어디서, 무엇을 잃을지 선택하기**"다.

```
방어 설계:
  - 디스크 버퍼(filesystem) + 충분한 노드 디스크 + 알람(버퍼 사용률!)
  - 백엔드 앞에 큐(Kafka)를 두어 완충 (대규모)
  - 볼륨을 줄여 근본 완화: 앱의 로그 레벨, 에이전트 필터 drop, 샘플링(비에러 로그)
  - 중요 로그(감사·에러)는 별도 파이프라인·별도 보증 (24의 감사 로그 불변성과 연결)
  - fluentbit_output_retries_failed_total, buffer usage 를 알람으로 (유실을 조용하지 않게)
```

## 4. Fluentd vs Fluent Bit

| | Fluentd | Fluent Bit |
|---|---|---|
| 언어 | Ruby(+C 코어) | **C** |
| 메모리 | 수십~수백 MB | **수 MB** |
| 플러그인 | 1000+ (풍부) | 수십 (핵심) |
| 설정 | 태그 기반 라우팅(`<match>`) | 태그 + 파이프라인(classic/YAML) |
| 자리 | **애그리게이터**(중앙) | **에이전트**(노드) |
| 성숙도 | CNCF Graduated | 같은 프로젝트 가족(하위) |

```
배치 패턴:
[A] Fluent Bit(DaemonSet) → 백엔드 직결          ← 단순·저비용 (많은 조직의 현재)
[B] Fluent Bit(DaemonSet) → Fluentd(중앙) → 백엔드  ← 복잡 라우팅·변환·재시도 집중
[C] Fluent Bit → Kafka → 소비자들                 ← 대규모·다중 소비자
[D] OTel Collector(filelog receiver) → 백엔드      ← 12의 통일 노선 (신호 단일 파이프라인)

[D]의 함의: 06 지도의 대통일 운동이 로그 행에도 도달 중 —
  단, 성숙도·플러그인 폭에서 Fluent Bit가 아직 강합니다. 병행 검토가 현실.
```

## 5. 구조화 로깅과 상관 — 조사 동선의 마지막 조각

```json
// 나쁨: 평문 — 파싱 부담, 필드 없음, 상관 불가
2026-07-10 14:02:11 ERROR payment failed for user 12345 after 600ms

// 좋음: 구조화 JSON — 필드로 검색, trace_id로 트레이스와 연결
{"ts":"2026-07-10T14:02:11Z","level":"error","msg":"payment failed",
 "trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7",
 "user_id":"12345","duration_ms":600,"service.name":"payment"}
```

- `trace_id`/`span_id`는 OTel 컨텍스트에서 자동 주입 가능(로깅 라이브러리 통합 — 12)
- **06 사고 사례의 실패 지점**: 서비스마다 요청 ID가 달라 로그를 이어 붙일 수 없었습니다
- **13의 조사 동선 마지막 홉**: 트레이스에서 얻은 trace_id로 로그를 조회 → "왜"
- 카디널리티 관점: 로그는 **높은 카디널리티 필드가 자연스러운 곳**입니다(user_id·request_id) — 11의 메트릭 규칙과 반대. 신호 분업(06)의 실무 형태.

## 6. 볼륨 관리 — 로그 비용의 실체

```
비용 = 수집량 × 저장 단가 × 보존 + 인덱싱 비용
줄이는 지점(위에서부터 쌉니다):
  ① 앱: 로그 레벨(프로덕션 info 이하 억제), 반복 로그 제거, 디버그 로그 게이트
  ② 에이전트: 노이즈 필터 drop(헬스체크 200 로그 등), 필드 프루닝
  ③ 백엔드: 인덱싱 최소화(Loki의 라벨만 인덱싱 철학), 보존 정책, 콜드 티어
★ ①이 가장 싸고, ③이 가장 비쌉니다 — 그런데 대부분 ③부터 손댑니다
```

## 7. 소스/도구에서 확인하기

- Fluent Bit: https://docs.fluentbit.io — buffering, multiline, kubernetes filter
- Fluentd: https://docs.fluentd.org — buffer plugins, at-least-once
- kubelet 로그 로테이션: https://kubernetes.io/docs/concepts/cluster-administration/logging/
- OTel filelog receiver: opentelemetry-collector-contrib
- 12·13 복습: trace_id 상관

## 요약 카드

| 질문 | 답 |
|------|----|
| 로그의 실제 경로? | stdout → CRI 로그 파일(/var/log/pods) → 에이전트 tail → 백엔드 |
| 첫 유실 지점? | kubelet 로테이션 — 에이전트가 못 따라가면 읽기 전에 파일이 사라집니다 |
| 파이프라인 5단? | input(tail·오프셋) / parser(멀티라인!) / filter(k8s 메타) / buffer / output |
| 유실의 세 방식? | drop(조용함) / block(파이프라인 정지) / 디스크 버퍼(한계 있음) |
| 유실이 최대인 순간? | 백엔드가 느려진 때 = 장애 중 — 로그가 가장 필요할 때 가장 많이 잃습니다 |
| Fluentd vs Fluent Bit? | 애그리게이터(중앙·플러그인) vs 에이전트(노드·경량 C) — 조합이 표준 |
| 조사 동선의 마지막 조각? | 구조화 로그 + trace_id 필드 (06 사고 사례의 실패 지점) |
| 비용 줄이는 순서? | 앱(가장 쌈) → 에이전트 필터 → 백엔드 인덱싱·보존(가장 비쌈) |
