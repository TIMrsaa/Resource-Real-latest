# 자가 점검 퀴즈

**Q1.** 보안 지도의 축을 "기능"이 아니라 "시간선"으로 잡는 이유는? 각 시간대와 대표 도구를 말하세요.

**Q2.** "각 층은 자기 시간대만 방어한다"를 admission과 런타임의 관계로 설명하고, cicd 21의 어떤 명제와 같은가요?

**Q3.** OPA/Gatekeeper와 Kyverno의 설계 차이 네 가지와, 선택(또는 병용) 기준은?

**Q4.** cert-manager와 SPIFFE/SPIRE가 각각 증명하는 것과, 신원이 "숨은 척추"인 이유는?

**Q5.** Falco의 탐지 대상(무엇을 보는가)과 구조적 한계, 그리고 강제(enforcement)를 원할 때의 대안은?

**Q6.** lab-02에서 Kyverno를 통과한 `good` Pod가 실행 중 침해되면 어느 도구가 무엇을 보는가요?

**Q7.** in-toto와 TUF가 각각 다루는 문제와, cicd 21의 어느 개념의 뿌리인가요?

**Q8.** 정책 도구 도입의 이행 곡선과, failurePolicy가 "명시적 선택"인 이유는?

---

## 정답

**A1.** 기능 축(스캔·정책·탐지)으로 나열하면 도구들이 겹쳐 보여 공백이 드러나지 않습니다 — SBOM 스캔과 admission 이미지 검증은 둘 다 "이미지 검사"지만 작동 시점이 다릅니다. 시간선: ① 빌드 전 — 서명·SBOM·provenance(cosign, in-toto, TUF) ② 배포 시점 — admission 검증·정책(OPA/Gatekeeper, Kyverno) ③ 실행 중 — 런타임 탐지(Falco, Tetragon) + 관통축: 신원(cert-manager, SPIFFE/SPIRE)과 정책 엔진(OPA·Kyverno). 시간선의 힘은 감시되지 않는 구간을 드러내는 것입니다.

**A2.** admission은 API 요청(Pod 스펙)을 보고 배포를 거절할 수 있을 뿐, 통과한 Pod가 실행 중에 하는 행위는 전혀 보지 않습니다. 정상 서명·정상 스펙의 Pod가 0-day나 탈취된 자격증명으로 침해되면 admission의 기록은 깨끗합니다 — 그 순간을 보는 것은 시스템콜을 감시하는 Falco뿐입니다. cicd 21의 "서명은 빌드 이후 변조만 잡고 빌드 중 주입(SolarWinds)은 못 잡는다"와 같은 명제 — **방어는 층의 합이 아니라 곱**이고, 각 도구는 자기 시간대의 위협만 담당합니다.

**A3.** ① 정책 언어: rego(전용 언어, 학습 곡선) vs YAML/CRD(K8s 친숙). ② 적용 범위: 범용(K8s·CI conftest·Terraform·앱 인가) vs K8s 전용. ③ 능력: OPA는 복잡한 로직·다영역 통일, Kyverno는 validate 외에 generate·mutate와 서명 검증(verifyImages) 내장. ④ 진입 비용: rego 학습 vs 즉시. 기준: 조직 전체 정책을 한 언어로 통일하려면 OPA, K8s 정책만 필요하고 rego가 부담이면 Kyverno — 병용도 흔합니다(CI는 conftest, admission은 Kyverno). "어느 영역의 정책을 어느 언어로"가 실제 질문.

**A4.** cert-manager: 인증서라는 **물건**의 발급·갱신·회전 자동화(Issuer→Certificate→Secret) — 만료로 인한 장애를 구조적으로 제거. SPIFFE/SPIRE: 워크로드의 **신원** 자체 — 노드·워크로드 증명(attestation)을 거쳐 검증 가능한 SVID를 발급, "이 Pod가 정말 결제 서비스인가"에 암호학적으로 답합니다. 신원이 척추인 이유: 정책(누구를 허용?)·암호화(누구와 mTLS?)·감사(누가 했나요?)가 모두 "누구"에 의존하는데, 신원이 없으면 그 답이 IP·네임스페이스 같은 네트워크 경계의 신뢰로 대체되어 사칭에 취약해집니다.

**A5.** 대상: 시스템콜(eBPF 또는 커널 모듈) — 컨테이너 내 셸 실행, 민감 파일 읽기, 권한 상승, 예상 밖 아웃바운드 등을 규칙으로 판정. 한계: **탐지·경보이지 차단이 아닙니다**(행위는 이미 일어났습니다), 규칙 밖 행위는 못 봅니다, 경보에 반응하는 체계가 없으면 로그만 쌓입니다. 강제 대안: seccomp/AppArmor 프로파일(예방 층에서 시스템콜 자체를 제한), Tetragon·KubeArmor(eBPF/LSM 기반 런타임 강제) — 탐지(detection)와 강제(enforcement)는 다른 능력입니다.

**A6.** Kyverno는 아무것도 보지 않습니다 — 이미 admit했고, 이후의 API 요청이 없는 한 관여하지 않습니다. Falco가 봅니다: 컨테이너 안에서 `sh`가 spawn되는 순간(`Terminal shell in container`), `/etc/shadow`류 민감 파일 접근(`Read sensitive file`), 서비스 어카운트 토큰 접근 등 — 시스템콜 수준의 행위이므로 "정상 스펙의 Pod"라는 사실과 무관하게 관측됩니다. 이것이 문지기와 CCTV를 둘 다 두는 이유(lab-02 Step 7의 대비표).

**A7.** in-toto: 공급망 각 단계(누가 무엇을 어떤 재료로)의 증명을 **연쇄**로 묶어 최종 산출물까지의 무결성을 보증 — SLSA provenance의 이론적 뿌리(cicd 21의 `--provenance`가 만드는 그 증명서의 계보). TUF: 저장소·업데이트 배포의 신뢰 모델 — 키 침해 시의 복구, 롤백·프리즈 공격 방어 등 "업데이트를 어떻게 안전하게 받을 것인가"의 명세이며, Notary/레지스트리 서명과 sigstore의 설계에 흡수됐습니다.

**A8.** 이행 곡선: Audit(위반 기록만) → PolicyReport로 위반 목록 확보 → 팀별 소진 기간 → 신규 네임스페이스만 Enforce → 전체 Enforce + 명시적 예외(사유 포함). 처음부터 Enforce하면 기존 워크로드의 재시작·스케일아웃이 연쇄 거절되어 정책 자체의 신뢰가 무너집니다(cicd 21·24의 반복 교훈). failurePolicy: webhook이 죽었을 때 요청을 막을지(fail-closed — 보안 우선, 배포 전면 중단 위험) 통과시킬지(fail-open — 가용성 우선, 검증 없는 통과) — 보안과 가용성 사이의 트레이드오프를 조직이 명시적으로 선택해야 하며, 기본값에 맡기면 사고 당일에야 어느 쪽이었는지 알게 됩니다.
