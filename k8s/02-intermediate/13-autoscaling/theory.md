# 이론 — HPA, VPA, 메트릭 파이프라인

> **🌱 17세 눈높이 비유: 편의점 알바 자동 배치 시스템**
> 점장(HPA)은 15초마다 CCTV(metrics-server)로 계산대 줄 길이를 봅니다. 규칙은 하나: **"알바 1명당 손님 5명"(목표값).**
> 지금 알바 2명에 손님 20명? → 20/2=10명/인, 목표의 2배 → **알바를 4명으로** (2×10/5).
> 손님이 빠지면 바로 줄이나요? → 아니. **5분간 지켜보고**(안정화 창) 천천히 줄입니다 — 다시 몰려올 수 있으니까.
> **VPA**는 다른 질문을 합니다: "알바 수가 아니라, 한 명에게 주는 계산대 크기(메모리/CPU)가 적절한가?"

---

## 1. 메트릭 파이프라인 — HPA의 눈

```
컨테이너 cgroup 사용량
  → kubelet (cAdvisor 내장, 노드별 수집)
  → metrics-server (클러스터 집계, 인메모리 — 저장 안 함!)
  → Metrics API (metrics.k8s.io)           ← kubectl top이 보는 곳
  → HPA 컨트롤러 (15초마다 조회)
```

- metrics-server는 **현재값 전용**입니다(이력 없음). 이력/그래프는 Prometheus(관측 스택)의 일 — 별개 파이프라인.
- EKS 1.36은 metrics-server가 기본 포함. `kubectl top pods`가 되면 파이프라인 정상.
- custom metrics(RPS 등)는 `custom.metrics.k8s.io` API를 **어댑터**(Prometheus Adapter/KEDA)가 제공 — 같은 HPA가 다른 눈을 끼는 구조.

## 2. HPA — 수평 확장

### 2.1 계산식 (전부의 핵심)

```
desiredReplicas = ceil( currentReplicas × currentMetric / targetMetric )
```

예: 3개 Pod, CPU 이용률 평균 90%, 목표 50% → ceil(3 × 90/50) = ceil(5.4) = **6개**.

- "이용률(Utilization)" = 사용량 / **requests** (limits 아님!). requests 100m에 90m 쓰면 90%.
- 여러 메트릭을 걸면 **각각 계산해 가장 큰 값** 채택 (보수적).
- 허용 오차(기본 ±10%) 안이면 변경 안 함 — 미세 출렁임 방지.

### 2.2 v2 문법

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: web }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target: { type: Utilization, averageUtilization: 50 }
  # type: Pods (custom, Pod당 평균) / Object (단일 객체값) / External (외부 시스템값)
```

### 2.3 behavior — 출렁임 제어 (v2의 백미)

```yaml
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0       # 즉시 증설 (기본)
      policies:
      - { type: Percent, value: 100, periodSeconds: 15 }   # 15초마다 최대 2배
      - { type: Pods, value: 4, periodSeconds: 15 }         # 또는 +4개
      selectPolicy: Max                    # 둘 중 관대한 쪽
    scaleDown:
      stabilizationWindowSeconds: 300     # 5분간 최고 권고값 유지 후 감축 (기본)
      policies:
      - { type: Percent, value: 10, periodSeconds: 60 }     # 분당 최대 10%씩만
```

- **증설은 빠르게, 감축은 천천히** — 기본 철학. 감축이 빠르면 트래픽 재상승 때 콜드스타트 연쇄.
- `stabilizationWindowSeconds`: 그 시간 동안의 **계산 결과 중 최대값**을 씁니다 → 일시 하락에 속지 않음.

### 2.4 HPA의 맹점

- 반응형입니다: 부하 → 메트릭 반영 → 스케일 → Pod 기동까지 수십 초~분. **스파이크는 못 막습니다** (선제 대응은 예약 스케일링/KEDA cron/과잉 프로비저닝).
- replicas를 0으로 못 내립니다(min 1). "큐 비면 0으로"는 KEDA의 영역.

## 3. VPA — 수직 조정

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
spec:
  targetRef: { apiVersion: apps/v1, kind: Deployment, name: web }
  updatePolicy:
    updateMode: "Off"        # Off=권고만 / Initial=생성 시만 / Auto=재시작하며 적용
```

- 실사용량 이력으로 **requests 권고값**을 계산. `Off` 모드로 권고만 받아 rightsizing 참고하는 용법이 가장 안전하고 흔합니다.
- Auto 모드는 적용 시 **Pod를 재시작**시킴 (in-place 적용은 아직 제한적) — 운영 워크로드엔 신중히.
- **같은 메트릭(CPU)에 HPA와 VPA를 동시에 걸면 안 됩니다**: VPA가 requests를 키우면 이용률%가 내려가 HPA가 줄이고... 서로 핸들을 돌리는 꼴. (HPA=custom metric + VPA=리소스, 같은 식의 분리는 가능)

## 4. 시야 확장 — 3층 연동의 실전 흐름

```
트래픽 급증 → HPA: Pod 4→12 → 노드 부족, 4개 Pending
→ Karpenter: Pending 감지, 노드 2대 증설 (~1분) → Pending 해소
→ 트래픽 감소 → HPA: 5분 안정화 후 감축 → 노드 한산 → Karpenter consolidation으로 노드 회수
```

각 층의 지연시간 합이 사용자 체감 — 그래서 readinessProbe/이미지 크기(모듈 01)/시작 시간이 오토스케일링 품질에 직결됩니다.

## 5. 소스코드에서 확인하기

- 계산식 본체: `pkg/controller/podautoscaler/replica_calculator.go` — `GetResourceReplicas`에 ceil 식이 그대로
- behavior 적용: 같은 패키지 `horizontal.go`의 `normalizeDesiredReplicasWithBehaviors`

## 요약 카드

| 질문 | 답 |
|------|----|
| HPA 계산식? | `ceil(current × 현재값/목표값)` |
| 이용률의 분모? | **requests** (없으면 HPA 불능) |
| 감축이 느린 이유? | scaleDown 안정화 창(기본 300s) — 재상승 대비 |
| 스파이크 대응? | HPA 단독 불가(반응형) — 선제 수단 병용 |
| HPA+VPA 동시 사용? | 같은 메트릭이면 충돌 — 분리 필수 |
| kubectl top의 데이터 출처? | metrics-server (현재값 전용, 이력 없음) |
