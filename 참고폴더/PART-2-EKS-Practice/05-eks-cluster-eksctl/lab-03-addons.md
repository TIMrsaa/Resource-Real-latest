# Lab 03 — Addon 관리

## 학습 확인 포인트

- [ ] EKS addon vs 자체 설치(Helm)의 차이를 안다
- [ ] addon 버전 업그레이드 흐름을 봤다

> **🌱 Addon 이 뭐고 왜 따로 있나?**
> K8s 기본 설치엔 DNS도, 네트워크 플러그인도, 스토리지 드라이버도 없음 (필수 의존성만 있음).
> EKS는 클러스터를 즉시 사용 가능하게 만들기 위해 이런 컴포넌트들을 자동 설치/관리해주는 시스템 = **Addon**.
> AWS가 호환 버전을 검증하고 업그레이드 경로를 보장 = "운영 부담 ↓".

## 1. 현재 설치된 addon 확인

```bash
eksctl get addon --cluster eks-study --region ap-northeast-2
```

기대:
```
NAME                  VERSION                STATUS  IAMROLE
aws-ebs-csi-driver    v1.39.x-eksbuild.x     ACTIVE  arn:aws:iam::xxx:role/...
coredns               v1.12.x-eksbuild.x     ACTIVE
kube-proxy            v1.35.x-eksbuild.x     ACTIVE
vpc-cni               v1.20.x-eksbuild.x     ACTIVE  arn:aws:iam::xxx:role/...
```

> **🧠 각 addon이 하는 일**
> | Addon | 한 줄 요약 | 없으면? |
> |-------|----------|--------|
> | `vpc-cni` | Pod에 VPC IP 할당 | Pod 못 뜸 |
> | `coredns` | 클러스터 내 DNS (svc 이름→IP) | `curl http://my-svc/` 가 안 됨 |
> | `kube-proxy` | Service IP → Pod IP 라우팅 | Service가 작동 안 함 |
> | `aws-ebs-csi-driver` | PVC → EBS 자동 생성 | PV 동적 프로비저닝 안 됨 |
>
> **`-eksbuild.X` 접미사**: AWS가 패치한 빌드 번호. 같은 K8s upstream 버전에 보안 패치 등 적용분.
>
> **`IAMROLE` 컬럼**: 일부 addon이 IRSA로 IAM Role 빌림. 위 vpc-cni, ebs-csi가 그 예.

## 2. AWS managed addon vs Helm 설치 차이

| | EKS addon | Helm 직접 설치 |
|---|---|---|
| 설치 방법 | `eksctl create addon` 또는 콘솔 | `helm install` |
| 업그레이드 | EKS 가이드 / `eksctl update addon` | `helm upgrade` |
| EKS 버전과 호환성 | AWS 보장 | 직접 확인 |
| 커스터마이징 | 제한 (configurationValues) | 완전 |
| 비용 | 무료 (워크로드만 청구) | 무료 |

**기본 정책**:
- vpc-cni, coredns, kube-proxy, ebs-csi → addon 권장
- AWS Load Balancer Controller, Karpenter, KEDA → Helm 권장 (커스터마이징 많음)

> **🧠 왜 둘로 나뉘어 있나?**
> - **AWS가 책임지고 호환성 보장하는 것** = addon (K8s 핵심 의존성)
> - **사용자가 자유롭게 골라 쓰는 것** = Helm (각자 사용 사례 다름)
>
> 운영 팁: addon으로 시작하고, 커스터마이즈가 필요해지면 Helm으로 옮기는 패턴이 흔함.

## 3. addon 사용 가능한 버전 보기

```bash
eksctl utils describe-addon-versions \
  --kubernetes-version 1.35 --name vpc-cni \
  --query 'Addons[].AddonVersions[].AddonVersion' --output text \
  | head -5
```

> **버전 호환성 매트릭스**: K8s 버전마다 어떤 addon 버전이 호환되는지 AWS가 명시.
> EKS 클러스터 업그레이드 전에 → addon 버전이 새 K8s에 호환되는지 먼저 확인 → 필요시 addon부터 업그레이드.

## 4. addon 업그레이드 흐름 (시뮬레이션)

```bash
# 현재 버전 확인
CURRENT=$(eksctl get addon --cluster eks-study --name vpc-cni \
  -o json | jq -r '.[0].Version')
echo "Current vpc-cni version: $CURRENT"

# 업그레이드 (실제로는 한 단계 위 버전이 있을 때만 의미)
# eksctl update addon --name vpc-cni --version <newer> --cluster eks-study --force
```

> **🧠 업그레이드 시 무슨 일이?**
> 1. AWS가 해당 addon Pod (보통 DaemonSet)을 새 버전으로 RollingUpdate
> 2. 노드 1개씩 → Pod 교체 → 다음 노드
> 3. `--force` 는 사용자가 수동 변경한 부분이 있을 때 덮어쓸지 여부
>    - 사용자가 vpc-cni의 ConfigMap을 직접 편집했다면 `--force` 없이 충돌
>    - `--force` = "내 수동 변경분 버려도 OK"

## 5. addon 자체 설정 변경 (configurationValues)

vpc-cni 의 환경변수 변경 예시:
```bash
eksctl update addon \
  --name vpc-cni \
  --cluster eks-study \
  --region ap-northeast-2 \
  --configuration-values '{"env":{"WARM_IP_TARGET":"5"}}'

# DaemonSet의 env 확인
kubectl describe ds aws-node -n kube-system | grep -A2 'WARM_IP_TARGET'
```

> **🧠 `WARM_IP_TARGET` 이란?**
> VPC CNI가 미리 ENI에 보조 IP를 몇 개 미리 할당해둘지. Pod 늘어날 때 IP 할당 지연 줄임.
> - 작게 (예: 1) → IP 절약, Pod 시작 약간 느림
> - 크게 (예: 10) → IP 미리 채워둠, Pod 빠른 시작
>
> 이게 lab의 핵심 아니라 **"addon도 설정 가능하다"** 가 포인트.
> AWS가 허용하는 옵션은 [공식 문서의 schema](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html) 참고.

## 6. addon 삭제 (학습 후)

이 lab의 변경(`WARM_IP_TARGET`)을 되돌리려면 다시 `--configuration-values '{}'` 로 update.
addon 자체를 삭제하면 vpc-cni 가 빠져 노드 통신이 끊깁니다 — **하지 마세요**.

> **⚠️ 핵심 addon 삭제 시 일어나는 일** (절대 운영에서 하지 말 것)
> - `vpc-cni` 삭제 → 새 Pod 못 뜸 (IP 할당 불가) + 기존 Pod 통신 깨질 수 있음
> - `coredns` 삭제 → DNS 해석 실패 → 모든 svc 호출 실패
> - `kube-proxy` 삭제 → Service IP가 Pod로 라우팅 안 됨 → 모든 트래픽 끊김
>
> 이 셋은 클러스터의 **3대 생명줄**.

## 학습 확인 질문

1. `vpc-cni` addon 을 삭제하면 어떻게 되는가?
2. `aws-ebs-csi-driver` addon이 IRSA를 자동 셋업해 주는 이유는?
3. CoreDNS addon 의 ConfigMap을 수동 편집했는데 EKS addon이 덮어쓰는 동작을 본 적 있다면? 어떻게 막을까?

> **힌트**:
> 1. Pod 통신이 깨지고 새 Pod도 못 뜸. 클러스터 사실상 마비.
> 2. EBS API 호출 권한 (CreateVolume 등) 이 필요. 노드 IAM에 부여하면 모든 Pod이 EBS 만들 수 있어 위험 → IRSA로 EBS CSI Pod에만 부여.
> 3. addon update 시 `--resolve-conflicts PRESERVE` 또는 `OVERWRITE` 옵션. 운영에선 ConfigMap 수동 편집보단 `configurationValues` 사용 권장.

다음: [quiz.md](./quiz.md)
