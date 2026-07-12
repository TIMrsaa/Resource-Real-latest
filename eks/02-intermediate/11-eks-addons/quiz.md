# 자가 점검 퀴즈

**Q1.** 관리형 애드온의 "진실의 원천"과 클러스터 안 실물의 관계는?

**Q2.** "kubectl로 고쳤는데 원복됐다"의 기술적 원리는? (k8s 24 용어로)

**Q3.** 애드온 버전 선택의 기준과 latest의 위험은?

**Q4.** configuration-values의 두 가지 운영상 장점은?

**Q5.** OVERWRITE / PRESERVE / NONE 각각의 자리와 PRESERVE의 함정은?

**Q6.** 클러스터 업그레이드에서 애드온의 위치와 그 이유는?

**Q7.** 애드온 업그레이드가 UPDATE_FAILED — 진단과 복구 수단은?

**Q8.** 관리형을 버리고 자가 관리로 전환해도 되는 조건은?

---

## 정답

**A1.** 진실 = EKS Addon 객체(버전+configuration-values). 클러스터 안의 DaemonSet/Deployment는 EKS가 reconcile하는 **출력물** — 출력물을 고치는 건 원본 없는 수정입니다 (k8s 39 GitOps와 동형).

**A2.** Server-side apply의 **필드 소유권** — EKS가 field manager로 소유한 필드를 kubectl이 덮으면, 다음 reconcile/업데이트에서 EKS가 소유권을 행사해 회복(OVERWRITE). `--show-managed-fields`로 owner 확인 가능.

**A3.** 대상 K8s 버전의 **default**(describe-addon-versions에서 조회 — AWS 검증 버전). latest의 위험: 현 CP 미지원 가능, 갓 릴리스 회귀 가능 — 특정 픽스가 필요할 때만 의식적으로.

**A4.** ① 스키마 검증 — 오타/잘못된 키가 **시끄럽게 거부**됨(조용한 무시 없음) ② 진실의 원천 단일화 — 업데이트에도 설정이 유지되고, ClusterConfig에 넣으면 IaC/DR까지 연결.

**A5.** OVERWRITE: 평시 표준(EKS 정의값 강제 — 드리프트 청소). PRESERVE: 자가 관리→관리형 **편입 시** 기존 값 보존용. NONE: 충돌을 실패로 드러내고 싶을 때. PRESERVE 함정: 보존값은 비공식 상태 — 인수 후 스키마로 정식화까지 해야 마이그레이션 완료.

**A6.** CP → **애드온** → 노드. CP가 먼저 올라간 뒤 애드온을 새 CP의 default로 맞춰 CP-애드온 호환을 확보하고, 그 다음 노드를 교체해 노드-애드온(kube-proxy 등) 정합을 맞춥니다 (skew 관리 — k8s 35).

**A7.** describe-addon의 status/health.issues + 해당 컴포넌트 로그(예: vpc-cni면 ipamd — 07). 복구: 애드온은 **버전 지정 롤백 가능**(update-addon --addon-version <직전>) — CP와 달리 가역이라 부담이 작습니다.

**A8.** 필요한 설정이 (최신 버전의) 스키마에도 없고, 그 요구가 검증된 실제 필요일 때 — 마지막 수단. 전환 시 버전 호환 검증/업그레이드 보조가 내 일이 됨을 수용하고, 헬름+GitOps(k8s 17/39)로 관리 체계를 갖춘 후에.
