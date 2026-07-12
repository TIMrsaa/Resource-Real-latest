# 이론 — EKS 비용 모델 + 우상향 진단

> **🌱 클러스터 비용은 "한 달 전기 요금 고지서"**
> 누진세(NAT/로그/EBS)와 기본료(Control Plane)가 섞여 있어서, 막연히 "전기 좀 아껴 쓰자"로는 절대 안 줄어든다.
> 어디서 새는지 항목별로 봐야 한다 — 이 모듈은 그 "고지서 항목별 점검" 방법을 다룬다.

## 1. EKS 비용 구성

| 항목 | 단가 (`ap-northeast-2`) | 비고 |
|------|------------------------|------|
| EKS Control Plane | $0.10/시간 (= ~$73/월) | 클러스터당 |
| EC2 (Managed Node) On-Demand | 인스턴스 타입별 | 시간당 |
| EC2 Spot | OD 의 약 30% | 회수 위험 |
| EBS gp3 | $0.092/GB/월 | + IOPS 추가 |
| NAT Gateway | $0.045/시간 + $0.045/GB | AZ 별 |
| ALB | $0.0225/시간 + LCU | + 데이터 전송 |
| NLB | $0.0225/시간 + NLCU | + 데이터 전송 |
| Data Transfer (Out) | $0.09/GB | 인터넷 방향 |
| CloudWatch Logs ingest | $0.50/GB | 가장 흔한 함정 |
| ECR | $0.10/GB/월 | 이미지 저장 |

**소규모 클러스터 (3 t3.medium spot + 1 ALB + 100GB EBS) 한 달 비용 견적**:
- Control Plane: $73
- 3 t3.medium spot × 730h × $0.016 = $35
- ALB: $0.0225 × 730 = $16
- EBS 100GB: $9
- NAT GW: $0.045 × 730 + 데이터 = ~$50 (지속 트래픽이면 더)
- CloudWatch Logs: $5 ~ $50 (앱 로그 양 따라)
- **합계: $190 ~ $250/월**

> **🧠 "보이지 않는 비용" 이 진짜 범인**
> Control Plane / EC2 처럼 눈에 잘 띄는 항목보다 **NAT Gateway + CloudWatch Logs** 가 실제 청구서에서 두 자리수 % 를 먹는 경우가 흔하다.
> 비용 분석은 항상 이 둘부터 의심하라.

## 2. "왜 비용이 우상향?" 패턴별 진단

### 2.1 EC2 비용 우상향
```bash
# 시간대별 노드 수 추이 (Prometheus)
count(kube_node_info)

# 인스턴스 타입 분포 변화
kubectl get nodes -L node.kubernetes.io/instance-type
```
체크:
- 노드 수가 점진 증가 → Pod requests 가 실제보다 큼? autoscaling 의도와 다름?
- 큰 인스턴스 타입 자주 등장 → Karpenter requirements 너무 느슨

### 2.2 EBS 비용 우상향
```bash
# 사용 안 하는 EBS 가 누적
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size,CreateTime]' --output table
```
주범:
- StorageClass `reclaimPolicy: Retain` → PVC 삭제해도 EBS 남음
- StatefulSet 삭제했는데 PVC 안 지움

### 2.3 NAT Gateway 폭증
```bash
aws ec2 describe-nat-gateways
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"USAGE_TYPE_GROUP","Values":["EC2: NAT Gateway"]}}'
```
주범:
- ECR pull 트래픽이 NAT 통해 인터넷으로 → VPC Endpoint 도입
- 업스트림 API 호출량 증가 → 캐싱 / Egress 최적화

### 2.4 CloudWatch Logs 폭증
```bash
aws logs describe-log-groups --query 'logGroups[].[logGroupName,storedBytes]' \
  --output text | sort -k2 -n | tail
```
주범:
- 앱 로그 레벨 DEBUG
- access log 가 너무 많이 (분당 수만 줄)
- retention 안 설정 (영구 보관)

> **🧠 "어디서 새는지" 부터 → "왜 새는지" 순서**
> 비용은 *Cost Explorer 로 항목 (EC2/EBS/NAT/Logs)* → *kubectl 로 워크로드 추적* 두 단계로 봐야 한다.
> 첫 단계 건너뛰고 워크로드부터 뒤지면 NAT 트래픽 같은 인프라 비용은 영원히 못 찾는다.

## 3. Right-Sizing 의 의미

Pod 의 `requests` 가 실제 사용량보다 크면 → Karpenter 가 큰 노드 만듦 → 노드 사용률 낮음 → 낭비.

**측정**:
```
container_memory_working_set_bytes / container_spec_memory_request_bytes
container_cpu_usage_rate / container_spec_cpu_request_cores
```

50% 미만 = over-provisioning. 80~90% = ideal. 100%+ = throttling 위험 (CPU) 또는 OOM 위험 (Memory).

> **🧠 requests 는 "예약석", limits 는 "탑승 한도"**
> requests 만 키워두고 사용 안 하면 Karpenter 는 "이만큼 자리 잡아둬" 라고 받아들여 큰 노드를 띄운다 — 실제 탑승객은 적어도 비행기는 큰 거.
> 그래서 right-sizing 의 90% 는 **requests 줄이기** 가 핵심이지 limits 가 아니다.

## 4. Right-Sizing 자동화 — VPA

**Vertical Pod Autoscaler**: 사용량 기록 → requests/limits 추천 또는 자동 수정.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: "Off"      # Off: 추천만, Auto: 자동 수정
```

**주의**: HPA 와 VPA 는 같은 메트릭 (CPU/Memory) 으로 동시 사용 시 충돌. HPA 는 Pod 수, VPA 는 Pod 크기.

> **🧠 운영 시작은 `updateMode: Off` 가 정답**
> Auto 모드는 Pod 를 재시작시킨다. 추천값 (Recommendation) 만 보고 사람이 검토 → 다음 배포에 manifest 로 반영하는 게 안전하다.
> "측정 → 추천 → 검증 → 적용" 4단계를 건너뛰면 새벽에 OOM 으로 페이지가 울린다.

## 5. NS / 워크로드 단위 비용 배분 — KubeCost / OpenCost

여러 팀이 한 클러스터를 쓰는 경우 "어느 NS 가 얼마 쓰는지" 알아야 한다.

**OpenCost** (오픈소스):
- Helm 으로 가벼운 설치
- Prometheus 메트릭 + AWS 가격 정보 → NS / Deployment / 라벨 단위 비용
- Grafana 대시보드 자동

**KubeCost**:
- OpenCost 의 상용 버전 (OpenCost = KubeCost 의 기반 OSS)
- 더 풍부한 UI / 알람 / 추천

학습은 OpenCost 로 충분.

> **🧠 "Showback" 이 행동을 바꾼다**
> 팀별/NS 별로 비용을 *보여주기만 해도* (실제 청구 X) 개발자가 자발적으로 requests 를 줄이고 retention 을 짧게 잡는다.
> 비용 절감의 가장 큰 효과는 도구가 아니라 *가시화* 에서 온다.

## 6. 비용 절감 체크리스트 (실행 우선순위)

1. **NAT Gateway 비용 확인** — VPC Endpoint 도입 (ECR, S3 → 즉시 효과)
2. **CloudWatch Logs retention 설정** (7일 / 30일 / 90일)
3. **사용 안 하는 EBS 제거** + StorageClass `Delete` 권장
4. **Spot 다양화** — Karpenter NodePool requirements 재검토
5. **Consolidation 활성화** + cooldown 적정 (`30s ~ 1m`)
6. **Pod requests right-sizing** — VPA 추천 모드로 시작
7. **NS 별 비용 가시화** — OpenCost / KubeCost 도입

> **🧠 위에서부터 해야 효과가 크다**
> 1번 (NAT/VPC Endpoint) 와 2번 (Logs retention) 은 *코드 변경 0* 으로 청구서 30~50% 가 빠지는 경우가 많다.
> Right-sizing/Spot 다양화 같은 워크로드 작업은 그 다음 단계 — 인프라 누수부터 막아야 한다.

다음: [lab-01-cost-explorer.md](./lab-01-cost-explorer.md)
