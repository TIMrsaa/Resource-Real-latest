# 이론 — EKS Upgrade Strategy

> **🌱 클러스터 업그레이드 = "비행 중에 엔진 갈아끼우기"**
> 비행기를 착륙시킬 수 없다 (= 다운타임 안 됨), 한 번에 엔진 두 개 갈면 추락 (= 여러 마이너 점프 X).
> 그래서 **순서 / 점진 / 검증** 세 박자가 핵심이고, 이 모듈은 그 안전 체크리스트를 다룬다.

## 1. EKS 버전 정책

- 분기마다 새 마이너 버전 출시 (1.33, 1.34, 1.35, ...)
- 각 버전은 **Standard support 14개월** + Extended support 12개월 (유료)
- Extended 만료되면 자동 업그레이드 강제

→ **분기당 한 번 업그레이드 권장**. 6개월 미루면 곧 만료 위협.

> **🧠 미루면 미룰수록 위험이 누적된다**
> 한 버전씩 따라가면 마이너 점프 1회 — diff 가 작아 호환성 깨질 일이 적다.
> 1년 미루면 3~4 버전 점프 (Standard 가 14개월) → 한 번에 통과 X, 강제 업그레이드 시 장애 위험.

## 2. 업그레이드 순서

```
1. Control Plane (1.34 → 1.35)
   ↓ (한 번에 한 마이너 버전만)
2. EKS Addon (vpc-cni, coredns, kube-proxy, ebs-csi)
   ↓
3. Managed Node Group (또는 Karpenter 가 자동)
   ↓
4. 워크로드 호환성 검증
```

**역순 X**: 노드를 1.35 로 먼저 올리면 1.34 Control Plane 과 호환 안 됨.

> **🧠 "두뇌 → 신경 → 손발" 순서**
> Control Plane 이 두뇌, Addon 이 신경계, 노드/워크로드가 손발이다.
> 두뇌부터 새 버전을 이해해야 신경/손발도 따라갈 수 있다 — 역순으로 가면 신경이 두뇌가 모르는 명령어를 보낸다.

## 3. Skew Policy (Control Plane vs 노드)

- **kubelet** ≤ kube-apiserver (같거나 한 단계 낮음)
- 즉, Control Plane 1.35 이면 노드는 1.34 / 1.35 OK. 1.36 노드는 ❌.

> **🧠 "한 단계 차이" 가 점진 업그레이드의 안전망**
> Skew 가 허용되는 동안이 *Control Plane 이미 올라갔는데 노드는 아직* 인 과도기 — 이 구간에서 워크로드를 검증하라.
> 노드가 한 단계 뒤처지는 건 정상, 두 단계 뒤처지는 건 사고.

## 4. 업그레이드 전 호환성 점검

### 4.1 Deprecated API 사용 여부

K8s 마이너 버전마다 일부 API 제거. 예: `policy/v1beta1` PodDisruptionBudget 은 1.25 에서 제거.

```bash
# pluto 도구 (deprecated API 검출)
pluto detect-helm --output wide
pluto detect-files -d ./manifests
```

또는 EKS 의 `EKS upgrade insights` (콘솔):
- Console → EKS → 클러스터 → Upgrade Insights
- API 사용 / addon 호환성 자동 점검

### 4.2 노드 OS / kubelet 버전

```bash
kubectl get nodes -o wide
# VERSION 컬럼 확인
```

### 4.3 Addon 호환

```bash
eksctl utils describe-addon-versions --kubernetes-version 1.35 --name vpc-cni
```

> **🧠 Helm chart 와 Operator 가 가장 자주 깨진다**
> EKS Upgrade Insights 는 K8s API 변경은 잡아주지만, 서드파티 Operator (예: ArgoCD, Prometheus Operator) 의 CRD 호환은 직접 릴리스 노트 확인이 필수다.
> "Insights 통과 = 안전" 이 아니라 "Insights + 각 차트 release note" 가 안전.

## 5. Control Plane 업그레이드

```bash
eksctl upgrade cluster --name eks-study --version 1.35 --approve
# 또는 Terraform: cluster_version 변수 변경 후 apply
# 또는 콘솔: Update version
```

소요: 약 20~30분. 무중단 (워크로드 영향 없음).

> **🧠 "무중단" 은 워크로드 한정 — IAM/Webhook 은 영향 가능**
> Control Plane 업그레이드 중에도 Pod 는 잘 돈다. 하지만 *kube-apiserver* 가 잠깐씩 끊기므로, *Admission Webhook* 이 timeout 짧게 잡혀 있으면 배포가 일시 실패할 수 있다.
> 업그레이드 시간엔 배포 일시 freeze 권장.

## 6. Addon 업그레이드

```bash
for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  LATEST=$(eksctl utils describe-addon-versions --kubernetes-version 1.35 --name $addon \
    --query 'Addons[0].AddonVersions[0].AddonVersion' --output text)
  eksctl update addon --name $addon --version $LATEST --cluster eks-study --force
done
```

> **🧠 vpc-cni 업그레이드는 따로 신중하게**
> 다른 addon 은 죽었다 살아도 워크로드 영향 없지만, vpc-cni 는 *모든 Pod 의 네트워크 데몬* 이다.
> `--force` 로 한 번에 올리지 말고 한 노드씩 drain → vpc-cni 재시작 → 검증 순서를 권장.

## 7. 노드 그룹 업그레이드

### 7.1 Managed Node Group

```bash
eksctl upgrade nodegroup --cluster eks-study --name workers
```

- 새 launch template (최신 EKS-optimized AMI)
- ASG 가 점진적 surge → 새 노드 join → 옛 노드 cordon/drain → 종료
- 자동 PDB 존중

### 7.2 Karpenter 노드

Karpenter v1 부터 **Drift** 가 자동:
- EC2NodeClass 의 AMI alias 가 `al2023@latest` 면 새 AMI 출시 시 자동 drift
- Disruption Budget 따라 점진 회전

수동 트리거:
```bash
kubectl annotate nodes -l managed-by=karpenter karpenter.sh/disruption=Drifted=$(date +%s) --overwrite
```

### 7.3 Self-Managed (legacy)

Launch template 직접 변경 + ASG instance refresh. 권장 X (Managed 또는 Karpenter 로 마이그).

> **🧠 PDB 가 노드 회전의 안전벨트**
> Managed/Karpenter 둘 다 PDB (PodDisruptionBudget) 를 존중하지만, *PDB 가 잘못 설정* 되면 (예: minAvailable=100%) 노드가 영원히 drain 못 되어 업그레이드가 멈춘다.
> 업그레이드 전 모든 워크로드의 PDB 가 *실제로 disruption 을 허용하는지* 확인하라.

## 8. 워크로드 호환성 점검 (업그레이드 후)

```bash
# 모든 Pod Ready
kubectl get pods -A | grep -v Running | grep -v Completed

# 핵심 시스템 Pod 모두 Ready
kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}={.status.phase}{"\n"}{end}'

# Deprecated API 사용 흔적 (audit log)
aws logs filter-log-events \
  --log-group-name /aws/eks/eks-study/cluster \
  --filter-pattern '"requestObject" "extensions/v1beta1"' \
  --max-items 5
```

> **🧠 "Pod Ready" 만으로 안심하지 마라**
> readinessProbe 가 너무 느슨하게 잡힌 앱은 새 버전 노드 위에서 *Ready 라고 거짓말* 하면서 실제 요청은 실패시킬 수 있다.
> 업그레이드 직후엔 메트릭 (5xx 비율, latency p99) 도 같이 봐야 진짜 검증.

## 9. Blue/Green 업그레이드 패턴 (운영)

여러 마이너 점프 또는 위험한 업그레이드 시:
1. 새 클러스터 (1.35) Terraform 으로 별도 생성
2. 워크로드 배포
3. Route 53 weighted 로 점진 트래픽 이전
4. 옛 클러스터 (1.33) 삭제

**장점**: 즉시 롤백 가능, blast radius 격리.
**단점**: 2배 비용 (이행 동안), DNS 캐시 / 세션 관리 필요.

> **🧠 "큰 점프" 일수록 Blue/Green 이 정답**
> 1.30 → 1.34 같은 다중 점프, 또는 etcd 마이그레이션을 동반하는 위험한 업그레이드는 in-place 보다 새 클러스터가 압도적으로 안전하다.
> 추가 비용은 "장애 1번의 비용" 보다 항상 싸다.

## 10. Karpenter + Drift 로 무중단 노드 업그레이드 (실무 best)

```yaml
# EC2NodeClass 의 amiFamily 변경 또는 alias 갱신
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest    # ← 새 AMI 자동 채택
```

→ 모든 기존 노드 Drift → Karpenter 가 PDB / Budget 존중하며 점진 교체.

> **🧠 `alias: al2023@latest` 는 양날의 검**
> 편하지만 새 AMI 가 나오면 *내 의지와 무관하게* 노드 회전이 시작된다.
> 운영 환경에선 명시적 버전 (예: `al2023@v20251101`) 으로 고정하고, 주기적으로 사람이 alias 갱신하는 게 안전하다.

다음: [lab-01-prereq-check.md](./lab-01-prereq-check.md)
