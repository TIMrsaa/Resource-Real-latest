# 흔한 함정 5선

## 1. graceful shutdown 없이 scale-to-zero

큐가 비면 KEDA가 Pod를 0으로 내립니다 — 그 순간 처리 중이던 메시지는 어떻게 되는가요? 워커가 SIGTERM을 무시하고, `terminationGracePeriodSeconds`가 처리 시간보다 짧고, `auto_ack=True`로 미리 ack했다면 **메시지는 조용히 사라집니다**. 필수 3종: ① SIGTERM 핸들러(새 메시지 수신 중단, 진행 중인 것만 마무리) ② gracePeriod ≥ 최대 처리 시간 ③ 처리 완료 후에만 ack. 이것 없이 scale-to-zero를 켜는 것은 "가끔 주문이 사라지는 시스템"을 만드는 것이고, 유실은 로그에도 남지 않습니다.

## 2. 사용자 대면 경로에 minReplicaCount: 0

콜드스타트는 폴링 간격 + 스케줄 + 이미지 pull + 앱 부팅이고, 노드까지 없으면 Karpenter의 1~2분이 더해집니다(theory §5). 이벤트 워커에는 훌륭하지만 동기 HTTP 요청 경로에서는 첫 사용자가 수십 초를 기다립니다(또는 타임아웃). 판정 질문: **첫 요청이 수 초를 기다려도 되는가.** 아니라면 minReplicaCount ≥ 1이고, 비용 절감은 다른 축(오버프로비저닝 제거, Spot, Karpenter의 consolidation)에서 찾아라. Knative의 스케일 투 제로도 같은 대가를 집니다(08).

## 3. threshold와 activationThreshold를 혼동

`threshold`는 HPA의 target — "Pod 하나가 감당할 양"이고 replicas 계산에 쓰입니다(`ceil(metric/threshold)`). `activationThreshold`는 0→1 전환의 문턱이고 KEDA가 판단합니다. 이것을 혼동하면 "메트릭이 있는데 Pod가 0"(activationThreshold가 너무 높음)이나 "메트릭이 조금만 있어도 Pod가 잔뜩"(threshold가 너무 낮음)이 됩니다. 그리고 `activationThreshold`를 안 주면 기본 0이라 **메트릭이 0보다 크기만 하면 즉시 활성**됩니다 — 노이즈에 반응하는 시스템이 됩니다.

## 4. ScaledObject를 긴 작업에 사용

메시지 처리에 10분이 걸리는데 ScaledObject로 워커를 스케일하면, 스케일다운 시 처리 중인 워커가 죽거나(유실) gracePeriod 10분을 기다려야 합니다(스케일다운이 영원히 안 끝남). 이런 워크로드는 **ScaledJob**이 답입니다 — 메시지마다 Job을 만들고, 잡이 완료될 때까지 Pod는 안전하며, 실패는 `backoffLimit`으로 재시도됩니다. 반대 실수도 있습니다: 초당 수백 개의 짧은 메시지에 ScaledJob을 쓰면 Pod 생성이 폭주해 API 서버와 스케줄러가 비명을 지릅니다(`scalingStrategy: accurate`와 `maxReplicaCount`로 완충하되, 근본은 모델 선택).

## 5. fallback 없이 외부 시스템 장애를 맞음

RabbitMQ가 죽거나 Prometheus가 응답을 못 하면 KEDA의 스케일러가 실패합니다 — 기본 동작에서는 메트릭을 못 얻으니 스케일 결정이 멈추고, 상황에 따라 **replicas가 0으로 떨어져 아무것도 처리하지 못하는** 상태가 될 수 있습니다. 외부 시스템 장애가 워크로드 전멸로 번지는 것입니다. `spec.fallback: {failureThreshold: 3, replicas: N}`으로 안전 replicas를 지정하고, `keda_scaler_errors_total`을 알람으로 걸어라. 그리고 KEDA operator가 큐·DB·Prometheus 자격증명을 가진 주체라는 것(07의 신뢰 경계)을 기억해 최소 권한·podIdentity로 운영하세요.

## 실무 사고 사례

> 한 회사가 이미지 처리 파이프라인을 KEDA로 자동화했습니다 — SQS 큐에 작업이 쌓이면 워커 Deployment가 0에서 최대 100까지 늘어나는 구조였고, ScaledObject의 `value: 10`(Pod 하나가 메시지 10개)으로 설정했습니다. 여섯 달간 완벽했습니다. 문제는 블랙프라이데이에 왔습니다. 트래픽 급증으로 큐에 12만 개의 메시지가 쌓였고, KEDA는 정직하게 계산했습니다: 120,000 ÷ 10 = 12,000 → maxReplicaCount인 100으로 제한. 100개 Pod가 요청됐고, 노드가 없어 Pending이 됐고, Karpenter가 노드를 만들기 시작했습니다. 여기까지는 설계대로였습니다. 사고는 다른 곳에서 터졌습니다: 이미지 처리 작업이 평균 4분 걸렸는데, 워커가 SIGTERM을 무시하고 있었습니다(`auto_ack=True`로 메시지를 받자마자 ack했습니다). 큐가 잠시 줄어들 때마다 KEDA가 스케일다운했고, 처리 중이던 Pod들이 30초 후 강제 종료되며 **그 메시지들이 영원히 사라졌습니다.** 최종 집계: 처리됐다고 기록된 메시지 12만 개 중 약 3,400개의 결과물이 존재하지 않았습니다 — 고객의 이미지가 처리되지 않은 채 "완료"로 표시된 것입니다. 발견은 사흘 뒤 고객 문의로였습니다. 개선은 네 가지였습니다: ① `auto_ack` 제거, 처리 완료 후 ack. ② SIGTERM 핸들러 + `terminationGracePeriodSeconds: 300`(최대 처리 시간). ③ **모델 전환** — 4분짜리 작업은 ScaledObject가 아니라 ScaledJob이 맞았습니다(잡은 완료까지 종료되지 않습니다). ④ `fallback`과 `keda_scaler_errors_total` 알람. 회고 문장: "우리는 오토스케일러를 믿었는데, **오토스케일러가 지키는 것은 replicas이지 우리의 메시지가 아니었다**" — 스케일링은 워크로드의 수명주기를 흔드는 행위이고, 그 흔들림을 견디는 것은 앱의 책임입니다.
