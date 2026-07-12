# Lab 02 — Composition·XRD·Claim으로 플랫폼 API 만들기

> 플랫폼 팀의 관점에서, 개발자에게 제공할 추상 API(XRD)를 정의하고, 그것이 여러 Managed Resource로 조합되는 Composition을 만들고, 개발자가 Claim으로 셀프서비스하는 전체 흐름을 provider-nop으로 실습합니다. 47(플랫폼 엔지니어링)의 핵심 메커니즘입니다.

## 시나리오

플랫폼 팀이 개발자에게 "데이터베이스 하나 주세요(size만 고르면)" API를 제공하려 합니다. 내부적으로는 DB + 백업버킷 + 모니터링을 한 세트로 만들어야 하지만, 개발자는 그걸 몰라야 합니다.

```
개발자가 원하는 것:  kind: AppDatabase, spec: { size: small }
플랫폼이 만드는 것:  DB(nop) + Bucket(nop) + Monitor(nop)  ← 개발자는 모름
```

## 0. 준비 (lab-01의 Crossplane + provider-nop 설치 가정)

```bash
# lab-01에서 crossplane + provider-nop 설치돼 있어야 함
kubectl get provider provider-nop   # HEALTHY True 확인
```

## 1. XRD — 추상 API 정의 (플랫폼 팀)

XRD(CompositeResourceDefinition)는 "새 API 타입"을 정의합니다 — 개발자가 쓸 어휘를 만듭니다.

```yaml
# xrd.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xappdatabases.platform.example.org
spec:
  group: platform.example.org
  names:
    kind: XAppDatabase          # 클러스터 범위 Composite
    plural: xappdatabases
  claimNames:
    kind: AppDatabase           # 네임스페이스 범위 Claim (개발자용)
    plural: appdatabases
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                parameters:
                  type: object
                  properties:
                    size:
                      type: string
                      enum: [small, medium, large]   # 개발자가 고를 것은 이것뿐
                  required: [size]
              required: [parameters]
```

```bash
kubectl apply -f xrd.yaml
kubectl get xrd
# NAME                                   ESTABLISHED   OFFERED
# xappdatabases.platform.example.org     True          True

# 개발자용 새 API 타입이 생겼습니다
kubectl get crd | grep appdatabase
# appdatabases.platform.example.org       ← Claim (개발자)
# xappdatabases.platform.example.org      ← Composite
```

**관찰** — 회원님이 `AppDatabase`라는 **새 K8s API**를 만들었습니다. 08의 CRD 확장을 플랫폼 팀이 도메인 어휘("우리 회사의 앱 DB")로 쓰는 것입니다.

## 2. Composition — 추상이 무엇으로 구성되는지 (플랫폼 팀)

```yaml
# composition.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: appdatabase-nop
spec:
  compositeTypeRef:
    apiVersion: platform.example.org/v1alpha1
    kind: XAppDatabase
  resources:
    # ① 데이터베이스 (실제라면 RDSInstance)
    - name: database
      base:
        apiVersion: nop.crossplane.io/v1alpha1
        kind: NopResource
        spec:
          forProvider:
            conditionAfter:
              - conditionType: Ready
                conditionStatus: "True"
                time: 5s
    # ② 백업 버킷 (실제라면 S3 Bucket)
    - name: backup-bucket
      base:
        apiVersion: nop.crossplane.io/v1alpha1
        kind: NopResource
        spec:
          forProvider:
            conditionAfter:
              - conditionType: Ready
                conditionStatus: "True"
                time: 5s
    # ③ 모니터링 (실제라면 CloudWatch alarm 등)
    - name: monitoring
      base:
        apiVersion: nop.crossplane.io/v1alpha1
        kind: NopResource
        spec:
          forProvider:
            conditionAfter:
              - conditionType: Ready
                conditionStatus: "True"
                time: 5s
```

```bash
kubectl apply -f composition.yaml
kubectl get composition
# NAME              XR-KIND        XR-APIVERSION
# appdatabase-nop   XAppDatabase   platform.example.org/v1alpha1
```

**핵심** — 하나의 추상(`XAppDatabase`)이 3개의 Managed Resource(DB+버킷+모니터링)로 조합된다고 정의했습니다. 이것이 "황금 경로"다 — 모범 구성을 플랫폼 팀이 한 번 정의하면, 모든 개발자가 같은 안전한 세트를 얻습니다.

## 3. Claim — 개발자의 셀프서비스

이제 개발자 입장. 개발자는 XRD도 Composition도 모릅니다. `size`만 고릅니다.

```yaml
# claim.yaml (개발자가 자기 네임스페이스에)
apiVersion: platform.example.org/v1alpha1
kind: AppDatabase
metadata:
  name: my-app-db
  namespace: default
spec:
  parameters:
    size: small       # 개발자가 아는 것은 이것뿐
```

```bash
kubectl apply -f claim.yaml

# Claim → Composite → 3개 MR이 자동 생성되는 것을 관찰
kubectl get appdatabase my-app-db          # 개발자가 보는 것 (하나)
# NAME        SYNCED   READY   CONNECTION-SECRET
# my-app-db   True     True

kubectl get xappdatabase                    # Composite (플랫폼 층)
kubectl get nopresource                     # 실제 MR 3개!
# NAME                      READY   SYNCED
# my-app-db-xxxxx-database  True    True
# my-app-db-xxxxx-backup-bucket  True  True
# my-app-db-xxxxx-monitoring     True  True
```

**관찰의 핵심** — 개발자는 `AppDatabase` **하나**를 만들었는데, 뒤에서 3개의 리소스가 생겼습니다. 개발자는 백업 버킷·모니터링의 존재조차 몰라도 모범 구성을 자동으로 얻습니다. 이것이 47(플랫폼 엔지니어링)의 셀프서비스 — **인지 부하를 플랫폼 팀이 흡수**합니다.

## 4. 관심사 분리 확인

```
개발자:      size: small  (한 줄, 도메인 언어)
              ↓
플랫폼 팀:    Composition (DB+버킷+모니터링을 어떻게 구성할지)
              ↓
Provider:    실제 클라우드 API 호출
```

- 개발자가 DB를 바꾸고 싶으면 `size`만 수정 → GitOps로 PR(14·15)
- 플랫폼 팀이 "모든 DB에 암호화 추가"를 원하면 Composition 하나만 수정 → 전 개발자에 적용
- **각 층이 자기 관심사만** — 42(Backstage)가 이 Claim 생성을 UI로 감싸면 완전한 IDP

## 5. GitOps 결합 (14·15)

```
Git 저장소:
  platform/xrd.yaml           # 플랫폼 팀 (추상 정의)
  platform/composition.yaml   # 플랫폼 팀 (구성)
  teams/team-a/claim.yaml     # 개발자 (요청)

ArgoCD가 전부 sync → 인프라도 GitOps로 조정
→ Terraform이라면 별도 파이프라인, Crossplane은 기존 GitOps에 얹힘
```

## 6. 정리

```bash
kubectl delete -f claim.yaml
kubectl delete -f composition.yaml
kubectl delete -f xrd.yaml
```

## 정리

- **XRD**: 개발자용 추상 API 타입 정의 (플랫폼 팀의 도메인 어휘)
- **Composition**: 그 추상이 여러 MR로 어떻게 조합되는지 (황금 경로)
- **Claim**: 개발자가 `size`만 골라 셀프서비스 (내부 구성은 몰라도 됨)
- 관심사 분리: 개발자(무엇을) / 플랫폼 팀(어떻게 구성) / Provider(클라우드 API)
- **★ 인지 부하를 플랫폼 팀이 흡수 — 47(플랫폼 엔지니어링)의 핵심 메커니즘, 42(Backstage)가 그 UI**
