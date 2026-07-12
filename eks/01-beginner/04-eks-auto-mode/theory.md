# 이론 — Auto Mode의 구조, 경계선 v2, 트레이드오프

> **🌱 17세 눈높이 비유: 자가용 → 렌터카 → 택시**
> - 표준 EKS = **렌터카**: 차(노드)는 빌리지만 주유·세차·정비 예약(패치/교체)은 내가
> - Auto Mode = **택시**: 차가 알아서 오고(프로비저닝), 정비는 회사가, 나는 목적지(워크로드)만.
>   요금에 서비스료가 붙고(추가 과금), 차를 개조할 수 없으며(노드 접근 불가), 같은 차를 오래 탈 수도 없습니다(최대 수명 후 교체)
> - Fargate = **지하철**: 차라는 개념 자체가 없음 — 대신 노선(제약)이 정해져 있습니다

---

## 1. Auto Mode가 가져가는 것 — 경계선 v2

모듈 01의 표에 Auto Mode 열을 추가하면:

| 영역 | 표준 EKS | Auto Mode |
|------|----------|-----------|
| control plane | AWS | AWS |
| 노드 프로비저닝 | 나 (노드그룹/Karpenter 설치) | **AWS (Karpenter 내장)** |
| 노드 OS/패치 | 나 (AMI 교체 트리거) | **AWS (자동, 최대 수명 내 강제 교체)** |
| 핵심 애드온 (CNI/CoreDNS/kube-proxy) | 회색 (관리형 애드온) | **내장 (노드 안에서 systemd로 — Pod로 안 보임!)** |
| EBS CSI / ALB 컨트롤러 | 내가 설치 (10, 08) | **내장 컨트롤러** |
| 노드 접근 (SSH/SSM) | 가능 | **불가** |
| OS | 선택 (AL2023/Bottlerocket) | **Bottlerocket 고정** |
| 요금 | EC2 그대로 | EC2 + **관리 수수료(인스턴스 요금에 비례)** |

### 충격 포인트: kube-system이 한산합니다

Auto Mode 노드에선 VPC CNI·kube-proxy 같은 것이 **DaemonSet Pod가 아니라 노드 내장 프로세스**로 돕니다 — `kubectl get pods -n kube-system`이 허전한 게 정상. "보이지 않는 컴포넌트"의 영역이 노드 안까지 확장된 것 (k8s 26에서 배운 kubelet과 같은 지위로 CNI가 들어간 셈).

## 2. NodePool — Karpenter 문법의 재등장

Auto Mode는 두 내장 NodePool을 제공합니다:

```
general-purpose   일반 워크로드용 (기본 활성)
system            시스템 워크로드용 (CriticalAddonsOnly taint)
```

커스텀 NodePool도 Karpenter API(`karpenter.sh/v1`)로 만듭니다 — 단 인스턴스 요구사항 키가 `eks.amazonaws.com/` 접두사 계열:

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata: { name: spot-arm }
spec:
  template:
    spec:
      requirements:
      - { key: "eks.amazonaws.com/instance-category", operator: In, values: [c, m, r] }
      - { key: "karpenter.sh/capacity-type", operator: In, values: [spot] }
      - { key: "kubernetes.io/arch", operator: In, values: [arm64] }
      nodeClassRef: { group: eks.amazonaws.com, kind: NodeClass, name: default }
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized   # 빈/저활용 노드 자동 회수
```

→ **모듈 17(Karpenter 심층)의 선행 학습이 됩니다**: 같은 엔진, 같은 설계 사고(요구사항 기반 프로비저닝, consolidation). Auto Mode에서 문법을 익히고 17에서 내부를 팝니다.

## 3. 운영 모델의 변화

| 표준에서 하던 일 | Auto Mode에선 |
|------------------|---------------|
| 노드그룹 버전 업그레이드 (k8s 35) | 자동 — 최대 수명(기본 21일) 내 롤링 교체. **PDB(k8s 19)가 유일한 안전벨트** |
| 노드 장애 대응 (k8s 38 #10) | 자동 감지/교체 — 단 "왜"는 여전히 내가 알아야 |
| 노드 SSH 디버깅 (k8s 26) | 불가 — `kubectl debug node`(제한적)와 관측성(12)으로 대체 |
| bin-packing/비용 (k8s 25, eks 22) | consolidation이 자동 — 검증은 내 몫 |

핵심 변화: **"노드를 고친다" → "노드는 갈아치워집니다(cattle의 완성), 나는 워크로드가 그 교체를 견디게 만든다".** PDB·graceful shutdown(k8s 14)·상태 외부화(k8s 08)가 전제 조건이 됩니다 — 21일마다 모든 노드가 반드시 교체되므로 "노드 교체를 못 견디는 워크로드"는 Auto Mode에서 살 수 없습니다.

## 4. 선택 기준

**적합**: 신규 클러스터, 표준 웹/API 워크로드, 노드 운영 인력을 아끼고 싶은 팀, Spot 적극 활용
**부적합/주의**:
- 커스텀 AMI/커널 모듈/노드 데몬 (보안 에이전트가 DaemonSet이면 OK, 호스트 설치형이면 불가)
- 노드 직접 접근이 필수인 규제/디버깅 요구
- GPU 특수 구성 (지원 범위 확인 필요 — 19)
- 관리 수수료가 부담스러운 거대 규모 (직접 Karpenter 운영과 비용 비교 — 17)

## 5. 소스/도구에서 확인하기

- Auto Mode 문서: https://docs.aws.amazon.com/eks/latest/userguide/automode.html
- 요금 (관리 수수료): https://aws.amazon.com/eks/pricing/
- NodePool API 차이: Auto Mode의 NodeClass는 `eks.amazonaws.com` 그룹 (오픈소스 Karpenter는 `karpenter.k8s.aws`)

## 요약 카드

| 질문 | 답 |
|------|----|
| Auto Mode가 추가로 가져간 것? | 노드 수명주기 전부 + 핵심 애드온 + EBS/ALB 컨트롤러 |
| 내장 스케일러? | Karpenter (NodePool 문법 그대로 — 17의 예습) |
| kube-system이 허전한 이유? | CNI/kube-proxy가 노드 내장 프로세스로 |
| 대가 3가지? | 관리 수수료, 노드 접근 불가, 최대 수명(강제 교체) |
| 생존 전제? | PDB + graceful shutdown — 노드 교체를 견디는 워크로드 |
| 표준 모드가 남는 곳? | 커스텀 AMI/호스트 접근/특수 GPU/수수료 회피 |
