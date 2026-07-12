# 자가 점검 퀴즈

**Q1.** Alpha/Beta/GA의 기본 활성 여부와, EKS 학습자가 의존할 수 있는 단계는?

**Q2.** 새 K8s 버전이 나왔을 때 기능을 발굴하는 4단계 루틴은?

**Q3.** in-place resize의 명령(서브리소스)과, Deployment 환경에서의 한계는?

**Q4.** "exit code 42는 재시도하지 말고 즉시 실패" + "노드 축출은 재시도 카운트 제외"를 선언하는 Job 기능은?

**Q5.** Downward API로 얻을 수 있는 정보 3가지와 대표 활용처는?

**Q6.** audience 지정 projected SA 토큰이 푸는 보안 문제와, 그것이 토대인 EKS 기능은?

**Q7.** Topology Aware Routing의 발동 조건과 전제 조건은?

**Q8.** STATUS가 `SchedulingGated`인 Pod의 의미와 해소 주체는?

---

## 정답

**A1.** Alpha: 기본 off (관리형에선 사실상 사용 불가). Beta: 기능별(1.24+ 신규는 대부분 off). GA: **기본 on, 게이트 제거.** EKS 의존은 **GA**(와 EKS가 켜둔 Beta)만.

**A2.** ① 공식 릴리스 블로그 정독 ② Feature Gates 표에서 단계 변화 확인 ③ 관심 기능의 KEP로 설계 의도 파악 ④ `kubectl explain`으로 내 클러스터 실제 지원 확인.

**A3.** `kubectl patch pod <p> --subresource=resize ...`. 한계: Pod 객체만 바꾸므로 Deployment **template은 그대로** — 다음 롤링 업데이트에서 원복됩니다 (영구 변경은 template 수정).

**A4.** **podFailurePolicy** — `onExitCodes`(42 → FailJob)와 `onPodConditions`(DisruptionTarget → Ignore) 규칙.

**A5.** Pod 이름/네임스페이스/라벨, 노드 이름, 자기 컨테이너의 requests/limits 등. 활용: 로그/메트릭에 신원 태깅, 런타임 튜닝(스레드 수 = CPU limit), 사이드카 설정.

**A6.** 기본 토큰을 외부에 주면 그 외부가 우리 API 서버에 **재전송**할 수 있는 문제 — audience를 외부 서비스로 지정하면 API 서버용으로는 무효가 됩니다(수신자 구속). 이 메커니즘 위에 **IRSA**(audience=sts.amazonaws.com)가 서 있습니다.

**A7.** 발동: Service에 `service.kubernetes.io/topology-mode: Auto` annotation + EndpointSlice에 zone hints가 실제로 부여됨. 전제: 백엔드가 **AZ별로 충분히 균형** 분산(아니면 안전하게 미발동) — topologySpread와 세트.

**A8.** `spec.schedulingGates`가 남아 있어 스케줄러 큐 입장 자체가 보류된 상태. 해소 주체는 게이트를 넣은 **외부 시스템**(배치 큐/승인 워크플로)이 게이트를 제거하는 것 — 자원/taint 디버깅 대상이 아닙니다.
