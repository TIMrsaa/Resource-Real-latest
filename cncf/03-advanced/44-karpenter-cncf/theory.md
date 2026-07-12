# 이론 — 두 층, CA vs Karpenter, 동작, NodePool·통합, 판단

> **🌱 17세 눈높이 비유: 미리 산 테이블 세트 vs 손님 보고 맞춤 테이블**
> - **손님(Pod)** = 식당에 온 다양한 인원(2명·8명·단체)
> - **Cluster Autoscaler(4인 테이블만 미리 구매)** = 테이블은 다 4인용. 2명이 와도 4인 테이블(2자리 낭비), 8명이 오면 4인 테이블 2개(어색). 종류가 고정
> - **Karpenter(손님 보고 딱 맞는 테이블 즉시 제작)** = 2명이면 2인, 8명이면 8인 테이블을 그 자리에서. 낭비 없음(빈패킹)
> - **통합(Consolidation, 손님 재배치)** = 띄엄띄엄 앉은 손님을 큰 테이블 하나로 합쳐 작은 테이블 치움(비용↓)
> - **대가** = 테이블을 자주 바꾸면 손님이 자리를 옮겨야 함(노드 churn, Pod 재스케줄) — 식사 중 옮기면 곤란(PDB로 보호)
> - **핵심** = "미리 정한 규격"이 아니라 "실제 수요에 맞춰 실시간으로"

---

## 1. 스케일의 두 층 — Pod와 노드

```
Pod 층 (배운 것):
  HPA(08): 부하 → replicas ↑
  KEDA(18): 이벤트 → 0↔N
  Knative(43): 요청 → scale-to-zero
  VPA(08): Pod 리소스 요청 조정

노드 층 (이 모듈):
  Pending Pod 있음 → 노드 늘림
  노드 놀고 있음 → 노드 줄임
  도구: Cluster Autoscaler, Karpenter

협력:
  HPA가 Pod 100개로 → 노드 부족 → Pending
  → 노드 오토스케일러가 노드 추가 → Pod 스케줄됨
  ★ 두 층이 함께 돌아야 완전한 탄력성
```

## 2. 08 스케줄링의 역방향

```
08 스케줄러:
  주어진 노드들 중 Pod 제약(리소스 요청·nodeSelector·
  affinity·taint/toleration)을 만족하는 노드에 배치
  → 못 찾으면 Pod는 Pending

Karpenter (역방향):
  Pending Pod들의 제약을 모아 분석
  "이 제약들을 만족하는 최적 노드는?"을 계산
  → 그 노드를 프로비저닝 → 스케줄러가 배치

→ Karpenter는 스케줄링 제약을 "거꾸로" 풀어 노드를 결정
→ 그래서 08의 리소스 요청·어피니티·taint를 정확히 알아야
```

## 3. Cluster Autoscaler vs Karpenter

```
                    Cluster Autoscaler       Karpenter
노드 단위           노드그룹(ASG, 고정 타입)  개별 노드(동적 타입)
프로비저닝          노드그룹 desired 조정      직접 노드 생성(JIT)
크기 맞춤           노드그룹 타입에 갇힘        Pod에 딱 맞는 타입 선택
속도                노드그룹 스케일 대기       직접, 더 빠름
빈패킹              제한적                    최적화(여러 타입 고려)
통합                제한적                    consolidation 내장
스팟                노드그룹별                유연(다양한 타입 혼합)
복잡성              단순·오래 검증            강력하나 churn 관리 필요

핵심 차이:
  CA = "미리 정한 규격의 노드를 몇 개"
  Karpenter = "실제 Pending Pod에 최적인 노드를 실시간으로"
  → 딱 맞춤 → 낭비 제거 → 비용 절감
```

## 4. Karpenter 동작 흐름

```
① 관찰(watch)
   스케줄 안 된 Pending Pod를 감시

② 결정(provisioning)
   Pending Pod들의 요구(CPU·메모리·아키텍처·zone·taint)를 모아
   만족하는 가장 효율적인 노드 구성을 계산
   (여러 인스턴스 타입·스팟/온디맨드 후보 중 최적)

③ 프로비저닝
   클라우드 provider로 노드 생성 → 클러스터 조인
   → 스케줄러가 Pending Pod를 새 노드에 배치

④ 통합(consolidation) — 지속
   주기적으로 "더 싸게 될까요?"를 평가:
     - 놀고 있는 노드 제거(empty)
     - 여러 저활용 노드를 큰 노드 하나로 합침(빈패킹)
     - 비싼 노드를 싼 노드로 교체
   → 통합 시 Pod를 안전하게 이동(drain, PDB 준수)

⑤ 중단(disruption) 관리
   노드 만료·통합·스팟 회수 시 → cordon+drain → Pod 재스케줄
   → PDB·graceful shutdown이 이때 작동(09)
```

## 5. NodePool과 NodeClass (선언 모델)

```
NodePool: 어떤 노드를 어떤 제약으로 만들지 (클라우드 중립)
  apiVersion: karpenter.sh/v1
  kind: NodePool
  spec:
    template:
      spec:
        requirements:                    # 08의 스케줄 제약과 대응
          - key: kubernetes.io/arch
            operator: In
            values: [amd64, arm64]       # 여러 아키텍처 허용
          - key: karpenter.sh/capacity-type
            operator: In
            values: [spot, on-demand]    # 스팟 우선, 없으면 온디맨드
        nodeClassRef: { name: default }
    disruption:
      consolidationPolicy: WhenEmptyOrUnderutilized
      consolidateAfter: 30s              # 통합 적극성
    limits:
      cpu: "1000"                        # 이 풀의 총 상한 (폭주 방지)

NodeClass: 클라우드별 노드 세부 (provider 특화)
  AMI/이미지, 보안그룹, 서브넷, 디스크... (클라우드마다 다름)

★ NodePool(중립) + NodeClass(클라우드별) 분리
  = karpenter-core / provider 분리 (41 Crossplane provider 모델과 유사)
```

## 6. 빈패킹과 통합 — 비용의 핵심

```
빈패킹(bin-packing):
  Pod들을 최소 노드에 촘촘히 배치 (낭비 최소)
  Karpenter가 노드 선택 시 여러 타입을 고려해 최적 조합
  예: 3개 작은 Pod → 큰 노드 1개 vs 작은 노드 3개 중 싼 쪽

통합(consolidation):
  시간이 지나며 생긴 비효율을 교정
  - Pod가 줄어 노드가 반쯤 비면 → 다른 노드로 합치고 빈 노드 제거
  - 온디맨드 노드를 스팟으로 교체 가능하면 교체
  → 지속적으로 "지금 이 워크로드의 최소 비용 구성"으로 수렴

대가(theory 계속):
  통합 = 노드 교체 = Pod 재스케줄(churn)
  → 자주 통합하면 Pod가 자주 이동 (안정성 vs 비용 트레이드오프)
  → consolidateAfter로 적극성 조절
```

## 7. 함정과 판단 (pitfalls 예고)

```
함정:
  - 리소스 요청 미설정 → Karpenter가 크기를 모름(08의 requests 필수)
  - PDB 없음 → 통합·중단이 Pod를 한꺼번에 퇴거 → 가용성 붕괴
  - 스팟 100% → 대량 회수 시 동시 중단
  - 과도한 통합 → churn 폭발(끊임없는 재스케줄)

판단:
  Karpenter가 맞음: 다양한 워크로드·가변 부하·비용 최적화 필요
  단순하면: 소규모·균일 워크로드는 CA로 충분
  중단 내성: 워크로드가 PDB·graceful shutdown을 갖춰야
  스팟: 상태 없는·중단 견디는 워크로드에 (스테이트풀은 신중, 09)
```

## 8. 소스/도구에서 확인하기

- Karpenter: https://karpenter.sh — NodePool, NodeClass, disruption, consolidation
- Cluster Autoscaler: https://github.com/kubernetes/autoscaler
- 08(스케줄링·리소스·오토스케일)·09(노드·PDB)·41(provider 모델)·18·43 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| 두 층? | Pod 스케일(HPA·KEDA·Knative) + 노드 스케일(CA·Karpenter) |
| CA vs Karpenter? | 고정 노드그룹 vs Pending Pod에 딱 맞는 노드 JIT 프로비저닝 |
| 08과 관계? | 스케줄링의 역방향 — 제약 만족 노드를 빚음(requests 필수) |
| 동작? | 관찰→결정→프로비저닝→통합→중단관리 |
| NodePool/NodeClass? | 중립 제약 + 클라우드별 세부 (core/provider 분리, 41 유사) |
| 통합(consolidation)? | 비효율 노드 재편으로 비용↓, 대가는 churn(Pod 재스케줄) |
| 대가? | churn·중단 관리·스팟 회수 → PDB·graceful shutdown 필수(09) |
| 판단? | 가변·다양 워크로드+비용 최적화면 Karpenter, 단순하면 CA |
