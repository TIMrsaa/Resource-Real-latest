# 학습 가이드 — 서버리스를 K8s로

## 서버리스가 약속한 것

Lambda·Cloud Functions로 대표되는 서버리스의 약속:

```
① 안 쓰면 0 (요청 없으면 비용 없음, scale-to-zero)
② 알아서 확장 (트래픽 폭증에 자동 스케일)
③ 서버 관리 없음 (코드만 올리면 됨)
```

하지만 대가가 있습니다 — **벤더 종속**(Lambda는 AWS에 묶임), 실행 환경 제약(런타임·시간 제한), 로컬 재현 어려움. Knative는 이 서버리스 경험을 **K8s 위에서** 재현해 이식성을 되찾으려는 시도입니다.

```
Lambda: 서버리스 편의 + AWS 종속
Knative: 서버리스 편의 + K8s 이식성 (어느 클라우드·온프레든)
```

## 두 부분 — Serving과 Eventing

```
Knative Serving: 요청 기반 서버리스
  scale-to-zero, 0→N 자동, 리비전, 트래픽 분할
  → "HTTP 요청을 받는 서버리스 컨테이너"

Knative Eventing: 이벤트 기반 라우팅
  CloudEvents(40)를 Broker·Trigger로 라우팅
  → "이벤트에 반응하는 서버리스"
```

40에서 CloudEvents를 배울 때 event-display로 이벤트를 받아봤습니다 — 그것이 Knative Eventing의 맛보기였습니다. 이 모듈이 그 전체를 다룹니다.

## 핵심 마법 — scale-to-zero의 원리

08에서 HPA(부하로 스케일)를 배웠지만, HPA는 최소 1은 유지합니다(0으로 못 감). Knative의 차별점은 **0까지** 간다는 것:

```
문제: Pod가 0이면 요청이 오면 누가 받나요? (아직 Pod가 없는데)
Knative의 답: Activator
  요청 → Activator(항상 떠 있음)가 붙잡음 → Pod를 띄움(0→1)
        → Pod 준비되면 요청 전달 → 이후 직접
  → 첫 요청은 "콜드 스타트"(Pod 뜰 때까지 대기)
```

이 Activator 메커니즘이 scale-to-zero의 핵심이며, 콜드 스타트라는 대가(theory·pitfalls)를 낳습니다. 이것을 이해하는 것이 이 모듈의 중심입니다.

## 18(KEDA)과의 관계 — 헷갈리기 쉬운 지점

```
KEDA(18): 이벤트 소스(Kafka lag 등)로 워크로드를 0→N (HPA 확장)
Knative: 요청(Serving)·이벤트(Eventing)로 서버리스 플랫폼

겹침: 둘 다 scale-to-zero, 이벤트 기반 스케일
차이:
  KEDA = 스케일러 (기존 Deployment를 이벤트로 스케일, 가벼움)
  Knative = 서버리스 플랫폼 (리비전·트래픽·Eventing까지, 무거움)
→ "그냥 이벤트로 스케일"이면 KEDA, "서버리스 플랫폼"이면 Knative
  (실제로 KEDA가 Knative보다 널리 쓰임 — 가벼워서)
```

theory에서 이 구분을 정확히 합니다. 18을 배웠으니 여기서 "왜 둘 다 있나"를 압니다.

## 08의 배포 전략이 여기서 — 리비전·트래픽

```
08에서 롤링·블루그린·카나리를 배웠습니다.
Knative는 이걸 기본 기능으로:
  코드 배포 = 새 Revision (불변)
  트래픽을 리비전에 % 분배:
    revision-1: 90%, revision-2: 10% (카나리)
  → 카나리·블루그린이 YAML 몇 줄 (24의 메시 트래픽 분할과 유사하지만 내장)
```

## 이 모듈의 판단 축

Knative는 강력하지만 무겁습니다. 판단이 필요합니다:

```
Knative가 맞는 경우:
  이식 가능한 서버리스가 필요 (멀티클라우드·온프레)
  scale-to-zero로 비용 절감 (드문드문 오는 워크로드)
  요청·이벤트 기반 + 카나리를 플랫폼으로

과한 경우:
  그냥 오토스케일이면 → HPA(08)나 KEDA(18)
  상시 트래픽이면 → scale-to-zero 이점 없음(콜드스타트만 손해)
  관리형 서버리스(Cloud Run은 Knative 기반)로 충분하면 → 그것
```

Cloud Run이 Knative API 기반이라는 점도 중요합니다 — Knative를 알면 Cloud Run을 알고, 이식성도 얻습니다.
