# 이론 — 6관문, 시크릿의 외부화, 탐지와 대응

> **🌱 17세 눈높이 비유: 성(城)의 방어**
> 성문 하나에 모든 걸 걸지 않습니다:
> - **해자와 검문(이미지 스캔)** = 성 안에 들일 물자를 미리 검사 — 썩은 게 들어오면 안이 병듭니다
> - **성벽(노드·PSA)** = 들어온 자가 성벽을 타 넘지 못하게 — privileged/hostPath는 사다리입니다
> - **내성 구획(NetworkPolicy)** = 한 구역이 함락돼도 옆 구역으로 못 넘어가게(측면 이동 차단)
> - **금고(Secrets Manager)** = 열쇠를 성 안에 두지 않습니다 — 성이 함락돼도 금고는 은행에
> - **파수꾼(GuardDuty·감사 로그)** = "성문을 누가 새벽에 열었나"를 늘 기록하고 이상하면 종을 칩니다
> - **비상 계단 봉쇄(IMDS 차단)** = 침입자가 왕의 인장(노드 IAM 역할)에 손대지 못하게 — EKS 침해의 고전적 경로

---

## 1. 6관문 지도 — 부품과 AWS의 매핑

| 관문 | 막는 것 | k8s 부품 | AWS 층 |
|------|--------|---------|--------|
| ① 공급망 | 취약·악성 이미지 | admission(23)의 이미지 정책 | ECR 스캔, 서명(cosign) |
| ② 신원·권한 | 과잉 권한 | RBAC(11), SA | IRSA/Pod Identity 최소권한(09) |
| ③ 워크로드 | 권한 상승·탈출 | **PSA/PSS**(32), seccomp | Bottlerocket(축소 OS — 05) |
| ④ 네트워크 | 측면 이동·유출 | NetworkPolicy(15·18) | SG, 프라이빗 API 엔드포인트 |
| ⑤ 시크릿 | 자격증명 탈취 | Secret(약점!) | **Secrets Manager CSI**, KMS 봉투암호화 |
| ⑥ 탐지·감사 | "이미 뚫렸다" | 감사 로그(21) | **GuardDuty EKS Protection**, CloudTrail |

세로로 읽으면 부품 목록, **가로로 읽으면 하나의 공격 경로**입니다 — 공격자는 ①에서 시작해 ⑥으로 갑니다. 방어는 각 칸에 하나씩.

## 2. k8s Secret의 진실과 그 대응 사다리

```
Secret은 "암호화"가 아닙니다 — etcd에 base64(=인코딩)로. 방어 사다리:
① RBAC 최소화        get secrets 권한이 곧 열람 (11의 escalation 관점)
② etcd 저장 암호화    EKS는 KMS 봉투암호화 지원 — 켜면 etcd 유출 시 방어
③ 외부화 (이 모듈)    Secrets Manager/Parameter Store에 두고 CSI로 마운트
                     → 클러스터 안에 원본이 없다 + 자동 회전 + AWS 감사 로그
```

CSI 드라이버의 구조:

```
SecretProviderClass (CRD: "어느 시크릿을, 어떻게 마운트")
 → secrets-store CSI driver + aws provider (DaemonSet)
 → Pod의 volume으로 마운트 (tmpfs — 디스크에 안 남음)
 → 권한: 그 Pod의 SA ← IRSA/Pod Identity로 Secrets Manager 읽기 (09)
옵션: syncSecret으로 k8s Secret도 생성(레거시 앱 호환 — 단 외부화의 이점 일부 반납)
```

**회전(rotation)**: Secrets Manager가 회전하면 CSI가 마운트 파일을 갱신(rotation poll) — 앱이 파일을 다시 읽으면 재배포 없이 새 자격증명. 앱이 시작 시 한 번만 읽는다면? 회전은 재시작을 요구합니다 — 설계 시 확인할 것.

## 3. GuardDuty EKS Protection — 두 개의 눈

| | Audit Log Monitoring | Runtime Monitoring |
|---|---|---|
| 원천 | CP 감사 로그(자동 — 우리가 켤 필요 없음) | 노드/Pod의 eBPF 에이전트(애드온) |
| 탐지 예 | 익명 접근 허용, 과도한 권한 부여, exec 남용, 알려진 악성 IP에서의 API 호출 | 컨테이너 탈출 시도, 암호화폐 채굴, 의심스러운 셸·바이너리, C2 통신 |
| 비용 | 계정 전역 요금 | + 에이전트 리소스 |

**탐지는 방어가 아닙니다** — Finding이 SNS/EventBridge로 나가서 사람이나 자동화가 행동해야 가치가 됩니다. 대응 자동화의 뼈대:

```
GuardDuty Finding → EventBridge → Lambda/Step Functions
   → 격리: 해당 Pod에 deny-all NetworkPolicy 적용 + 노드 cordon + 스냅샷(포렌식)
   → 통보: 보안 채널 + 티켓 자동 생성
```

## 4. IMDS — EKS 침해의 고전 경로

```
공격자가 Pod에서 curl 169.254.169.254 → 노드의 IAM 역할 자격증명 획득
  → 그 역할이 넓으면(예: ec2:*, s3:*) 클러스터 밖 AWS까지 장악
```

차단 3중:

1. **hop limit = 1** (인스턴스 메타데이터 옵션) — 컨테이너(1홉 추가)에서 접근 불가
2. IMDSv2 강제(토큰 필요) — 단순 SSRF 차단
3. 노드 역할 최소화 + 워크로드는 IRSA/Pod Identity로(09) — "노드 역할을 훔쳐도 별게 없게"

## 5. 감사 로그의 보안 재독 (21의 다른 얼굴)

업그레이드 preflight의 도구였던 감사 로그는 보안에선 **수사 자료**입니다. 필수 감시 쿼리(12의 Logs Insights):

```
- system:anonymous / system:unauthenticated 의 성공 요청 (있으면 즉시 사고)
- exec / attach / port-forward 사용 (누가 언제 어느 Pod에)
- ClusterRoleBinding 생성·수정 (권한 상승의 발자국 — 11)
- secrets 대량 조회 (한 SA가 짧은 시간에 다수 get)
```

## 6. 소스/도구에서 확인하기

- secrets-store-csi-driver: https://github.com/kubernetes-sigs/secrets-store-csi-driver + aws provider
- GuardDuty EKS: AWS 문서 "EKS Protection" (탐지 목록 = 위협 모델 카탈로그)
- EKS Best Practices Guide(보안): https://aws.github.io/aws-eks-best-practices/security/docs/
- kubescape/kube-bench: CIS 벤치마크 스캐너 — 관문 점검 자동화

## 요약 카드

| 질문 | 답 |
|------|----|
| 6관문? | 공급망·신원·워크로드·네트워크·시크릿·탐지 |
| k8s Secret의 진실? | 암호화 아닌 인코딩 — RBAC→KMS 암호화→외부화(CSI) 사다리 |
| CSI의 이점? | 원본이 클러스터 밖 + tmpfs 마운트 + 자동 회전 + AWS 감사 |
| GuardDuty 두 눈? | 감사 로그 모니터링 / 런타임(eBPF) |
| 탐지의 조건? | Finding → EventBridge → **자동 격리·통보** (탐지≠방어) |
| IMDS 3중 차단? | hop limit 1, IMDSv2, 노드 역할 최소화(+IRSA) |
