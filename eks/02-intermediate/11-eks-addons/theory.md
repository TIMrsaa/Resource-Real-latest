# 이론 — 애드온 객체 모델, 버전, 설정, 충돌

> **🌱 17세 눈높이 비유: 정품 펌웨어 vs 커스텀 롬**
> 폰(클러스터)의 기본 앱(CNI/DNS 등)을 관리하는 두 방법:
> - **정품 펌웨어(관리형 애드온)**: 제조사가 기기 OS 버전마다 **호환 검증된 앱 버전 목록**을 주고, 업데이트도 버튼 하나. 설정은 제조사가 허용한 옵션 화면(스키마) 안에서만
> - **커스텀 롬(자가 설치)**: 뭐든 가능하지만 호환성 검증·업데이트·고장 수리가 전부 내 일
> 그리고 정품 펌웨어의 철칙: 시스템 파일을 직접 고치면(kubectl edit) **다음 동기화 때 원복**됩니다 — 설정은 공식 옵션 화면(configuration-values)으로만

---

## 1. 애드온 객체 모델

```
Addon (EKS API 객체)
├ addonName / addonVersion        무엇을 어느 버전으로
├ configurationValues (JSON/YAML) 커스텀 설정 — 스키마 검증됨!
├ resolveConflicts                OVERWRITE | PRESERVE | NONE
├ podIdentityAssociations/IRSA    드라이버 권한 (09)
└ status: ACTIVE | DEGRADED | UPDATE_FAILED ...
     ↓ EKS가 reconcile
클러스터 안의 실물: DaemonSet/Deployment/CRD들 (kube-system)
```

종류: AWS 제공(vpc-cni, coredns, kube-proxy, ebs/efs-csi, pod-identity-agent, snapshot-controller, guardduty agent...) + Marketplace/커뮤니티(서드파티).

## 2. 버전 — 호환 매트릭스의 조회

```bash
# 이 K8s 버전에서 쓸 수 있는 애드온 버전들 (+기본 버전 표시)
aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version 1.36 \
  --query 'addons[0].addonVersions[].{v:addonVersion,default:compatibilities[0].defaultVersion}'
```

- **default**: 그 K8s 버전에서 AWS가 기본으로 미는 검증 버전 — 무난한 선택
- latest가 항상 좋은 게 아닙니다: 현 CP 버전 미지원일 수 있음 (조회가 먼저)
- 클러스터 업그레이드 순서(k8s 35): **CP → 애드온(새 CP의 default로) → 노드** — 애드온이 가운데인 이유: CP와의 호환을 먼저 맞추고, 노드 교체는 그 후

## 3. configuration-values — 선언적 설정의 통로

```bash
# 스키마부터 — 무엇을 바꿀 수 있는지의 공식 목록
aws eks describe-addon-configuration --addon-name coredns --addon-version <v> \
  --query 'configurationSchema' --output text | python3 -m json.tool | head -30
# 적용
aws eks update-addon --addon-name coredns --configuration-values '{"replicaCount":3}'
```

- 스키마 밖 키는 **검증 단계에서 거부** — 오타가 조용히 무시되지 않습니다 (장점!)
- 07에서 한 `ENABLE_PREFIX_DELEGATION`도 이 통로였습니다 — 진실의 원천 단일화
- ClusterConfig(eksctl)의 addons 섹션에 넣으면 IaC까지 완성 (eks 02)

## 4. 충돌 해결 — "내 수정이 사라진" 원리

| resolveConflicts | 생성/업데이트 시 동작 |
|------------------|----------------------|
| OVERWRITE | EKS 관리 필드를 애드온 정의값으로 강제 (kubectl 수정 패배) |
| PRESERVE | 기존 값 보존 (마이그레이션용 — 단 관리 포기 아님) |
| NONE | 충돌 시 실패로 알려줌 |

내부적으로 **server-side apply의 필드 소유권**(k8s 24!)을 씁니다 — EKS가 owner인 필드를 kubectl이 고치면, 다음 reconcile/업데이트에서 EKS 소유권이 회복됩니다. "고쳤는데 원복"의 정체 = **필드 매니저 싸움에서 진 것.** 커스텀은 스키마가 허용하는 한 configuration-values로, 스키마 밖 요구면 자가 관리 전환을 검토.

## 5. 운영 루틴

```
분기(또는 CP 업그레이드 시):
1. aws eks list-addons + describe-addon → 현 버전 인벤토리
2. describe-addon-versions로 대상 CP의 default 확인
3. 스키마 diff 확인(설정 키 변경 여부) → update-addon (한 번에 하나, 핵심부터)
4. status ACTIVE + 워크로드 스모크 확인
상시: status가 DEGRADED/UPDATE_FAILED면 알림 (콘솔 추가 기능 탭의 그 표시 — eks 03)
```

## 6. 소스/도구에서 확인하기

- 애드온 문서: https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html
- 각 애드온의 스키마: `describe-addon-configuration` (버전마다 다를 수 있음)
- eksctl addons: https://eksctl.io/usage/addons/

## 요약 카드

| 질문 | 답 |
|------|----|
| 애드온의 진실의 원천? | EKS Addon 객체 (클러스터 안 실물은 출력물) |
| kubectl 수정이 원복되는 원리? | SSA 필드 소유권 — EKS가 owner (k8s 24) |
| 설정 통로? | configuration-values (스키마 검증) |
| 버전 선택 기준? | 대상 K8s 버전의 default (describe-addon-versions) |
| 업그레이드 순서? | CP → 애드온 → 노드 (k8s 35) |
| 관리형 vs 자가? | 핵심 4종은 관리형, 스키마 밖 요구면 자가 |
