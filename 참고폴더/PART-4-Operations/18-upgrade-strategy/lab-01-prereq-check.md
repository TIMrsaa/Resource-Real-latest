# Lab 01 — 업그레이드 사전 점검

> **🌱 핵심 개념 미리보기**
> - **Skew Policy**: kubelet 은 apiserver 보다 최대 **3 마이너 버전 낮을 수 있음** (1.28→1.31 OK). 거꾸로 더 높을 수는 없음.
> - **EKS Upgrade Insights**: AWS 가 클러스터를 스캔해 deprecated API/노드/addon 호환성을 자동 점검해주는 기능.
> - **Deprecated API**: K8s 가 매 버전마다 일부 API 를 제거. 매니페스트가 옛 apiVersion 을 쓰면 업그레이드 후 적용 실패.
> - **pluto**: deprecated API 를 정적/동적으로 탐지하는 OSS 도구 (Fairwinds).
> - **PDB (PodDisruptionBudget)**: drain 중 동시에 죽일 수 있는 Pod 수 제한. 너무 빡빡하면 노드 업그레이드 stuck.

## 1. 현재 버전 확인

```bash
aws eks describe-cluster --name eks-study --query 'cluster.{version:version,platformVersion:platformVersion,status:status}'

kubectl version
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.nodeInfo.kubeletVersion}{"\n"}{end}'
```

## 2. EKS Upgrade Insights (콘솔 또는 CLI)

```bash
aws eks list-insights --cluster-name eks-study \
  --query 'insights[].[id,name,recommendation,insightStatus.status]' --output table
```

기대 (예시):
```
deprecated-api      Replaceable resource versions detected   PASSING
ekssupport          EKS support status                       UNHEALTHY     ← 필요 시
nodeMaxConfigured   Node Pod density                         PASSING
```

`UNHEALTHY` 가 있으면 그 권고 사항 따르기.

> **🧠 Insights 가 무엇을 보나**
> AWS 가 클러스터의 audit log + 리소스 인벤토리를 분석해 자동 점검:
> - **deprecated-api**: 다음 버전에서 제거될 API 를 호출한 client 가 있나 (audit log 추적).
> - **nodeMaxConfigured**: max-pods 설정과 실제 노드 수용량 매칭.
> - **eks-support**: 현재 버전이 EOL/extended-support 상태인지.
>
> Insights 는 **콘솔 무료 + API 호출 제한 없음**. 업그레이드 전 가장 먼저 봐야 할 곳.

## 3. Deprecated API 사용 여부 (`pluto`)

```bash
brew install FairwindsOps/tap/pluto

# Helm 릴리즈 점검
pluto detect-helm -A

# YAML 파일 점검 (예: 본 커리큘럼 매니페스트)
cd "$(git rev-parse --show-toplevel)"
pluto detect-files -d ./PART-1-Kubernetes-Basics --target-versions=k8s=v1.35.0

# 클러스터 안의 리소스 점검 (kubectl convert + pluto)
pluto detect-all-in-cluster --target-versions=k8s=v1.35.0
```

기대: deprecated 사용처가 있으면 파일/객체별 출력. 다 통과면 `No problems found`.

> **🧠 pluto 의 3가지 모드 차이**
> - `detect-files`: 디스크의 YAML 만 스캔. CI 파이프라인에서 PR 차단용.
> - `detect-helm`: 클러스터에 설치된 Helm 릴리즈의 manifest 분석. "지금 떠있는 차트가 안전한가".
> - `detect-all-in-cluster`: 클러스터의 live 리소스 직접 조회. last-applied-configuration annotation 을 봐서 원본 apiVersion 추정.
>
> 가장 확실한 건 3개 다 돌리는 것 — 한쪽만 보면 누락됨.

## 4. addon 호환 버전 확인

```bash
TARGET=1.35

for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  echo "=== $addon ==="
  eksctl utils describe-addon-versions --kubernetes-version $TARGET --name $addon \
    --query 'Addons[0].AddonVersions[0].[AddonVersion,Compatibilities[0].DefaultVersion]' \
    --output text
done
```

## 5. 노드 그룹 AMI 버전

```bash
aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers \
  --query 'nodegroup.{releaseVersion:releaseVersion,amiType:amiType,version:version}'
```

## 6. PDB / 워크로드 ready 상태

```bash
kubectl get pdb -A
kubectl get pods -A | grep -vE 'Running|Completed' | head
```

PDB 가 너무 빡빡하면 (`minAvailable: 100%`) 노드 업그레이드 stuck.

> **🧠 PDB 가 업그레이드를 막는 메커니즘**
> 노드 drain → kubelet 이 각 Pod 에 eviction 요청 → API server 가 PDB 검사.
> `minAvailable: 100%` (또는 replicas 와 같은 값) 이면 **단 1개도 죽일 수 없음** → eviction 영원히 거부.
> EKS managed node group 은 1시간 후 force replace 시도하지만, 그 사이 새 노드 vs 옛 노드가 공존해 클러스터 비용 증가.
> 점검 명령: `kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,MIN:.spec.minAvailable,MAX:.spec.maxUnavailable,ALLOWED:.status.disruptionsAllowed`

## 7. Backup / Disaster Recovery

업그레이드 전 다음을 백업:
```bash
# 클러스터의 모든 매니페스트 export (velero 권장, 학습용은 간단 버전)
mkdir -p /tmp/eks-backup
for ns in default order monitoring kube-system karpenter keda; do
  kubectl get all,cm,secret,pvc,sa,role,rolebinding -n $ns -o yaml > /tmp/eks-backup/${ns}.yaml 2>/dev/null
done
ls -la /tmp/eks-backup/
```

(Secret 은 sensitive 주의 — git 커밋 금지)

> **🧠 왜 단순 `kubectl get -o yaml` 백업으론 부족한가**
> `kubectl get` 결과엔 `resourceVersion`, `uid`, `creationTimestamp` 등 클러스터 의존 필드가 섞임 → 그대로 apply 시 충돌.
> Velero 는 etcd snapshot 대신 API 기반으로 export + restore 시 필드 정리 + **PVC 의 EBS snapshot 까지** 함께 처리.
> 학습용 임시 백업엔 `kubectl get` 으로 충분하지만, 실제 DR 설계엔 Velero (또는 클러스터 자체 재생성 + GitOps 복원) 권장.

## 8. 학습 확인

- skew policy (kubelet vs apiserver) 이 허용하는 차이는?
- `kubectl convert` 의 용도는?
- velero 가 K8s backup 에 적합한 이유는?

다음: [lab-02-control-plane.md](./lab-02-control-plane.md)
