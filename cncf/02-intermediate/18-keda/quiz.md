# 자가 점검 퀴즈

**Q1.** KEDA의 3컴포넌트와 각 역할은? "스케일 계산은 누가 하는가"에 답하세요.

**Q2.** ScaledObject를 만들면 클러스터에 무엇이 생기나요? HPA는 무엇을 통해 메트릭을 얻나요?

**Q3.** activationThreshold와 threshold의 차이와, 각각을 잘못 설정하면 생기는 증상은?

**Q4.** scale-to-zero의 콜드스타트를 구성하는 요소들과, 사용자 대면 경로의 판정 질문은?

**Q5.** ScaledObject 워커의 필수 3종 조건은? 없으면 무슨 일이 생기나요?

**Q6.** ScaledObject와 ScaledJob의 선택 기준과, 각각을 잘못 선택했을 때의 실패 모드는?

**Q7.** "KEDA를 깔았는데 Pod가 안 뜬다"의 진단 4층과 각 층의 확인 명령은?

**Q8.** KEDA의 신뢰 경계(07)와 fallback이 방어하는 시나리오는?

---

## 정답

**A1.** operator(ScaledObject watch, 스케일러 폴링, activation 판단으로 0↔1 전환, HPA 생성·관리), metrics-adapter(External Metrics API 서버 — HPA의 질의에 외부 메트릭으로 답합니다), admission-webhooks(설정 검증 — 같은 대상에 중복 ScaledObject 등 차단). **스케일 계산(1↔max)은 여전히 HPA가 합니다** — KEDA는 통역사이자 0↔1 담당입니다.

**A2.** `keda-hpa-<scaledobject-name>`이라는 HPA 오브젝트가 자동 생성됩니다(metrics type: External). HPA는 표준 `external.metrics.k8s.io/v1beta1` API로 메트릭을 질의하고, 그 APIService가 keda-metrics-apiserver를 가리킵니다 — 즉 HPA는 KEDA를 모르고 표준 API로 물을 뿐이며, 답하는 쪽이 KEDA입니다.

**A3.** `threshold`는 HPA의 target = "Pod 하나가 감당할 양"이고 `desired = ceil(metric/threshold)`에 쓰입니다. `activationThreshold`는 0→1 전환의 문턱으로 KEDA가 판단합니다. activationThreshold가 너무 높으면 "메트릭이 있는데 Pod가 0"이고, 지정하지 않으면 기본 0이라 메트릭이 0보다 크기만 하면 즉시 활성되어 노이즈에 반응합니다. threshold가 너무 낮으면 적은 메트릭에도 replicas가 과도하게 늘어납니다.

**A4.** 폴링 간격(최대 pollingInterval만큼 감지 지연) + Pod 스케줄 + 이미지 pull(캐시 없으면 수십 초) + 앱 부팅 + (노드가 없으면) Karpenter의 노드 프로비저닝 1~2분. 판정 질문: **첫 요청이 수 초를 기다려도 되는가.** 이벤트 워커(지연 허용)는 Yes → minReplicaCount 0 가능. 사용자 대면 동기 경로는 대개 No → minReplicaCount ≥ 1, 비용 절감은 다른 축에서.

**A5.** ① SIGTERM 핸들러(새 메시지 수신 중단, 진행 중인 것만 마무리) ② `terminationGracePeriodSeconds` ≥ 최대 처리 시간 ③ 처리 완료 후에만 ack(auto_ack 금지). 없으면: 스케일다운 시 처리 중이던 Pod가 강제 종료되며 이미 ack된 메시지가 영원히 사라집니다 — 유실이 로그에도 남지 않고, 시스템은 "처리 완료"로 기록합니다(사고 사례의 3,400건).

**A6.** ScaledObject: 워커가 상주하며 큐를 소비 — 짧은 메시지를 대량 처리할 때 효율적. ScaledJob: 메시지(들)마다 Job 생성, 처리 후 Pod 종료 — 긴 작업(수 분~시간), 격리, K8s 수준 재시도(backoffLimit)가 필요할 때. 잘못된 선택: 긴 작업에 ScaledObject → 스케일다운 시 유실 또는 스케일다운이 끝나지 않음. 짧고 많은 메시지에 ScaledJob → Pod 생성 폭주로 API 서버·스케줄러 과부하(`scalingStrategy: accurate`·maxReplicaCount로 완충하되 근본은 모델 선택).

**A7.** ① 스케일러가 신호를 읽는가 — `kubectl get scaledobject -o jsonpath='{.status.conditions}'`, operator 로그, 인증(TriggerAuthentication). ② metrics-adapter가 답하는가 — `kubectl get --raw /apis/external.metrics.k8s.io/v1beta1/...`. ③ HPA가 계산·확대하는가 — `kubectl describe hpa keda-hpa-<name>`(Metrics·Conditions·behavior·max). ④ Pod가 스케줄되는가 — `kubectl get pod -o wide`, FailedScheduling 이벤트, 노드 층(Karpenter·자원·taint). "안 뜬다"의 대부분은 ③ 또는 ④입니다.

**A8.** 신뢰 경계: KEDA operator가 TriggerAuthentication의 자격증명으로 큐·DB·Prometheus에 직접 접속해 폴링합니다 — keda 네임스페이스 침해는 그 자격증명 전부의 침해이므로 최소 권한(읽기 전용 사용자)·podIdentity(IRSA)·Secret 접근 제한이 필요합니다. fallback(`{failureThreshold: N, replicas: M}`)이 방어하는 시나리오: 외부 시스템(큐·Prometheus)이 장애로 메트릭을 못 주면 스케일 결정이 멈추고 replicas가 0으로 떨어져 워크로드가 전멸할 수 있습니다 — fallback은 그때 안전 replicas를 유지합니다. 함께 `keda_scaler_errors_total` 알람 필수.
