# Lab 02 — Addons 동작 검증

> **🌱 핵심 개념 미리보기**
> - **kubernetes_manifest**: Terraform 으로 임의 K8s YAML(특히 CRD) 적용하는 리소스. CRD 는 미리 install 돼 있어야.
> - **time_sleep**: provider 간 의존성 타이밍 보정. Helm 후 30 초 대기로 Karpenter Pod Ready 보장.
> - **IRSA via Terraform**: aws_iam_role + service_account annotation 두 단계가 한 module 안에서.
> - **두 번째 apply 가 정상화**: 종종 처음 apply 가 race condition 으로 실패 → 한 번 더 실행.
> - **여러 source 적용**: 다른 폴더의 매니페스트를 임시 디렉토리에 복사해 디렉토리 구조 유지.

## 1. Karpenter NodePool / EC2NodeClass 가 만들어졌는지

```bash
kubectl get nodepool,ec2nodeclass
kubectl describe ec2nodeclass default
```

기대: READY=True.

`kubernetes_manifest` 리소스가 Helm 후 `time_sleep` 30초 후에 적용. 처음 apply 시 가끔 Karpenter Pod 가 아직 안 떠서 실패할 수 있음 → 두 번째 apply 가 정상.

> **🧠 `kubernetes_manifest` 가 까다로운 이유**
> 이 리소스는 plan 단계에서 cluster 에 dry-run API 호출 → CRD 가 없으면 plan 부터 실패.
> 즉 "Karpenter Helm install → CRD 등록 → kubernetes_manifest plan" 순서가 한 apply 안에 있어야 함.
> `time_sleep` + `depends_on` 으로 강제 직렬화. 진정한 해법은 CRD 를 먼저 별도 apply 하는 2-stage 패턴.

## 2. KEDA + IRSA 검증

```bash
kubectl get sa -n keda keda-operator -o yaml | yq '.metadata.annotations'
```

기대: `eks.amazonaws.com/role-arn` 가 채워져 있음.

> **🧠 Terraform 으로 IRSA 만들기**
> ① OIDC provider 등록 (EKS 모듈이 자동) ② IAM Role with trust policy (sub=system:serviceaccount:keda:keda-operator) ③ ServiceAccount annotation.
> 세 단계 중 하나라도 빠지면 토큰 받지 못함 → Pod 에서 `Unable to load AWS credentials` 에러.
> Terraform 의 module 이 이 셋을 한 번에 묶어줘서 코드 1줄 (`module "irsa_keda" { ... }`) 로 끝남.

```bash
kubectl logs -n keda -l app=keda-operator --tail=20
```

## 3. AWS LB Controller 검증

```bash
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | yq '.metadata.annotations'
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## 4. 간단한 워크로드 배포 (eks-study 클러스터에서 했던 것 재현)

```bash
# Module 09 의 매니페스트를 새 클러스터에 적용 (디렉토리 구조 유지하여 동일 파일명 충돌 방지)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SRC=../../PART-2-EKS-Practice/09-msa-deploy/manifests
rm -rf /tmp/tf-msa
for f in "$SRC"/order/*.yaml "$SRC"/user/*.yaml "$SRC"/payment/*.yaml "$SRC"/notification/*.yaml "$SRC"/frontend/*.yaml "$SRC"/base/namespace.yaml "$SRC"/base/ingress.yaml; do
  rel="${f#$SRC/}"
  out="/tmp/tf-msa/$rel"
  mkdir -p "$(dirname "$out")"
  sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" "$f" > "$out"
done

kubectl apply -f /tmp/tf-msa/base/namespace.yaml
kubectl apply -R -f /tmp/tf-msa/
kubectl get all -n order
```

> **🧠 sed 루프가 디렉토리 구조를 보존하는 이유**
> 단순 `sed ... > /tmp/$(basename $f)` 로 모든 파일을 평탄화하면 `deployment.yaml` 이 6개라 마지막 하나로 덮어씀.
> 본 루프는 `rel="${f#$SRC/}"` 로 상대 경로 추출 → `/tmp/tf-msa/order/deployment.yaml` 처럼 원본 구조 유지.
> `kubectl apply -R -f /tmp/tf-msa/` 가 디렉토리 재귀로 모든 YAML 적용. namespace 우선 적용은 의존성 보장.

## 5. (옵션) MSA 와 KEDA SQS 결합 시연

위 Module 14 의 시나리오를 새 클러스터에서 다시 한 번:
```bash
# SQS 큐 생성
aws sqs create-queue --queue-name eks-study-payments-tf

# (이후 모듈 13/14 의 절차와 동일)
```

## 6. Terraform 변경 후 재적용

예: NodePool 의 limits 변경:
```hcl
# karpenter.tf 수정
limits = { cpu = "200" }    # 100 → 200
```

```bash
terraform plan
terraform apply
```

→ 변경된 리소스만 update. (idempotent)

> **🧠 Terraform 의 idempotency 메커니즘**
> apply 마다 ① tfstate 의 desired ② 실제 리소스 (Refresh 단계) ③ 변경된 .tf 파일을 비교 → diff 만 적용.
> NodePool limits 만 바뀌면 `kubernetes_manifest.update` 한 줄로 끝, 노드 재생성 X.
> 단, immutable 속성 (예: EKS cluster name) 변경은 `destroy + create` 로 처리 → 클러스터 통째 재생성 위험 → plan 으로 항상 사전 확인.

## 다음: [lab-03-destroy.md](./lab-03-destroy.md)
