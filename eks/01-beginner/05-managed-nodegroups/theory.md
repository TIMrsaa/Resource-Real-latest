# 이론 — 노드그룹 해부, AMI, 풀 설계, 업데이트

> **🌱 17세 눈높이 비유: 프랜차이즈 매장의 직원 채용 체계**
> - **노드그룹** = "홀 직원 2~4명 유지" 같은 **채용 정책** — 본사(EKS)가 정책을 관리
> - **ASG** = 정책을 집행하는 **채용 담당자** — 결원이 나면 자동으로 충원
> - **시작 템플릿** = **채용 공고+교육 매뉴얼** — 어떤 사람(인스턴스 타입)을 뽑아 어떻게 교육(userdata)할지
> - **AMI** = 신입의 **기본 소양**(OS) — 일반 학교 출신(AL2023) vs 특수 훈련소 출신(Bottlerocket: 군더더기 없음, 개조 불가)
> - **taint/label** = 부서 배치표 — "주방 자격증 있는 직원만 주방에"

---

## 1. 3층 구조 — EKS 객체 → ASG → EC2

```
EKS Nodegroup (정책: AMI/타입/min·max·desired/라벨/taint/업데이트 설정)
  └→ Auto Scaling Group (집행: 그 수를 유지, AZ 분산, 교체)
       └→ EC2 인스턴스들 (실물: 내 계정, 내 과금 — 모듈 01의 회색지대)
            └→ 부팅 시 nodeadm/부트스트랩이 클러스터에 조인 → kubectl get nodes
```

진단 함의: "노드가 안 늘어요/이상해요"는 층을 따라 내려갑니다 — ① Nodegroup health(issues 필드) ② ASG 활동 이력(쿼터/용량 부족이 여기 찍힘) ③ EC2 상태/시스템 로그(조인 실패). 모듈 26(트러블슈팅)의 단골 경로.

## 2. AMI 계열 — AL2023 vs Bottlerocket

| | AL2023 (기본) | Bottlerocket |
|---|---|---|
| 성격 | 범용 리눅스 | **컨테이너 전용 OS** (패키지 매니저/셸 없음) |
| 커스터마이즈 | nodeadm(YAML)로 유연 | 제한적 (TOML 설정만) — 그게 장점 |
| 보안 표면 | 보통 | 최소 (불변 루트, 자동 업데이트 친화) |
| 디버깅 | SSH/SSM 자유 | admin/control 컨테이너 경유 |
| 어울림 | 커스텀 요구, 익숙함 | 보안 우선, 표준 워크로드 (Auto Mode의 기반 — 04) |

> AL2는 수명 종료 흐름 — 신규는 AL2023 또는 Bottlerocket. (GPU 등 가속 워크로드는 전용 변형 AMI — 19)

### 시작 템플릿과 nodeadm

노드그룹에 시작 템플릿을 붙이면 커스터마이즈가 열립니다: 인스턴스 세부(EBS 크기/암호화, IMDSv2), 그리고 **userdata**. AL2023의 userdata는 `NodeConfig`(YAML — MIME 멀티파트):

```yaml
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  kubelet:
    config:                      # kubelet 설정 주입 (k8s 26의 그 설정!)
      maxPods: 58
    flags: ["--node-labels=team=payments"]
```

→ "노드 부팅 커스터마이즈"의 표준 통로. 단, 손대는 만큼 Auto Mode와 멀어집니다(04의 트레이드오프).

## 3. 풀 설계 — 라벨과 taint의 콤보 (k8s 12/34의 실전)

```yaml
# ClusterConfig 발췌 — 용도별 풀의 정석
managedNodeGroups:
- name: general                  # 기본 풀: taint 없음 (아무나 입주)
  instanceType: t3.medium
  labels: { pool: general }
- name: memory-heavy             # 전용 풀: taint로 잠금
  instanceType: r7g.large        # (Graviton — 19)
  labels: { pool: memory }
  taints: [{ key: pool, value: memory, effect: NoSchedule }]
- name: spot-batch               # Spot 풀: 배치/내결함 워크로드용
  instanceTypes: [t3.large, t3a.large, m5.large]   # ★ 다양화가 Spot의 생명
  spot: true
  labels: { pool: spot }
  taints: [{ key: pool, value: spot, effect: NoSchedule }]
```

설계 원칙:
- **기본 풀 하나는 taint 없이** (시스템/잡동사니의 거처)
- 전용 풀은 **taint(밀어냄) + 라벨(끌어당김) 세트** — taint만으론 "전용"이 안 됩니다(k8s 34 lab-02의 그 구멍: 다른 Pod의 toleration 복제까지 막으려면 admission)
- Spot 풀은 인스턴스 타입을 **여러 개** — 한 타입의 Spot 풀 고갈에 대비 (중단 신호 처리는 17/22)

## 4. 업데이트와 복구

### 롤링 업데이트 (k8s 35의 그 드레인을 누가 하나)

`update-nodegroup-version` 시: 새 AMI 노드 증설 → 구 노드 cordon+drain(**PDB 존중**) → 종료, 를 반복.

```yaml
updateConfig:
  maxUnavailable: 1        # 동시에 비울 노드 수 (또는 maxUnavailablePercentage)
```

- 크게 = 빠르고 거칠게 / 작게 = 느리고 안전하게 — 클러스터 크기와 PDB 여유로 결정
- PDB가 빡빡하면 업데이트가 **멈춥니다** (k8s 35 lab-02의 데드락 — 여기서 재회)

### 노드 자동 복구 (node repair)

`nodeRepairConfig: { enabled: true }` — NotReady 등 비정상 노드를 자동 교체. k8s 38 #10(노드 장애 진단)의 1차 대응이 자동화되는 것 — 단 "왜 죽었나"의 추적은 여전히 내 일(반복되면 교체가 아니라 원인 제거).

## 5. 소스/도구에서 확인하기

- 노드그룹 문서: https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html
- nodeadm 스펙: https://awslabs.github.io/amazon-eks-ami/nodeadm/
- Bottlerocket: https://bottlerocket.dev/
- AMI 릴리스 노트: github.com/awslabs/amazon-eks-ami (AL2023) / bottlerocket-os/bottlerocket

## 요약 카드

| 질문 | 답 |
|------|----|
| 노드그룹의 3층? | Nodegroup(정책) → ASG(집행) → EC2(실물) |
| "노드가 안 늘어요" 진단 경로? | nodegroup health → ASG 활동 이력 → EC2 로그 |
| AMI 기본 선택? | AL2023 (커스텀 유연) / 보안 우선이면 Bottlerocket |
| 전용 풀의 공식? | taint(밀어냄) + label(끌어당김) + (완전 격리는 admission) |
| Spot 풀의 생명? | 인스턴스 타입 다양화 |
| 업데이트 속도 손잡이? | updateConfig.maxUnavailable (+PDB가 브레이크) |
