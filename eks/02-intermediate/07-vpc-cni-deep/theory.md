# 이론 — ENI/IP 모델, ipamd, prefix delegation, 확장 기능

> **🌱 17세 눈높이 비유: 좌석이 정해진 통학버스**
> 노드는 통학버스, Pod는 학생, IP는 **좌석표**입니다. 이 학교(VPC)의 규칙: 모든 학생은 **진짜 좌석표**(VPC IP)가 있어야 탑승.
> - 버스마다 좌석표 묶음(ENI)을 몇 묶음까지, 묶음당 몇 장까지 가질 수 있는지 **차종(인스턴스 타입)별로 정해져 있습니다**
> - 안내원(ipamd)은 학생이 몰릴 때를 대비해 **여분 좌석표를 미리 떼어옵니다**(warm pool) — 빠르지만, 안 쓰는 표를 쥐고 있어 학교 전체 표(서브넷)가 일찍 동납니다
> - **prefix delegation** = 좌석표를 낱장이 아니라 **16장 묶음 쿠폰**으로 발급 — 같은 묶음 수로 16배의 학생을 태웁니다

---

## 1. 기본 모델 — ENI × IP의 산수

인스턴스 타입마다 (ENI 수, ENI당 IP 수)가 고정:

| 타입 | ENI | ENI당 IP | **maxPods (기본 공식)** |
|------|-----|---------|------------------------|
| t3.medium | 3 | 6 | 3×(6-1)+2 = **17** |
| m5.large | 3 | 10 | 3×(10-1)+2 = **29** |
| m5.4xlarge | 8 | 30 | 8×(30-1)+2 = **234** |

```
maxPods = ENI수 × (ENI당 IP − 1) + 2
          (각 ENI의 첫 IP는 ENI 자신 몫, +2는 호스트네트워크 Pod 등)
```

→ **t3.medium의 17이라는 천장**: CPU/메모리가 남아도 Pod 17개에서 끝 — "작은 인스턴스 여러 대" 전략의 숨은 비용입니다 (k8s 27 pitfall의 수식판).

## 2. ipamd — IP 재고 관리자

aws-node DaemonSet(노드마다)의 핵심 컨테이너. 동작:

```
부팅: 기본 ENI 외 추가 ENI/IP를 미리 확보 (warm pool)
Pod 생성(CNI ADD): 풀에서 IP 하나 즉시 지급 (EC2 API 대기 없음 — 빠른 기동의 비밀)
풀 부족: EC2 API로 ENI 추가/IP 추가 (이게 느리면 Pod 생성도 느려짐)
Pod 삭제: IP 회수 → 풀로
```

### warm 설정 — 속도 vs 재고 잠식의 다이얼

| 환경변수 | 의미 | 기본 |
|----------|------|------|
| WARM_ENI_TARGET | 여분 ENI 수 | 1 (= ENI 하나 분량의 IP를 항상 예비) |
| WARM_IP_TARGET | 여분 IP 수 | (설정 시 ENI 대신 IP 단위 — 작은 서브넷에 유용) |
| MINIMUM_IP_TARGET | 부팅 시 최소 확보 | — |

trade-off: warm을 크게 = Pod 기동 빠름 + **서브넷 IP를 미리 잠식** / 작게 = 절약 + 스파이크 때 EC2 API 대기. 서브넷이 좁은 클러스터에서 `WARM_ENI_TARGET=1`이 IP를 갉아먹는 것이 고갈 사고의 단골 기여 요인(16).

## 3. Prefix Delegation — 게임 체인저

ENI에 IP를 낱개가 아니라 **/28 프리픽스(16개 묶음)**로 붙입니다:

```
m5.large 기본:   3 ENI × 9 IP        = 29 Pod
m5.large prefix: 3 ENI × 9 프리픽스 × 16 = 432 슬롯 → maxPods는 별도 상한(110/250)으로
```

- 활성화: vpc-cni 환경변수 `ENABLE_PREFIX_DELEGATION=true` + **maxPods 상향**(kubelet — eks 05 nodeadm 또는 eksctl이 자동)
- 조건: 니트로 인스턴스, 그리고 **서브넷에 연속된 /28 블록**이 있어야 함 — 파편화된 서브넷에선 실패 (오래된 클러스터의 함정)
- 효과: 작은 인스턴스의 Pod 밀도 정상화 + EC2 API 호출 감소(묶음 단위라)
- 신규 클러스터의 사실상 표준. 단 서브넷 IP **소비 단위도 16개 묶음**이 된다는 것은 인지 (작은 서브넷에선 양날)

## 4. 확장 기능 두 가지 (존재와 용도까지)

### Custom Networking — Pod를 다른 서브넷에

`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true` + ENIConfig CRD: **노드는 원래 서브넷, Pod는 전용(보조 CIDR) 서브넷** — 좁은 VPC에 100.64.0.0/16 같은 비라우팅 대역을 붙여 Pod IP 문제를 해결(16에서 실습). 대가: ENI 하나가 노드 몫으로 빠져 maxPods 감소, 설정 복잡도.

### Security Groups for Pods — Pod별 SG

특정 Pod에만 전용 SG(예: RDS 접근 허용)를 붙입니다 — SecurityGroupPolicy CRD. 노드 SG의 "전부 아니면 전무"를 벗어나는 정밀 제어. 대가: 그 Pod는 **branch ENI**를 소비(밀도 영향), 니트로 한정. NetworkPolicy(k8s 15)와의 관계: SG는 VPC 자원(RDS 등) 접근 제어에, NetworkPolicy는 Pod간에 — 상호 보완.

## 5. 관측 — 장애 전에 묻기

```bash
# ipamd 메트릭 (노드별 IP 재고!)
kubectl get pods -n kube-system -l k8s-app=aws-node -o name | head -1   # aws-node Pod
# 그 Pod에서: curl localhost:61678/metrics → awscni_total_ip_addresses, assigned 등
# ipamd 로그: 노드의 /var/log/aws-routed-eni/ipamd.log (k8s 27에서 본 것)
# EC2 쪽: 서브넷 가용 IP
aws ec2 describe-subnets --query 'Subnets[].{id:SubnetId,free:AvailableIpAddressCount}'
```

운영 알림 두 개는 필수: **서브넷 가용 IP < 임계**, **노드 IP 할당률 > 임계** — 16의 사고를 예방하는 최소 장치.

## 6. 소스/도구에서 확인하기

- amazon-vpc-cni-k8s 리포(29에서 기여 대상!): https://github.com/aws/amazon-vpc-cni-k8s — ipamd 코드, 설정 변수 README
- 타입별 ENI/IP 한도 표: AWS 문서 "IP addresses per network interface per instance type"
- max-pods 계산기: 리포의 `misc/eni-max-pods.txt`, `max-pods-calculator.sh`

## 요약 카드

| 질문 | 답 |
|------|----|
| 노드당 Pod 천장? | ENI×(IP−1)+2 — 인스턴스 타입이 결정 |
| Pod 기동이 빠른 비결? | ipamd의 warm pool (미리 확보한 IP 즉시 지급) |
| warm의 양날? | 속도 ↔ 서브넷 IP 선점 잠식 |
| prefix delegation? | /28(16개) 묶음 할당 — 밀도 ×16, 니트로+연속 블록 필요 |
| Pod별 방화벽? | SG-for-Pod (branch ENI 소비) — VPC 자원 접근 제어용 |
| 필수 알림 2개? | 서브넷 가용 IP, 노드 IP 할당률 |
