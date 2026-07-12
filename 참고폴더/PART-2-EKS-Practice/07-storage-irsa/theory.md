# 이론 — IRSA & Pod Identity

> **🌱 IRSA = "Pod 마다 개인 사원증 발급"**
> 옛날엔 회사 출입증 (노드 IAM) 한 장을 모든 직원 (Pod) 이 돌려 썼다 — 한 명만 S3 접근이 필요해도 다 같이 권한 보유.
> IRSA 는 Pod 마다 *전용 사원증* 을 발급해서, 정확히 필요한 만큼만 출입 가능하게 한다 (최소 권한 원칙).

## 1. 문제: K8s ServiceAccount 가 AWS IAM 을 어떻게 쓰지?

### 옛날 방식: 노드 IAM Role 공유
- 노드 EC2 인스턴스 프로파일에 IAM Role 을 부여
- 그 노드의 모든 Pod 이 같은 IAM 권한을 갖게 됨
- **문제**: 한 Pod 만 S3 권한이 필요한데 모든 Pod에 부여 → 최소 권한 위반

### 해결책: IRSA — Pod 별로 IAM Role

> ServiceAccount 단위로 IAM Role 부여 → Pod이 자기 SA 에 매핑된 IAM Role 권한만 사용

> **🧠 "노드 IAM 공유" 가 보안 사고 1위 패턴**
> 노드에 광범위한 권한을 주면 *침투된 Pod 하나가 클러스터 전체 AWS 자산을 장악* 한다.
> IRSA/Pod Identity 의 도입은 선택이 아니라 *모든 운영 클러스터의 필수* — 노드 IAM 은 최소 권한만 (ECR pull, EKS describe 정도).

## 2. IRSA 동작 원리

```
┌─ 1. AWS는 EKS 클러스터의 OIDC issuer URL을 IAM에 등록 (Identity Provider)
│
├─ 2. IAM Role의 Trust Policy: "이 OIDC issuer 가 발급한 토큰 + 특정 SA 면 신뢰"
│
├─ 3. K8s SA의 annotation: eks.amazonaws.com/role-arn=arn:aws:iam:...
│
├─ 4. Pod 시작 시 kubelet이 Projected Token 을 Pod에 자동 마운트
│     (이 토큰은 OIDC issuer 가 서명한 JWT)
│
├─ 5. Pod 의 AWS SDK 가 토큰 감지 → STS AssumeRoleWithWebIdentity 호출
│     - Role ARN: SA annotation 에서
│     - WebIdentityToken: 마운트된 토큰
│
└─ 6. STS 가 토큰의 OIDC 서명을 검증 → IAM Role 의 임시 자격증명 반환
      Pod 의 AWS SDK 가 이 자격증명으로 AWS API 호출
```

> **🧠 "토큰은 단기, 자격증명은 자동 갱신"**
> Projected Token 은 분 단위로 만료되고 kubelet 이 자동 갱신, STS 자격증명도 1시간마다 자동 갱신된다.
> 그래서 *AWS Access Key 를 Pod 에 박는 옛 방식은 절대 안 된다* — 누출 시 영구 권한이지만 IRSA 는 본질적으로 임시.

## 3. SA Annotation 형식

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app-role
```

> **🧠 "SA 만 만들어두면 IRSA 가 동작 안 한다"**
> annotation 추가는 절반일 뿐 — IAM Role 의 Trust Policy 에 *동일한 SA path* 가 있어야 양방향 매칭.
> 디버깅 시 *양쪽 (K8s SA annotation, IAM Trust Policy) 의 SA path 가 글자 단위로 일치* 하는지 확인.

## 4. IAM Role Trust Policy 형식

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/XXXX"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.ap-northeast-2.amazonaws.com/id/XXXX:sub": "system:serviceaccount:default:my-app",
        "oidc.eks.ap-northeast-2.amazonaws.com/id/XXXX:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

핵심: `:sub` 조건이 `system:serviceaccount:<ns>:<sa>` 정확히 일치해야 함.

> **🧠 Trust Policy 의 `:sub` 가 IRSA 의 진짜 보안 경계**
> OIDC issuer 만으로는 *클러스터 안 모든 Pod 이 같은 자격증명* 을 받을 위험이 있다.
> `:sub` 조건이 SA name 까지 박혀 있어야 *정확히 그 SA 의 Pod 만* AssumeRole 가능 — 이 조건 없는 Trust Policy 는 사실상 broken.

## 5. Pod에 자동 마운트되는 토큰

```bash
kubectl exec -it <pod> -- ls /var/run/secrets/eks.amazonaws.com/serviceaccount/
# → token (JWT)
```

```bash
kubectl exec -it <pod> -- env | grep AWS
# AWS_ROLE_ARN=arn:aws:iam:...
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

→ AWS SDK가 이 두 환경변수를 자동으로 감지해 AssumeRoleWithWebIdentity.

> **🧠 "AWS SDK 가 환경변수를 자동 인식" 이 IRSA 의 사용 편의성 핵심**
> 앱 코드에는 IAM 인증을 위한 *한 줄도 추가 안 된다* — SDK 가 알아서 토큰을 찾아 사용.
> 그래서 "내 앱 코드만 보면 IRSA 가 적용됐는지 모른다" → SA annotation + Trust Policy 가 단일 진실 source.

## 6. eksctl 의 편의 명령

수동으로 위를 다 해도 되지만 eksctl이 한 번에:
```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=default \
  --name=my-app \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve
```

수행하는 일:
1. CloudFormation Stack 만들어 IAM Role 생성 (Trust 정책 포함)
2. K8s SA 생성 + annotation 자동 설정

> **🧠 `eksctl create iamserviceaccount` 가 운영 디버깅을 어렵게 만들 수도**
> 편하지만 *어떤 CFN 스택* 이 만들어졌는지 모르고 지나가기 쉽다 — 나중에 정책 수정/삭제 시 어디를 봐야 할지 모름.
> 학습 단계엔 한 번쯤 수동으로 (IAM Role 생성 → Trust Policy → SA annotation) 직접 해보고 그 다음에 eksctl 의 편의를 쓰는 게 낫다.

## 7. Pod Identity (2024+ 신규)

IRSA 의 한계:
- IAM Role 의 Trust 정책에 OIDC issuer 와 SA name 을 정확히 박아야 함
- 클러스터 마이그레이션 / SA 이동 시 Trust 정책 수정 필요

**Pod Identity** 는 다음을 해결:
```bash
aws eks create-pod-identity-association \
  --cluster-name eks-study \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::xxx:role/my-app-role
```

- IAM Role의 Trust 는 EKS Pod Identity Service 만 신뢰 (간단한 정책)
- 클러스터 ID 와 SA 매핑은 EKS Pod Identity Agent (DaemonSet) 가 담당
- Role 재사용 더 쉬움

전제: `eks-pod-identity-agent` addon 설치 필요.

| | IRSA | Pod Identity |
|---|---|---|
| 출시 | 2019 | 2023말 / 2024 |
| Trust Policy | OIDC issuer + sub 박아야 함 | 단순 (`pods.eks.amazonaws.com`) |
| Role 재사용 | 어려움 (issuer 마다 정책 따로) | 쉬움 (여러 클러스터/SA에 연결) |
| 토큰 발급 | kubelet (Projected Token) | Pod Identity Agent |
| 의존성 | OIDC provider | `eks-pod-identity-agent` addon |
| 권장 | 기존 자산 / 멀티-클러스터 호환 | 신규 클러스터 |

본 커리큘럼: IRSA 기본, Pod Identity 도 한 lab 에서 시연.

> **🧠 Pod Identity 는 "다중 클러스터" 시 진가**
> 한 IAM Role 을 여러 EKS 클러스터의 여러 SA 에 연결 가능 → 클러스터를 옮겨도 IAM 변경 안 해도 됨.
> 단일 클러스터에서는 IRSA 와 큰 차이 없지만, 멀티 환경 운영팀에선 Pod Identity 가 운영 부담을 크게 줄인다.

다음: [lab-01-ebs-csi-irsa.md](./lab-01-ebs-csi-irsa.md)
