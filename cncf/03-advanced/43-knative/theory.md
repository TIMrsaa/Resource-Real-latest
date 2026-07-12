# 이론 — Serving, scale-to-zero, 리비전·트래픽, Eventing, KEDA 대비, 판단

> **🌱 17세 눈높이 비유: 자동 점등 복도등 vs 항상 켠 등**
> - **일반 Deployment(항상 켠 등)** = 아무도 안 지나가도 계속 켜짐(Pod 1개 이상 상시, 전기=비용 낭비)
> - **Knative Serving(센서 복도등)** = 아무도 없으면 꺼짐(0), 누가 오면 켜짐(0→1)
>   - **Activator(센서+스위치)** = 사람이 오는 걸 감지해 불을 켜고, 켜질 때까지 잠깐 기다림(콜드 스타트)
> - **Revision(교체 가능한 전구)** = 새 전구로 갈되 옛 전구도 남겨둠, 밝기를 90:10으로 나눠 테스트(카나리)
> - **Eventing(초인종→방송)** = 초인종(이벤트)이 울리면 해당 방(소비자)에만 방송(Trigger 라우팅)
> - **콜드 스타트의 대가** = 꺼진 등은 켜지는 데 시간이 걸림 — 첫 사람은 잠깐 어둠 속에서 기다림

---

## 1. Knative Serving — 요청 기반 서버리스

```
Service(Knative) 하나가 만드는 것:
  Configuration → Revision(들) → Route(트래픽)
  + Pod 오토스케일 (0 ↔ N)

Knative Service YAML (간단!):
  apiVersion: serving.knative.dev/v1
  kind: Service
  metadata: { name: hello }
  spec:
    template:
      spec:
        containers:
          - image: myapp:v1
            env: [...]
  → 이것만으로 scale-to-zero + 오토스케일 + 리비전 + 라우팅 + URL

일반 Deployment와 비교:
  Deployment + Service + HPA + Ingress + (카나리는 별도) 를
  Knative Service 하나가 대체 (서버리스 추상)
```

## 2. scale-to-zero 메커니즘 — Activator와 KPA

```
핵심 문제: Pod가 0인데 요청이 오면?

구성 요소:
  Activator: 항상 떠 있는 컴포넌트, 요청을 붙잡고 버퍼링
  Autoscaler(KPA): 요청량을 보고 Pod 수 결정
  Queue-Proxy: 각 Pod의 사이드카(동시성 측정·Activator 통신)

0 → 1 흐름 (콜드 스타트):
  1. 요청 도착 → Pod 0이라 Activator로 라우팅
  2. Activator가 요청을 붙잡고(버퍼) KPA에 "스케일 업" 신호
  3. KPA가 Pod 1개 생성 → 준비 대기
  4. Pod Ready → Activator가 버퍼한 요청 전달
  5. 이후 트래픽은 Activator 우회, Pod로 직접
  → 1~4 사이가 "콜드 스타트" 지연 (이미지 풀·앱 시작 시간)

N → 0 흐름:
  요청 없는 시간(기본 ~60s stable window) 지속 → KPA가 0으로
  → 다시 Activator가 대기 상태로 (다음 요청 대비)

KPA vs HPA:
  HPA(08): CPU·메모리 기반, 최소 1 (0 불가)
  KPA(Knative): 동시성(concurrency)·RPS 기반, 0 가능
  → KPA가 서버리스에 맞게 요청 기반·0 지원
```

## 3. 리비전과 트래픽 분할 (08의 배포 전략 내장)

```
Revision: 코드/설정의 불변 스냅샷
  배포할 때마다 새 Revision (revision-1, revision-2...)
  옛 Revision도 남음 → 즉시 롤백 가능

Route: 트래픽을 Revision에 분배
  traffic:
    - revisionName: hello-00001
      percent: 90
    - revisionName: hello-00002
      percent: 10             # 카나리 10%
    - latestRevision: true
      tag: latest             # 이름있는 태그로 직접 접근

배포 전략 (08과 대응):
  블루그린: 100% → 0%/100% 전환
  카나리: 90/10 → 점진 이동
  → 24(메시)의 트래픽 분할과 유사하나 Knative에 내장
  → 트래픽 이동이 YAML % 변경 (GitOps 14·15로)
```

## 4. Knative Eventing — CloudEvents 라우팅 (40)

```
40에서 CloudEvents(봉투 형식)를 배웠습니다. Eventing이 그걸 라우팅:

구성:
  Source: 이벤트 발생원 → CloudEvents로 변환
    (PingSource=주기적, KafkaSource, ApiServerSource=k8s 이벤트...)
  Broker: 이벤트 버스 (이벤트를 받아 보관·전달)
  Trigger: 필터 + 구독 (type별로 소비자에 라우팅)
  Sink: 이벤트 소비자 (Knative Service 등)

흐름:
  Source → Broker → Trigger(filter: type=order.created) → Sink(Service)
  → 이벤트가 오면 해당 Trigger가 맞는 소비자에만 전달
  → 소비자는 scale-to-zero (이벤트 없으면 0, 오면 뜸)

★ 40의 event-display가 바로 Sink였습니다
  Trigger의 필터가 CloudEvents의 type·source로 라우팅
  → 이벤트 기반 서버리스 (이벤트가 곧 스케일 트리거)
```

## 5. KEDA(18)와의 관계 — 정확한 구분

```
                  KEDA(18)            Knative
정체              스케일러            서버리스 플랫폼
스케일 대상       기존 Deployment     Knative Service(자체)
트리거            이벤트 소스(50+)    HTTP 요청 / CloudEvents
scale-to-zero     O                   O
리비전·트래픽     X (스케일만)        O (카나리·롤백 내장)
Eventing 라우팅   X                   O (Broker·Trigger)
무게              가벼움              무거움(여러 컴포넌트)
채택              매우 널리           특정 서버리스 요구

언제 무엇:
  기존 워크로드를 이벤트로 0↔N 스케일 → KEDA (가볍고 충분)
  요청·이벤트 기반 서버리스 플랫폼 + 트래픽 관리 → Knative
  둘 다 쓰기도: Knative Eventing + KEDA 스케일

★ 40의 아키텍처에서: 이벤트 라우팅은 Knative Eventing,
  워커 스케일은 KEDA — 각자 강점 (겹치지만 다른 층)
```

## 6. 트레이드오프 — 서버리스를 K8s로

```
장점:
  + scale-to-zero (드문 워크로드 비용 절감)
  + 이식성 (Lambda 종속 회피, 어느 클라우드·온프레)
  + 카나리·트래픽·리비전 내장
  + Cloud Run이 Knative API 기반 (이식 경로)

단점:
  - 콜드 스타트 (첫 요청 지연 — 지연 민감 서비스엔 문제)
  - 복잡성 (Activator·KPA·여러 컴포넌트 운영)
  - 무게 (작은 클러스터엔 과함)
  - 상시 트래픽엔 이점 없음 (0으로 안 가니 콜드스타트만 손해)

판단:
  드문드문 오는 워크로드 + 이식성 필요 → Knative
  그냥 오토스케일 → HPA(08) / KEDA(18) (가벼움)
  관리형으로 충분 → Cloud Run(Knative 기반) 등
  상시 고트래픽 → 일반 Deployment (서버리스 이점 없음)
```

## 7. 소스/도구에서 확인하기

- Knative: https://knative.dev/docs — Serving(autoscaling, traffic), Eventing(broker, trigger)
- KPA: https://knative.dev/docs/serving/autoscaling/
- 08(HPA·배포 전략)·40(CloudEvents)·18(KEDA)·24(트래픽) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| Knative Serving? | 요청 기반 서버리스 — scale-to-zero·리비전·트래픽·오토스케일 |
| scale-to-zero 원리? | Activator(요청 붙잡음)+KPA(요청 기반 스케일, 0 가능) |
| 콜드 스타트? | Pod 0→1 뜰 때까지 첫 요청 대기 (서버리스의 대가) |
| 리비전·트래픽? | 불변 Revision + % 분배 → 카나리·블루그린 내장(08) |
| Eventing? | CloudEvents(40) 라우팅 — Source·Broker·Trigger·Sink |
| KEDA 차이? | KEDA=스케일러(가벼움), Knative=서버리스 플랫폼(무거움) |
| 트레이드오프? | 이식성·scale-to-zero vs 콜드스타트·복잡성·무게 |
| 언제? | 드문 워크로드+이식성. 그냥 스케일이면 HPA/KEDA |
