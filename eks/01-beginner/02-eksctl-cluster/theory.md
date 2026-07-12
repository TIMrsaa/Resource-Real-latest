# 이론 — ClusterConfig, 인증 경로, Access Entries

> **🌱 17세 눈높이 비유: 회원제 클럽의 입장 시스템**
> - **eksctl 설정 파일** = 클럽 설계도 — "홀 크기, 출입구 수, 직원 수"를 문서로 (말로 시키면 다음에 똑같이 못 짓습니다)
> - **get-token** = 신분증을 정부(AWS STS)가 실시간 보증하는 것 — 클럽이 자체 회원증을 안 만들고 "주민등록증 확인"으로 끝냅니다 (비밀번호 보관 부담 0)
> - **access entry** = 클럽의 게스트 명단 — "정부 신분증의 이 이름은 우리 클럽의 VIP다"라는 매핑
> - **RBAC** = 입장 후 구역 권한 — VIP여도 주방(kube-system)은 못 들어갑니다

---

## 1. ClusterConfig — 클러스터의 매니페스트

```yaml
# cluster.yaml — eksctl create cluster -f cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: k8s-study
  region: ap-northeast-2
  version: "1.36"
  tags: { project: k8s-study, owner: me }

vpc:                                  # 생략 시 eksctl이 VPC 신설
  clusterEndpoints: { publicAccess: true, privateAccess: true }

accessConfig:
  authenticationMode: API             # access entries 전용 (표준)

managedNodeGroups:
- name: workers
  instanceType: t3.medium
  desiredCapacity: 2
  minSize: 0                          # 휴지기 0 스케일 허용 (모듈 01)
  maxSize: 4
  amiFamily: AmazonLinux2023
  volumeSize: 30
  labels: { role: general }
  iam:
    withAddonPolicies: { ebs: false } # 권한은 따로, 최소로 (09)

addons:                               # 관리형 애드온 (11에서 심층)
- { name: vpc-cni }
- { name: coredns }
- { name: kube-proxy }
- { name: eks-pod-identity-agent }
```

읽는 법: **K8s 매니페스트와 같은 사상** — 원하는 상태 선언, `eksctl create/upgrade`가 수렴. Git에 커밋하면 클러스터의 이력서가 됩니다. (단 eksctl은 완전한 reconcile은 아닙니다 — 일부 변경은 `eksctl update/upgrade` 하위 명령이 따로 있습니다)

## 2. eksctl의 뒷면 — CloudFormation

`eksctl create cluster`가 실제로 하는 일: **CloudFormation 스택 생성** (VPC, IAM 역할, 클러스터, 노드그룹이 각각 스택). 함의:

- 진행/실패 추적은 CFN 콘솔(이벤트 탭)에서 — "eksctl이 멈췄어요"의 진단처
- 리소스 수동 변경은 스택과 어긋남(drift)을 만듭니다 — k8s 10의 "라이브 수정은 빚"의 인프라판
- 삭제도 `eksctl delete cluster`로 — 스택째 지워야 잔존물이 없습니다 (모듈 01의 "새는 돈" 예방)

## 3. 인증 경로 해부 — kubectl이 EKS에 들어가기까지

```
① kubectl이 kubeconfig를 읽음
   users[].user.exec: { command: aws, args: [eks, get-token, ...] }   ← 비밀번호가 없습니다!
② aws eks get-token 실행
   = STS GetCallerIdentity 요청을 "서명만 하고" 토큰으로 포장 (사전 서명 URL)
   → 짧은 수명(~14분)의 bearer 토큰 출력
③ API 서버가 토큰 검증: 그 서명을 STS로 확인 → "이 요청자는 IAM arn:...:role/X"
④ access entry: 그 ARN → K8s 사용자/그룹 매핑 (+access policy)
⑤ RBAC: 매핑된 주체의 권한 평가 (k8s 11)
```

핵심 통찰: kubeconfig엔 **비밀이 없습니다** — 자격증명은 AWS CLI의 자격증명 체계(프로파일/SSO/인스턴스 역할)에서 옵니다. "kubeconfig 유출"보다 "IAM 자격증명 유출"이 진짜 사고이고, 토큰은 14분이면 죽습니다.

## 4. Access Entries — IAM과 K8s의 공식 다리

### 구조

```
AccessEntry:  principalArn (IAM 사용자/역할) ← 클러스터의 "게스트 명단" 한 줄
  ├─ kubernetesGroups: [my-team]            ← RBAC 그룹에 매핑하거나
  └─ AccessPolicy 연결:                      ← AWS 정의 정책을 바로 (RBAC 없이)
      AmazonEKSClusterAdminPolicy   (≈ cluster-admin)
      AmazonEKSAdminPolicy          (≈ admin, ns 스코프 가능)
      AmazonEKSEditPolicy           (≈ edit)
      AmazonEKSViewPolicy           (≈ view)
      └ accessScope: cluster | namespace[...]   ← ns 단위 제한 가능!
```

두 가지 사용 패턴:
1. **간편**: entry + AWS 관리 정책 (View/Edit...) — RBAC 작성 없이 표준 권한
2. **정밀**: entry + kubernetesGroups → 내가 만든 (Cluster)RoleBinding(k8s 11)으로 — 커스텀 권한

### aws-auth ConfigMap (구세대) — 알아만 두기

옛 방식: kube-system의 `aws-auth` ConfigMap에 mapRoles/mapUsers를 직접 편집. 문제: YAML 오타 하나로 **전원 접근 불능**(편집 수단이 그 ConfigMap 자체라 복구 곤란), 감사 어려움. authenticationMode가 `API`면 무시되고, `API_AND_CONFIG_MAP`이면 병행(마이그레이션용). 옛 클러스터에서 만나면: access entries로 이전이 정답.

### 생성자 특권의 변화

클러스터를 만든 IAM 주체는 자동으로 admin 권한을 받습니다 — 옛날엔 **어디에도 안 보이는 숨은 권한**(감사 불가)이었지만, access entries 체제에선 명시적 entry로 보입니다(끌 수도 있습니다). "누가 이 클러스터에 들어올 수 있나"가 드디어 전부 조회 가능해졌습니다 — lab-02에서 실측.

## 5. kubeconfig 관리

```bash
aws eks update-kubeconfig --name k8s-study --region ap-northeast-2   # 표준 (컨텍스트 추가/갱신)
kubectl config get-contexts                                          # 멀티 클러스터 전환 (k8s 10)
```

## 6. 소스/도구에서 확인하기

- eksctl 스키마 전체: https://eksctl.io/usage/schema/
- access entries 문서: https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
- get-token의 구현: aws-cli의 `awscli/customizations/eks/get_token.py` (서명 토큰의 실체)

## 요약 카드

| 질문 | 답 |
|------|----|
| 클러스터 생성의 정석? | ClusterConfig 파일 + Git (한 줄 명령은 일회용) |
| eksctl의 뒷면? | CloudFormation 스택 — 진단/삭제도 스택 단위 |
| kubeconfig의 비밀번호? | 없습니다 — exec로 매번 STS 서명 토큰(~14분) 발급 |
| 인증/인가 분담? | 인증=IAM(STS), 인가=access policy 또는 RBAC |
| 권한 부여 표준? | access entries (aws-auth CM은 구세대) |
| ns 단위로 IAM 주체 제한? | AccessPolicy의 accessScope: namespace |
