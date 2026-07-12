# 이론 — 멀티테넌시 스펙트럼과 테넌트 패키지 설계

> **🌱 17세 눈높이 비유: 건물을 나눠 쓰는 4가지 방법**
> 세 회사가 공간을 나눠 씁니다:
> ① **칸막이 사무실**(ns 격리) — 같은 층, 칸막이+출입증. 싸지만 벽이 얇습니다(커널 공유)
> ② **층 분리**(노드 격리) — 회사마다 전용 층. 시끄러운 이웃 문제 해결
> ③ **별관 임대**(vCluster) — 같은 건물이지만 자기만의 로비/관리실(가상 control plane)
> ④ **독립 건물**(클러스터 분리) — 완전 격리, 비용/관리 최대
> 정답은 없습니다 — **"입주사끼리 얼마나 못 믿는가 + 예산"** 이 결정합니다.

---

## 1. 스펙트럼과 선택 기준

| 수준 | 격리 수단 | 막는 것 | 못 막는 것 | 적합 |
|------|----------|---------|-----------|------|
| ① ns 기반 (소프트) | RBAC+Quota+NetPol+PSA | 실수, 가벼운 악용 | 커널 취약점, 클러스터 리소스 충돌 | 사내 팀들 (상호 신뢰) |
| ② +노드 격리 | taint/toleration+affinity | 노이지 네이버, 노드 레벨 측면 공격 | control plane 공유 이슈 | 민감 워크로드 혼재 |
| ③ vCluster | 가상 control plane (테넌트별 API서버/etcd를 호스트 ns 안 Pod로) | CRD/웹훅/버전 충돌 — **테넌트가 cluster-admin처럼 행동 가능** | 커널 공유 (노드는 여전히 공용 가능) | 플랫폼팀이 "클러스터를 서비스로" 제공 |
| ④ 클러스터 분리 | 물리적 별도 | 전부 | — (비용/운영만 남음) | 외부 고객, 규제, prod |

> 모듈 09에서 약속한 답: **prod는 ④, 사내 dev/staging은 ①~②**가 일반 권고의 근거가 이 표입니다.

## 2. 테넌트 ns 패키지 — 5종 세트 (lab-01에서 조립)

새 테넌트 = ns 하나 + 아래 다섯 가지가 **반드시 같이**:

```
1. RBAC        팀 그룹 ↔ edit(또는 커스텀) RoleBinding — "자기 방만" (11)
2. ResourceQuota   CPU/메모리/Pod 수/LB 개수 상한 — "전기요금 한도" (09)
3. LimitRange      기본값 주입 — Quota의 짝꿍 (09)
4. NetworkPolicy   기본 거부 + 자기 ns 허용 + DNS — "방문 잠금" (15)
5. PSA 라벨        enforce=baseline, warn=restricted — "안전 수칙" (32)
```

하나라도 빠지면: RBAC 없음→남의 방 출입, Quota 없음→한 팀이 클러스터 독식, NetPol 없음→옆 팀 DB 직접 접속(09의 그 실험), PSA 없음→privileged로 노드 장악.

### 패키지 + 셀프서비스의 진화

패키지를 수동 apply → Helm 차트(17) → **테넌트 Operator**(30): "Tenant"라는 CRD를 만들면 컨트롤러가 5종 세트를 찍어내는 구조. 실제 오픈소스: Capsule, HNC(계층 ns). 우리는 모든 부품을 만들 줄 압니다 — 조립 선택의 문제.

## 3. 노드 격리 — 12의 공식 재사용

```
테넌트 A 전용 노드: taint tenant=a:NoSchedule + 라벨 tenant=a
테넌트 A의 Pod:    toleration + nodeAffinity(tenant=a)   ← 3종 세트 (모듈 12)
```

- 강제의 빈틈: 테넌트가 toleration을 "안 쓰면" 공용 노드로 갈 수 있고, "남의 것을 쓰면"? — taint 키를 비밀로 할 수는 없으니 **admission(23)으로 ns별 허용 toleration을 강제**하는 것이 완성형 (PodTolerationRestriction 또는 VAP/Kyverno)
- 비용 트레이드오프: 전용 노드 = bin-packing 효율 하락 — Karpenter의 NodePool 분리(eks 파트 17)가 이 운영을 자동화

## 4. ns로 절대 안 되는 것들 (③으로 가는 신호)

- **CRD 버전 충돌**: CRD는 클러스터 스코프 — A팀이 cert-manager v1.14, B팀이 v1.16을 원하면 끝
- 웹훅/admission 충돌: 한 팀의 웹훅이 전 클러스터에 영향 (23의 폭발 반경)
- K8s 버전 선택권, control plane 튜닝 욕구
- 이런 요구가 쌓이면 vCluster(테넌트별 가짜 API 서버 — 실제 Pod는 호스트 클러스터에 동기화) 또는 ④

## 5. 운영 디테일

- **테넌트별 비용 추적**: ns 라벨(`cost-center`) + Quota 사용량 + OpenCost(eks 파트 22) — "쓴 만큼 보여주기"가 Quota 협상의 평화 유지군
- **공정성**: Quota는 상한일 뿐 보장이 아닙니다 — 핵심 테넌트에는 PriorityClass(12)와 전용 노드로 보장을
- 클러스터 스코프 리소스 보호: 테넌트에게 ClusterRole 생성권을 주지 않기 — escalation 방지(11)의 실전 의미

## 6. 소스/도구에서 확인하기

- Capsule (테넌트 Operator): https://github.com/projectcapsule/capsule
- vCluster: https://github.com/loft-sh/vcluster — "API 서버를 Pod로" 구조가 모듈 02 이해도를 시험합니다
- 공식 멀티테넌시 가이드: https://kubernetes.io/docs/concepts/security/multi-tenancy/

## 요약 카드

| 질문 | 답 |
|------|----|
| 스펙트럼 결정 질문? | 상호 신뢰 수준 / 노이지 허용치 / 클러스터 리소스 필요 / 운영 여력 |
| 테넌트 패키지 5종? | RBAC, Quota, LimitRange, NetworkPolicy, PSA |
| 노드 격리 공식? | taint+toleration+affinity (+admission으로 toleration 통제) |
| ns로 불가능한 요구? | CRD/웹훅/버전의 테넌트별 분리 → vCluster/클러스터 분리 |
| Quota의 한계? | 상한이지 보장 아님 — 보장은 Priority+전용 노드 |
