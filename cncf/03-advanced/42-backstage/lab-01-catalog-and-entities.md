# Lab 01 — Software Catalog와 Entity 모델

> Backstage 전체를 kind에 띄우는 것은 무겁습니다(Node 앱·DB·플러그인). 이 랩은 **카탈로그의 핵심인 Entity 모델**을 catalog-info.yaml로 직접 설계하고, 서비스 의존 그래프를 손으로 그려 보며 24의 마이크로서비스 지형을 Backstage가 어떻게 표현하는지 익힙니다. 원하면 마지막에 로컬 Backstage 실행법을 안내합니다.

## 1. 시나리오 — 작은 전자상거래 지형

```
System: shop
  Component: storefront (웹)     → owner: web-team
  Component: order-service       → owner: order-team
  Component: payment-service     → owner: payments-team
  API: order-api (order-service 제공)
  API: payment-api (payment-service 제공)
  Resource: orders-db            (order-service 의존)
  Resource: payments-db          (payment-service 의존)
```

## 2. Entity를 catalog-info.yaml로 (직접 작성)

```yaml
# storefront/catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: storefront
  description: 고객 웹 스토어프론트
spec:
  type: website
  lifecycle: production
  owner: web-team
  system: shop
  consumesApis:
    - order-api          # storefront → order-api 소비
    - payment-api
```

```yaml
# order-service/catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: order-service
  description: 주문 처리
spec:
  type: service
  lifecycle: production
  owner: order-team
  system: shop
  providesApis: [order-api]         # 제공
  dependsOn: [resource:orders-db]   # DB 의존
---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: order-api
spec:
  type: openapi
  lifecycle: production
  owner: order-team
  system: shop
  definition: |
    openapi: 3.0.0
    info: { title: Order API, version: 1.0.0 }
    paths: { /orders: { post: { summary: 주문 생성 } } }
```

```yaml
# 인프라 Entity (41의 Resource와 연결)
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: orders-db
spec:
  type: database
  owner: order-team
  system: shop
```

```yaml
# 조직 Entity (소유권의 대상)
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: order-team
spec:
  type: team
  children: []
```

## 3. 관계 그래프를 그려 보기

catalog-info.yaml의 관계 필드가 만드는 그래프를 손으로 그립니다:

```
              [web-team]        [order-team]      [payments-team]
                  │ownedBy          │ownedBy            │ownedBy
              [storefront]      [order-service]   [payment-service]
                  │                  │providesApi        │providesApi
      consumesApi │  ┌───────────[order-api]      [payment-api]
                  ├──┘                                    ▲
                  └────────────────────────consumesApi───┘
                                     │dependsOn        │dependsOn
                                 [orders-db]       [payments-db]
              모두 partOf → System: shop
```

**관찰** — 이 그래프가 Backstage 카탈로그의 핵심 가치입니다. 신입이 "결제는 누가?"라고 물으면 `payment-service → ownedBy → payments-team`을 즉시 압니다. "order-api를 누가 쓰나요?"는 `consumesApi` 역방향으로 `storefront`임을 압니다. 24의 서비스 의존 그래프가 **문서가 아니라 코드(catalog-info.yaml)에서** 자동으로 그려집니다.

## 4. 왜 이게 "낡지 않나" — 위키와의 결정적 차이

```
위키 방식: 별도 위키 페이지에 "order-service는 orders-db를 씀"
  → 코드가 바뀌어도 위키는 그대로 → 6개월 뒤 거짓말

Backstage 방식: catalog-info.yaml이 레포에 삶
  → 의존이 바뀌면 PR에서 함께 수정 (14의 코드 리뷰)
  → 코드와 함께 버전 관리 → 진실 유지
```

이것이 42의 핵심 통찰 — **메타데이터를 코드 옆에 두면 낡지 않습니다**(14 GitOps의 "코드가 진실의 원천"을 조직 지식에 적용).

## 5. (선택) 로컬 Backstage 실행

실제로 보고 싶다면 (Node 18+ 필요, 무겁습니다):

```bash
# 로컬 Backstage 앱 생성 (시간·자원 소요)
npx @backstage/create-app@latest
# → 이름 입력 → 앱 생성
cd my-backstage
yarn dev
# http://localhost:3000 에서 카탈로그 UI

# 위에서 만든 catalog-info.yaml들을 등록:
# UI → Create → Register Existing Component → GitHub URL
```

kind 클러스터가 있으면 Kubernetes 플러그인으로 배포 현황도 각 Component 페이지에 붙일 수 있습니다(플러그인 설정 필요).

## 6. 정리

- Entity(Component·API·System·Resource·Group)와 관계(ownedBy·partOf·provides/consumesApi·dependsOn)로 지형을 표현
- catalog-info.yaml이 **코드 옆에 삶** → 자동 수집 → 낡지 않음(14의 정신)
- 관계 그래프가 24의 서비스 의존을 눈으로 — "누가 소유·제공·소비·의존"
- Resource가 41(Crossplane Managed Resource)과 연결 — 인프라도 카탈로그에
- **★ 위키의 실패(별도 관리라 낡음) vs Backstage(코드와 함께라 삽니다)**
