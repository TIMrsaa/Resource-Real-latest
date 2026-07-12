# 이론 — skew 정책, 업그레이드 순서, drain의 해부

> **🌱 17세 눈높이 비유: 24시간 영업 식당의 리모델링**
> 문 닫지 않고 식당을 뜯어고칩니다:
> - **주방(control plane)**: 본사 시공팀(EKS)이 무중단으로 교체해줍니다. 단 **새 설비는 구형으로 못 되돌립니다** — 착공 전 점검(preflight)이 전부입니다
> - **홀 테이블(노드)**: 한 구역씩 — "예약 중지" 팻말(cordon)을 걸고, 앉은 손님을 다른 구역으로 안내(drain)한 뒤 교체
> - **지배인의 규칙(PDB)**: "전체 좌석의 ⅔는 항상 영업" — 안내가 이 규칙을 깨게 되면 그 손님은 못 옮깁니다. 규칙이 "좌석 100% 유지"라면? 리모델링은 영원히 시작 못 합니다
> - **메뉴판(API)**: 개편마다 빠지는 메뉴가 있습니다 — 예고문(deprecation)을 미리 읽고 단골(컨트롤러)의 주문을 바꿔놔야, 개편 날 "그 메뉴 없어요" 사태가 안 납니다

---

## 1. 지원 주기 — 미루기의 가격표

- 업스트림: 마이너 릴리스 연 3회, 각 버전 지원 약 14개월
- EKS: 표준 지원 종료 후 **연장 지원 기간엔 클러스터 시간당 요금이 크게 추가**되고, 연장까지 끝나면 자동(강제) 업그레이드
- control plane 마이너는 **1단계씩만** (1.34→1.36 직행 불가). 미룬 버전 수 = 해야 할 업그레이드 횟수

> 노드는 예외적으로 점프 가능 — 노드는 "업그레이드"가 아니라 **새 버전으로 교체**라서, skew만 지키면 구노드(1.33)를 신노드(1.36)로 바로 갈 수 있습니다.

## 2. 버전 skew 정책 — 순서를 만드는 물리 법칙

핵심 규칙: **어떤 컴포넌트도 kube-apiserver보다 신형일 수 없습니다.**

| 컴포넌트 | apiserver 대비 허용 |
|----------|-------------------|
| kubelet (노드) | 같거나 **최대 3 마이너 뒤** (1.36 CP ↔ 1.33~1.36 kubelet) |
| kube-proxy | kubelet과 같은 규칙 (노드 따라감) |
| controller-manager/scheduler | 같거나 1 마이너 뒤 (EKS가 CP로 묶어 관리) |
| kubectl | ±1 마이너 |

두 가지 함의:

1. **순서 고정**: 노드를 먼저 올리면 kubelet > apiserver — 위반. 그래서 CP → 노드 순서는 취향이 아니라 규칙입니다.
2. **여유 확보**: CP를 올려도 노드는 3 마이너까지 합법으로 뒤처질 수 있습니다 — CP만 먼저 올리고 노드는 몇 주에 걸쳐 점진 교체하는 운영이 가능한 근거.

## 3. 업그레이드 runbook 골격

```
[Gate — 비가역 단계 전 preflight]
 G1. EKS cluster insights — ERROR 있으면 중단
 G2. 폐기 API 탐지 — Pluto(정적) + insights(동적)
 G3. 애드온 호환표 — 목표 버전의 default 애드온 버전 확보 (eks 11)
 G4. PDB 전수 점검 — disruptionsAllowed=0 해소
 G5. 백업 (Velero — 36) + 변경 공지 + 롤백 계획

[실행 — 순서 고정]
 1. control plane (EKS 무중단, 비가역, 1 마이너)
 2. 애드온 (새 CP의 default 버전으로 — vpc-cni/coredns/kube-proxy)
 3. 노드 (drain 기반 롤링 교체 — 무중단의 실전)

[검증]
 4. 핵심 워크로드 헬스 → 관측 스택 헬스 → insights 재확인
```

애드온이 2번인 이유: CP가 오른 직후가 "CP-애드온" 정합을 맞출 타이밍이고, 그 다음 노드가 오르면 "노드-애드온(kube-proxy)" 정합까지 맞습니다 (eks 11에서 재론).

## 4. 폐기 API — 세 겹의 탐지망

버전마다 API가 제거됩니다. 업그레이드 후 `no matches for kind` 또는 컨트롤러 침묵 고장을 **미리** 막는 층위:

| 층 | 도구 | 잡는 것 | 놓치는 것 |
|----|------|--------|----------|
| 정책 | reference/api-deprecations 표 | "무엇이 언제 사라지나" | 우리가 그걸 쓰는지 |
| 정적 | Pluto (`detect-files`, `detect-helm`) | 저장소/차트 속 폐기 API | 코드 안에서 호출하는 컨트롤러 |
| 동적 | EKS insights (감사 로그 기반 — 21) | **런타임에 실제 호출된** 폐기 API + 호출 주체 | 아직 배포 안 한 매니페스트 |

정적과 동적은 사각이 서로 반대입니다 — **둘 다** 돌려야 그물이 됩니다.

## 5. drain의 해부 — 무중단 노드 교체의 심장

`kubectl drain <node>` = cordon + 축출의 조합:

```
1. cordon        node.spec.unschedulable=true — 신규 배치 차단 (기존 Pod은 그대로)
2. 축출 루프      노드 위 Pod마다 Eviction API(POST .../pods/<p>/eviction) 호출
   - DaemonSet Pod → 건너뜀 (--ignore-daemonsets)   ← 어차피 노드와 운명공동체
   - mirror/static Pod → 건너뜀
   - emptyDir 있는 Pod → 데이터 소실 경고 (--delete-emptydir-data로 동의)
   - PDB 검사 → 위반이면 429 거부, drain은 재시도하며 대기
3. 대상 Pod 전부 퇴장 → 완료. 노드 교체/종료 안전
```

**축출(eviction)과 삭제(delete)의 차이**가 이 설계의 전부입니다: delete는 무조건 지우지만, eviction은 **API 서버가 PDB를 확인하고 거부할 수 있는** 정중한 요청입니다. 그래서 drain 중에도 가용성 하한이 지켜집니다.

### PDB와의 상호작용 (19의 실전)

```
replicas=3, maxUnavailable=1 → 한 번에 1개씩: 축출 → 새 노드에서 Ready → 다음
replicas=3, minAvailable=3   → 단 1개도 축출 불가 → drain 영구 대기 = 데드락
```

PDB는 안전벨트이자 브레이큽니다 — **잠재 데드락(disruptionsAllowed=0)은 preflight에서 걸러야** 하고, 이것이 lab-01 G4의 정체입니다.

### 관리형 노드그룹은 이걸 자동화합니다

`update-nodegroup-version` 한 번이면: 새 AMI 노드 추가 → 구 노드 cordon+drain(PDB 존중) → 종료, 를 롤링으로. `updateConfig.maxUnavailable`(또는 %)로 동시 교체 폭 조절. 우리의 몫은 PDB를 평소에 바르게 걸어두는 것.

## 6. 전략 스펙트럼

| 전략 | 방법 | 롤백 | 비용 |
|------|------|------|------|
| in-place 롤링 (기본) | 노드그룹 제자리 교체 | 구 AMI로 재롤링(느림) | 최소 |
| Blue/Green 노드그룹 | 새 버전 노드그룹 신설 → 이전 → 구 그룹 삭제 | 구 그룹으로 즉시 복귀 | 일시 2배 |
| Blue/Green 클러스터 | 새 클러스터 → 트래픽 전환 | DNS/LB 되돌림 | 최대 (큰 점프·규제용) |

CP가 비가역이므로, "CP 버전 자체를 되돌릴 가능성"까지 원하면 답은 클러스터 Blue/Green뿐입니다.

## 7. 소스/도구에서 확인하기

- drain 로직: `staging/src/k8s.io/kubectl/pkg/drain/` — DaemonSet/mirror Pod 필터와 재시도 루프
- **PDB 검사의 실체**: `pkg/registry/core/pod/storage/eviction.go` (kube-apiserver) — Eviction 서브리소스가 PDB를 확인하고 429를 돌려주는 그 코드 (42 코드투어의 좋은 목적지)
- Pluto: https://github.com/FairwindsOps/pluto
- 폐기 API 가이드: https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- EKS insights: https://docs.aws.amazon.com/eks/latest/userguide/cluster-insights.html

## 요약 카드

| 질문 | 답 |
|------|----|
| 순서와 그 근거? | CP → 애드온 → 노드. "apiserver보다 신형 금지" skew 규칙이 강제 |
| CP 마이너 점프? | 불가(1단계씩). 노드는 교체라서 점프 가능 |
| 폐기 API 탐지? | 표(정책) + Pluto(정적) + insights(동적) — 사각이 반대라 셋 다 |
| drain vs delete? | drain은 eviction API — PDB가 거부권을 가짐 |
| 데드락 조건? | disruptionsAllowed=0 (예: minAvailable=replicas) |
| 유일한 비가역? | control plane — 그래서 preflight가 게이트 |
