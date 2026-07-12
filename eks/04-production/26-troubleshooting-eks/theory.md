# 이론 — 계층 심문법과 EKS 10대 장애 진단 카드

> **🌱 17세 눈높이 비유: 방에 불이 안 켜집니다**
> - **앱 계층** = 전구가 나갔나요? (제일 싸고 흔한 원인 — 먼저 봅니다)
> - **k8s 계층** = 스위치가 꺼졌나요? 방 두꺼비집이 내려갔나요?
> - **EKS 관리면** = 우리 집 계량기 문제인가요?
> - **AWS 인프라** = 동네 전체가 정전인가요? (제일 비싸고 드문 원인 — 마지막에 확인)
> 초보는 동네 정전부터 의심하며 한전에 전화하고, 숙련자는 전구부터 돌려봅니다. 그리고 둘 다보다 빠른 사람은 묻습니다 — **"어제까지 됐나요? 뭘 바꿨나요?"**

---

## 1. 4계층과 그 CCTV

```
④ 앱          로그(12의 파이프라인), 앱 메트릭
③ k8s 오브젝트  kubectl describe/events(★1h 후 소멸), get -o yaml, 컨트롤러 로그
② EKS 관리면    감사 로그(21), insights, describe-addon health.issues(11)
① AWS 인프라    CloudTrail, Flow Logs(18), ipamd 로그(07), 서비스 상태 페이지
```

**심문 순서 = ④→①** (싸고 흔한 것부터). 단 증상이 명백히 특정 계층을 가리키면 직행합니다 — 그 판정을 돕는 것이 아래 카드들입니다.

## 2. 진단 카드 10장

### 카드 1 — Pod가 ContainerCreating에서 영원히 (IP 고갈)

- **증상**: 새 Pod만 안 뜹니다, 기존은 정상. `describe pod`에 `failed to assign an IP address to container`
- **확진**: `aws ec2 describe-subnets --query 'Subnets[].AvailableIpAddressCount'` → **AZ별 최솟값** 확인 / `kubectl logs -n kube-system ds/aws-node -c aws-node | grep -i "no available"`
- **처방**: 즉시 — 여유 AZ로 Pod 유도(nodeSelector)·불필요 Pod 정리. 근본 — warm 회수/prefix delegation/secondary CIDR (**16**)
- **함정**: 노드를 더 붙이면 warm 선점으로 악화

### 카드 2 — Pod가 Pending, 이벤트는 Insufficient

- **증상**: `0/N nodes are available: Insufficient cpu` (또는 nvidia.com/gpu)
- **확진**: `kubectl describe pod`의 이벤트 전문 — 어떤 자원이 부족한가 / `kubectl top nodes` / GPU면 device plugin 등록 확인(**19**)
- **처방**: requests 조정(22), Karpenter NodePool limits·requirements 확인(**17**), taint 대응 toleration 누락 확인
- **함정**: Karpenter가 노드를 안 만드는 이유가 limits 상한이거나 requirements 불일치인 경우가 많습니다 — `kubectl logs -n karpenter deploy/karpenter`가 답을 말해줍니다

### 카드 3 — Pod에서 AWS 호출이 AccessDenied (IRSA/Pod Identity)

- **증상**: 앱 로그에 `AccessDenied`/`UnauthorizedOperation`, 혹은 자격증명 자체가 없음(`NoCredentialProviders`)
- **확진**: `kubectl exec` → `env | grep AWS_` (토큰 파일·역할 ARN 주입 여부) / `aws sts get-caller-identity`를 Pod 안에서 / association 확인 `eksctl get podidentityassociation`
- **처방**: SA 이름·ns 오타, 신뢰 정책의 `sub` 조건, 정책의 Resource ARN 범위 — **09**의 3단 점검
- **함정**: SA를 나중에 만들면 Pod 재시작이 필요(토큰 주입은 생성 시점)

### 카드 4 — 유저는 502/503인데 Pod는 건강

- **증상**: ALB 5xx, `kubectl get endpoints`는 정상
- **확진**: ALB access log의 `elb_status_code` vs `target_status_code`(**14**) / TG healthy count / 배포 시각과의 상관
- **처방**: 502=keep-alive 역전 또는 draining 중 전송(preStop·deregistration_delay), 503=healthy 0(readiness gate 미설정) — **14**의 4종 세트
- **함정**: "앱 로그에 오류가 없으니 앱은 무죄"는 맞습니다 — 범인은 ALB↔Pod 경계입니다

### 카드 5 — 노드 NotReady

- **증상**: `kubectl get nodes`에 NotReady, 그 위 Pod들이 축출되기 시작
- **확진**: `kubectl describe node`의 Conditions(MemoryPressure/DiskPressure/PIDPressure) → `kubectl debug node/<n>`로 kubelet·containerd 상태 / EC2 상태 검사 / 새 노드라면 access entry·SG(**02·05**)
- **처방**: 디스크 압박이면 이미지 GC·볼륨, 메모리면 requests 정합, 조인 실패면 IAM·네트워크 배선
- **함정**: 노드 하나가 아니라 **전 노드 동시 NotReady**면 CP↔노드 통신(SG/엔드포인트)이나 애드온 사고를 의심

### 카드 6 — DNS 간헐 실패

- **증상**: 무작위 `Name or service not known`, 재시도하면 성공
- **확진**: `kubectl -n kube-system logs deploy/coredns` / CoreDNS replicas·CPU / `conntrack -S`의 insert_failed(노드에서) / 앱의 `ndots` 설정
- **처방**: CoreDNS 스케일·PDB, NodeLocal DNSCache, `dnsConfig.ndots:2`로 검색 도메인 순회 축소 (k8s **16**)
- **함정**: "DNS가 느리다"의 절반은 ndots=5로 인한 불필요한 조회 4번

### 카드 7 — 애드온이 DEGRADED / 설정이 원복됨

- **증상**: `describe-addon` status DEGRADED, 또는 kubectl로 고친 설정이 며칠 뒤 사라짐
- **확진**: `aws eks describe-addon ... health.issues` / 해당 컴포넌트 로그 / `--show-managed-fields`로 필드 소유자(**11**)
- **처방**: configuration-values로만 설정, 버전은 default 기준, 실패 시 직전 버전 롤백
- **함정**: 애드온은 롤백 가능(CP와 달리) — 겁먹지 말 것

### 카드 8 — 볼륨이 안 붙습니다 (EBS/EFS)

- **증상**: Pod가 `Volume is already exclusively attached`/`FailedAttachVolume`으로 정지
- **확진**: `kubectl describe pvc/pv`, CSI 컨트롤러 로그 / **AZ 불일치**(EBS는 AZ 고정!) / 노드 IAM의 CSI 권한
- **처방**: StatefulSet·RWO 워크로드의 존 고정(topology), Recreate 전략, 스냅샷 복원 시 존 확인 (**10**)
- **함정**: 노드가 다른 AZ에서 스케줄되면 EBS는 원리상 붙을 수 없습니다 — 스케줄러 문제가 아니라 물리 문제

### 카드 9 — Pod 간 통신 불가 (정책/방화벽)

- **증상**: A→B 타임아웃, DNS는 정상
- **확진**: **18의 진단 계단** — netpol → SG → NACL → 라우팅 → Flow Logs(REJECT면 SG/NACL 확정, ACCEPT면 NP 재심문)
- **처방**: 계단이 지목한 층
- **함정**: Flow Logs의 ACCEPT는 무죄 증명이 아닙니다(NP 드롭은 안 찍힙니다)

### 카드 10 — 스케일이 멈췄습니다 (HPA/Karpenter 동결)

- **증상**: 부하가 느는데 replicas·노드가 그대로
- **확진**: `kubectl describe hpa`(메트릭 unknown?) → 메트릭 파이프라인(Prometheus/adapter — **15**) / `kubectl get pdb -A`(disruptionsAllowed=0이면 consolidation·drain도 동결) / Karpenter 로그·NodePool limits
- **처방**: 메트릭 복구, CPU 메트릭 병기(안전망), PDB 완화, limits 상향
- **함정**: HPA는 메트릭을 못 읽으면 **현 replicas로 동결**됩니다 — 조용해서 더 위험

## 3. "어제까지 됐다"의 힘 — 변경 우선 심문

```
1. 최근 배포? (rollout history / git log — 39)
2. 애드온·노드 업데이트? (21의 runbook 이력)
3. 정책·권한 변경? (CloudTrail: IAM/SG/NACL 변경 이벤트)
4. AWS 쪽 사건? (Health Dashboard)
```

증상이 모호할수록 이 네 질문이 계층 심문보다 빠릅니다 — 원인의 대다수는 **최근의 변경**입니다.

## 4. 도구상자

| 도구 | 자리 |
|------|------|
| `kubectl debug node/<n>` | 노드 안(라우팅·프로세스·로그) — SSH 없이 |
| netshoot 이미지 | Pod 안 네트워크 진단(ping/traceroute/ss/tcpdump) |
| `kubectl events --for pod/x` | 이벤트(1시간 소멸 — 급하면 먼저 저장) |
| `aws eks describe-addon/insights` | EKS 관리면의 진실 |
| Flow Logs / 감사 로그 / CloudTrail | 각 계층의 CCTV |
| ipamd·컨트롤러 로그 | 07·08의 내부 사정 |

## 5. 소스/도구에서 확인하기

- EKS 트러블슈팅 공식: https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html
- EKS Best Practices Guide — 각 장의 "Troubleshooting" 절
- `eks-node-viewer`, `kube-capacity` — 자원 압박 즉석 파악

## 요약 카드

| 질문 | 답 |
|------|----|
| 심문 순서? | 앱 → k8s → EKS 관리면 → AWS (싸고 흔한 것부터) |
| 그보다 빠른 질문? | "어제까지 됐나요? 뭘 바꿨나" — 변경 우선 심문 |
| ContainerCreating 정지? | IP 고갈 의심 → describe-subnets의 **AZ별 최솟값** |
| 502/503인데 Pod 정상? | ALB 경계 — elb vs target status code |
| Flow Logs ACCEPT + 불통? | NetworkPolicy(또는 앱) — CCTV의 사각 |
| HPA 침묵? | 메트릭 unknown → 현 replicas 동결 (파이프라인 확인) |
| 이벤트의 수명? | 약 1시간 — 급하면 먼저 저장하세요 |
