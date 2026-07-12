# 자가 점검 퀴즈 (고급 트랙 졸업 시험 겸용)

**Q1.** 컨테이너 장악 후 공격자의 4단계 행보와, 각 단계를 끊는 이 커리큘럼의 모듈/설정을 매핑하세요.

**Q2.** `capabilities: {drop: ["ALL"]}`이 일반 웹 앱을 망가뜨리지 않는 이유는?

**Q3.** runAsNonRoot: true인데 이미지가 root 전제일 때의 증상과 근본/임시 해법은?

**Q4.** PSA의 3표준×3모드를 설명하고, 운영 정석 라벨 조합을 쓰라.

**Q5.** PSA enforce 라벨을 붙여도 기존 위반 Pod가 사는 이유와, 그것이 운영에 주는 의미(양면)는?

**Q6.** `hostUsers: false`가 바꾸는 것을 uid 관점에서 설명하세요.

**Q7.** kube-system이 privileged 등급인 것은 문제인가요? 그 구조의 원칙은?

**Q8.** (종합) restricted 통과 Pod의 필수 설정 5가지를 암기로 나열하세요.

---

## 정답

**A1.** ① 컨테이너 내 권한 상승 — runAsNonRoot/allowPrivilegeEscalation:false (이 모듈) ② 호스트 탈출 — drop ALL/seccomp/privileged 금지/hostUsers:false (이 모듈) ③ 클러스터 권한 탈취 — SA 토큰 최소화/RBAC (모듈 11) ④ 횡적 이동 — NetworkPolicy (모듈 15).

**A2.** capability는 **특권 시스템콜**(raw socket, mount, ptrace...)의 허가증이고, 일반 앱의 일(TCP/UDP 소켓 통신, 파일 IO)은 특권이 필요 없기 때문. 예외(<1024 포트 바인딩)만 개별 add.

**A3.** 증상: `CreateContainerConfigError`(기동 거부) 또는 기동 후 자기 파일 permission denied. 근본: 이미지에 `USER`와 올바른 파일 소유권을 굽습니다. 임시: fsGroup/runAsUser 조정, 레거시 최후 절충은 user namespaces.

**A4.** 표준: privileged(무제한)/baseline(알려진 상승 경로 차단)/restricted(모범사례 강제). 모드: enforce(거부)/warn(경고)/audit(기록). 정석: `enforce=baseline` + `warn=restricted` + `audit=restricted` → 준비되면 enforce를 restricted로 승격.

**A5.** PSA는 admission(생성 시점 검사)이라 **소급 적용이 없습니다.** 양면: 라벨 부착이 무중단이라 도입이 안전합니다(+) / "라벨 = 안전"이 아니므로 기존 워크로드 감사·교체까지 해야 실제 강화입니다(−).

**A6.** 컨테이너 namespace 안의 uid(0 포함)가 호스트의 **비특권 고유 대역**(예: 165536+)으로 매핑됩니다 — 컨테이너 root가 탈출해도 호스트에서는 아무 특권 없는 유저. uid_map 파일로 확인 가능.

**A7.** 문제가 아니라 설계입니다 — CNI/CSI/kube-proxy는 노드 조작이 **본업**이라 특권이 필요합니다. 원칙: **특권의 필요를 전용 ns로 격리**하고 그 ns만 등급을 낮춥니다. 일반 워크로드 ns의 privileged가 발견 사항입니다.

**A8.** ① `runAsNonRoot: true` (+runAsUser) ② `allowPrivilegeEscalation: false` ③ `capabilities: {drop: ["ALL"]}` ④ `seccompProfile: {type: RuntimeDefault}` ⑤ 금지 항목 부재(privileged/hostPath/hostNetwork/hostPID 등). (+권장: readOnlyRootFilesystem, automountServiceAccountToken: false)
