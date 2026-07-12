# Lab 01 — Variables 활용

> **🌱 Variables 가 뭔가? 왜 필수?**
> Grafana 의 **Variables (Templates)** = 대시보드 상단의 drop-down 필터.
> 같은 패널을 namespace/Pod/instance 별로 보고 싶을 때 매번 새 패널 만드는 대신 변수 한 번 정의 → 동적 필터.
>
> **종류**:
> - **Query**: PromQL/SQL 결과를 옵션으로 (예: 모든 namespace)
> - **Custom**: 정적 값 목록 (`prod,staging,dev`)
> - **Interval**: 시간 윈도우 (`1m,5m,1h`) — rate window 동적 변경
> - **Datasource**: 여러 Prometheus 인스턴스 전환
> - **Constant**: 상수 (URL prefix 등)
>
> **핵심 가치**: 한 대시보드로 N개 환경/대상 처리 — JSON 정의 줄어들고 유지보수 쉬움.

## 1. Grafana 접근

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
```

http://localhost:3000 (admin / eks-study-admin)

## 2. 새 대시보드 생성

1. 좌측 + 메뉴 → Dashboard
2. New panel 추가 → close (변수 먼저 만들기)

> **🧠 변수 먼저, 패널 나중**
> 패널 쿼리에 변수를 쓰려면 변수가 먼저 정의되어 있어야 함.
> 거꾸로 하면 패널 쿼리에 `$namespace` 가 빈 값으로 평가 → 빈 그래프.
>
> 워크플로: 변수 정의 → 데이터 흐름 검증 (drop-down 채워짐?) → 패널 추가.

## 3. 변수 정의

Settings (대시보드 우상단 톱니) → Variables → Add variable.

### 변수 1: namespace
- **Name**: namespace
- **Type**: Query
- **Data source**: Prometheus
- **Query**: `label_values(kube_pod_info, namespace)`
- **Multi-value**: ✓ (여러 NS 선택 가능)
- **Include All option**: ✓
- Apply

> **🧠 `label_values` 함수의 동작**
> Grafana 전용 함수 (PromQL 아님).
> ```
>   label_values(<metric>, <label>)
>   = 그 메트릭의 unique <label> 값들 반환
> ```
> = "kube_pod_info 메트릭에 등장하는 모든 namespace 값 목록".
>
> **Multi-value + All**: drop-down 에서 여러 개 + "All" 옵션.
> 선택 결과는 PromQL 에서 `=~` (정규식) 매칭으로 사용 — `namespace=~"$namespace"`.

### 변수 2: pod
- **Name**: pod
- **Type**: Query
- **Query**: `label_values(kube_pod_info{namespace=~"$namespace"}, pod)`     ← cascading
- **Multi-value**: ✓
- Apply

> **🧠 Cascading variables 의 위력**
> `$namespace` 가 변수 query 안에 들어감 → namespace 가 바뀌면 pod 목록 자동 재계산.
> = "monitoring 네임스페이스 선택 → pod drop-down 에 monitoring NS 의 Pod 만".
>
> **순서 중요**: Variables 목록의 위에서 아래 순서로 평가. namespace 가 pod 보다 위에 있어야.
> Settings → Variables 에서 드래그로 순서 변경 가능.

### 변수 3: interval (rate window)
- **Name**: interval
- **Type**: Interval
- **Values**: `1m,5m,15m,1h`

> **🧠 Interval 변수의 두 가지 활용**
> 1. **사용자 토글**: drop-down 으로 1m/5m/1h 직접 선택
> 2. **`$__interval` 자동값**: Grafana 가 그래프 너비/시간 범위 보고 적정 값 자동 선택 (시간 범위 1d 면 자동으로 5m)
>
> 알람용 윈도우는 1: 명시적 — 패닉 시 1m 으로 빠른 변화 확인.
> 일반 대시보드는 2: 자동 — 줌 인/아웃 시 적정 해상도.

## 4. 패널에서 변수 사용

새 패널 → Time series. Query:
```
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=~"$namespace",pod=~"$pod"}[$interval]))
```

상단 drop-down 으로 namespace / pod / interval 변경 시 그래프 즉시 갱신.

> **🧠 `=~` (regex) 가 Multi-value 에 필수인 이유**
> Multi-value 변수는 선택 결과를 정규식 OR 로 묶어 반환:
> - 선택: `[order, payment]` → `$namespace` = `order|payment`
> - PromQL: `namespace=~"order|payment"` ← regex 매칭이라 OK
>
> 만약 `=` (정확 매칭) 쓰면:
> - `namespace="order|payment"` ← 그런 값 없음 → 빈 결과
>
> Multi-value 쓸 거면 무조건 `=~`. 단일 값이면 `=` OK.

## 5. Repeat by variable (한 변수당 패널 자동 복제)

패널 설정 → Repeat options:
- Repeat by: `namespace`

→ 각 namespace 마다 같은 패널이 한 줄에 자동 생성.

> **🧠 Repeat 의 두 가지 모드**
> - **Repeat panel**: 같은 패널을 N번 복제, 각 인스턴스에 다른 변수값
> - **Repeat row**: 행 전체를 복제 (여러 패널 묶음)
>
> 활용 예:
> - "각 NS 별 RPS / 에러율 / 지연" 3개 패널 묶음 → row repeat → NS 마다 한 줄
> - "각 노드별 CPU" → panel repeat → 단일 패널 N개
>
> **함정**: Repeat 변수가 multi-value 이고 100개 값 선택 → 패널 100개 렌더링 → 브라우저 freeze.
> 보통 변수에 max 5~10 값 정도로 제한하거나 NS=All 선택 비추.

## 6. 변수 export → JSON 저장

대시보드 Settings → JSON Model → 복사. 다음 lab 의 provisioning 에 사용.

> **🧠 JSON Model 의 구조**
> ```json
> {
>   "templating": { "list": [...] },   ← 변수 정의
>   "panels": [...],                    ← 패널들
>   "time": {...},                      ← 기본 시간 범위
>   "uid": "...",                       ← 영구 ID
>   "version": N                        ← 변경 카운터
> }
> ```
> Provisioning 시 `version` 은 무시 (Grafana 가 관리). `uid` 는 영구 — 변경 시 다른 대시보드로 인식.

## 7. 표준 대시보드 변수 (재사용 패턴)

| 변수 | Query | 용도 |
|------|-------|------|
| `cluster` | `label_values(kubernetes_cluster)` 또는 hardcode | 멀티 클러스터 |
| `namespace` | `label_values(kube_pod_info, namespace)` | NS 필터 |
| `pod` | `label_values(kube_pod_info{namespace=~"$namespace"}, pod)` | Pod 필터 |
| `instance` | `label_values(node_uname_info, instance)` | 노드 필터 |
| `interval` | Interval type | rate window |

> **🧠 이 5개 조합 = 90% 대시보드 커버**
> 표준화하면 모든 팀 대시보드가 같은 변수 이름 사용 → URL 공유 시 변수 값 직접 전달 가능.
>
> URL 패턴: `/d/<uid>/<slug>?var-namespace=order&var-pod=order-service-xxx`
> = 알람에서 대시보드 링크 생성 시 컨텍스트 자동 전달.

## 8. 학습 확인

1. `Multi-value` 옵션 + `=~` regex 매칭 조합의 효과는?
2. `label_values` 와 `query_result` 함수의 차이는?
3. cascading 변수 ($namespace → $pod) 가 늦게 갱신되는 이유?

> **힌트**:
> 1. 여러 값을 한 PromQL 쿼리에서 OR 매칭 — 변수 값이 `a|b|c` 처럼 합쳐짐. =~ 가 정규식 매처라 가능. = 면 동작 안 함.
> 2. label_values = label 의 unique value 목록 (가벼움). query_result = 임의 PromQL 쿼리의 모든 시계열 (라벨 + 값) — 동적 옵션 만들 때.
> 3. Grafana 가 변수를 위에서 아래로 평가. namespace 변경 → pod query 재실행 (네트워크 + Prometheus 평가) → drop-down 갱신. 보통 0.5~2초 지연.

다음: [lab-02-provisioning.md](./lab-02-provisioning.md)
