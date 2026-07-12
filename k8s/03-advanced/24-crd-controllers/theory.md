# 이론 — CRD, 가비지 컬렉션, Finalizer, Server-Side Apply

> **🌱 17세 눈높이 비유: 시청에 "새 민원 양식"을 등록하기**
> 시청(API 서버)에는 기본 민원 양식(Pod, Service...)이 있습니다. **CRD는 "반려동물 등록증"이라는 새 양식을 시청에 정식 등록**하는 것입니다 — 등록하는 순간 접수창구(REST API), 양식 검사(스키마), 열람 구독(watch)이 자동으로 생깁니다.
> - **ownerReference** = 서류에 적힌 "상위 서류 번호". 상위 서류가 파기되면 청소부(GC)가 딸린 서류도 파기.
> - **finalizer** = 서류의 "파기 전 처리 목록" 스티커. "이 등록증 파기 전에 보호소에 통보할 것" — 통보 담당자가 스티커를 떼기 전까지 서류는 **파기 대기 상태로 보존**됩니다.
> - **server-side apply** = 한 서류를 여러 부서가 고칠 때, **필드마다 담당 부서 도장**을 찍어 누가 어느 칸의 주인인지 기록하는 제도.

---

## 1. CRD — 새 리소스 종류의 등록

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: websites.platform.example.com     # <plural>.<group> 형식 필수
spec:
  group: platform.example.com
  scope: Namespaced                        # 또는 Cluster
  names:
    kind: Website
    plural: websites
    singular: website
    shortNames: [ws]                       # kubectl get ws
  versions:
  - name: v1
    served: true                           # API로 제공
    storage: true                          # etcd 저장 버전 (정확히 1개만 true)
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: [image, replicas]
            properties:
              image: { type: string, pattern: '^.+:.+$' }      # 검증 내장!
              replicas: { type: integer, minimum: 1, maximum: 10 }
              domain: { type: string }
          status:                          # 컨트롤러가 쓰는 영역
            type: object
            properties:
              readyReplicas: { type: integer }
              phase: { type: string }
    subresources:
      status: {}                           # ★ /status 분리 (아래)
      scale:                               # kubectl scale + HPA 호환!
        specReplicasPath: .spec.replicas
        statusReplicasPath: .status.readyReplicas
    additionalPrinterColumns:              # kubectl get의 출력 컬럼
    - { name: Ready, type: integer, jsonPath: .status.readyReplicas }
    - { name: Phase, type: string, jsonPath: .status.phase }
```

### 설계 포인트

- **status 서브리소스**: `/status` 엔드포인트를 분리하면 — spec 수정 권한과 status 수정 권한을 RBAC로 나눌 수 있고(사용자는 spec만, 컨트롤러는 status만), 서로의 업데이트가 충돌하지 않습니다. **모든 진지한 CRD의 기본.**
- **CEL 검증 추가** (`x-kubernetes-validations`): 스키마로 안 되는 교차 필드 검증 — `self.minReplicas <= self.maxReplicas` 같은 것. 모듈 23의 CEL이 CRD 안으로
- **버전 전환**: v1alpha1 → v1beta1 → v1. 여러 버전 served 가능, 저장은 1개. 버전 간 변환은 conversion 웹훅 (또 웹훅입니다!)

## 2. ownerReference와 가비지 컬렉션

```yaml
metadata:
  ownerReferences:
  - apiVersion: platform.example.com/v1
    kind: Website
    name: my-site
    uid: 3f7a...                  # 이름이 아니라 uid로 결합 (재생성된 동명이인과 구분)
    controller: true              # "주 관리자" 표시 (1개만)
    blockOwnerDeletion: true
```

삭제 전파 3모드 (`kubectl delete --cascade=`):

| 모드 | 동작 |
|------|------|
| background (기본) | 부모 즉시 삭제 → GC가 자식들을 뒤따라 삭제 |
| foreground | 자식 다 지운 뒤 부모 삭제 (부모가 Terminating으로 대기) |
| orphan | 부모만 삭제, 자식은 고아로 생존 |

> 모듈 04의 "Deployment 지우면 RS/Pod 연쇄 삭제", 모듈 05 사고사례의 "컨트롤러가 죽어 NLB 고아" — 전부 이 메커니즘의 면면입니다.

## 3. Finalizer — 삭제를 가로채는 갈고리

```yaml
metadata:
  finalizers: [platform.example.com/cleanup-dns]
```

삭제의 실제 순서:

```
delete 요청 → 즉시 삭제 ❌ → deletionTimestamp 기록 (Terminating 표시)
→ 컨트롤러가 그걸 보고 뒷정리 수행 (외부 DNS 삭제, S3 비우기...)
→ 컨트롤러가 자기 finalizer를 제거
→ finalizers가 빈 배열이 되는 순간 → 진짜 삭제
```

- 용도: **클러스터 밖 자원**의 정리 보장 (LB, DNS, 클라우드 디스크). PVC의 `kubernetes.io/pvc-protection`이 내장 사례
- "Terminating에 영원히" = 뒷정리 담당 컨트롤러가 죽었거나 에러 → **원인을 고치는 게 정석**, finalizer 수동 제거는 "뒷정리 포기" 선언(고아 자원 각오)임을 알고 최후에만

## 4. Server-Side Apply (SSA) — 필드 소유권

문제: HPA는 replicas를, 사람은 image를, 컨트롤러는 라벨을 — 한 객체를 여럿이 만질 때 누가 뭘 덮어쓰는가요? (모듈 13 pitfall의 일반화)

SSA의 답: **필드마다 관리자(fieldManager)를 기록**합니다 (`metadata.managedFields`).

```bash
kubectl apply --server-side --field-manager=team-a -f deploy.yaml
```

- 내 소유 필드만 갱신, 남의 필드는 그대로 — 안 보내면 "소유 포기"로 해석
- 남의 소유 필드를 바꾸려 하면 → **409 Conflict + 누구 소유인지 알려줌** (`--force-conflicts`로 강탈 가능)
- 컨트롤러 구현의 표준이 됐습니다: "내가 관리하는 필드만 선언하고 SSA로 보낸다" — 3-way merge(client apply)의 모호함이 사라짐

## 5. 컨트롤러 패턴 총정리 (모듈 30의 설계도)

```
   CRD (Website)                      컨트롤러 (모듈 30에서 구현)
   사용자: spec 작성        ──watch──▶  informer가 변화 감지
                                       workqueue에 키 적재
                                       reconcile(키):
                                         자식 리소스(Deployment 등) 생성/수정 [SSA]
                                         ownerReference 설정 [GC 대비]
                                         외부 자원 있으면 finalizer 관리
                                         status 갱신 [/status 서브리소스]
```

## 6. 소스코드에서 확인하기

- GC 컨트롤러: `pkg/controller/garbagecollector/` — ownerReference 그래프 구축과 삭제 전파
- finalizer 처리(삭제 보류): `staging/src/k8s.io/apiserver/pkg/registry/generic/registry/store.go` 의 `Delete` — deletionTimestamp만 찍고 보존하는 분기
- SSA 병합 엔진: `staging/src/k8s.io/apimachinery/pkg/util/managedfields/` + sigs.k8s.io/structured-merge-diff

## 요약 카드

| 질문 | 답 |
|------|----|
| CRD 등록의 효과? | REST API+검증+watch+kubectl이 즉시 생김 |
| status 서브리소스의 이유? | spec(사용자)/status(컨트롤러) 권한·충돌 분리 |
| GC의 결합 키? | ownerReference의 **uid** |
| Terminating에 갇힘의 정체? | finalizer 제거 대기 — 뒷정리 컨트롤러를 확인하세요 |
| SSA의 핵심? | 필드 단위 소유권(managedFields) — conflict가 명시화 |
| Operator의 공식? | CRD(명사) + 컨트롤러(동사) |
