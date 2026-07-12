# 학습 가이드 — KEDA는 HPA의 대체가 아니라 통역사입니다

## 오해를 먼저 부숩니다

"KEDA를 쓰면 HPA를 안 쓴다"는 흔한 오해입니다. 실제로는:

```
ScaledObject를 만들면 → KEDA가 그것을 보고 → HPA 오브젝트를 자동 생성합니다
                                              (이름: keda-hpa-<scaledobject>)
HPA는 external metrics API로 KEDA의 metrics-adapter에게 묻습니다:
   "큐 길이가 지금 얼마인가요?"
KEDA metrics-adapter가 답합니다: "1,347"
HPA가 계산합니다: target=100 이므로 desired = ceil(1347/100) = 14 replicas
```

즉 **스케일 계산은 여전히 HPA가 합니다.** KEDA가 하는 일은 두 가지입니다: ① 외부 세계의 신호를 HPA가 이해하는 메트릭으로 번역(통역사) ② HPA가 구조적으로 못 하는 0↔1 전환을 직접 처리(activation).

이 구조를 알면 진단이 쉬워집니다. "Pod가 안 늘어난다"는 세 층 중 하나입니다: 스케일러가 신호를 못 읽나(인증·연결), metrics-adapter가 답을 못 주나, 아니면 HPA의 계산·behavior가 막나.

## scale-to-zero의 진짜 비용

`minReplicaCount: 0`은 매력적입니다 — 이벤트가 없으면 Pod가 0개, 비용도 0. 대가는 **첫 요청의 지연**입니다:

```
0 → 1 전환 시간 = KEDA 폴링 간격(최대 pollingInterval)
                 + Pod 스케줄 시간
                 + 이미지 pull (캐시 없으면 수십 초)
                 + 앱 부팅 시간
                 + (노드가 없으면) Karpenter의 노드 프로비저닝 1~2분
```

이벤트 워커(지연 허용)에는 훌륭하고, 사용자 대면 동기 요청에는 재앙입니다. 03에서 Wasm이 겨냥한다고 했던 콜드스타트 문제가 여기서 실무 결정으로 돌아옵니다.

## ScaledObject vs ScaledJob — 처리 모델의 차이

```
ScaledObject: 장기 실행 워크로드(Deployment)를 스케일 — 워커가 계속 살아서 큐를 폴링
ScaledJob:    메시지마다(또는 N개마다) Job을 하나씩 생성 — 처리 후 Pod 종료
```

메시지 처리가 오래 걸리고(수 분~시간), 재시도·격리가 중요하며, 워커가 상태를 갖지 않는다면 ScaledJob이 맞습니다. 짧은 메시지를 대량으로 처리한다면 ScaledObject가 효율적입니다. 이 선택을 잘못하면 "잡이 중간에 죽어 메시지가 유실"되거나 "Pod가 초당 수십 개씩 생성되어 API 서버가 비명"을 지릅니다.

## Karpenter와의 직렬 관계

10에서 그렸던 그림을 실험으로 확인합니다: KEDA가 Pod를 늘리면 → 자원이 부족하면 Pending → Karpenter가 노드를 만듭니다. 두 오토스케일러가 **각자 자기 층만** 본다는 사실이 진단의 출발점입니다.
