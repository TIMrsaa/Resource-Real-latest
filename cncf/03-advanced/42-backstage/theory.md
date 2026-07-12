# 이론 — 포털의 문제, 세 기둥, Entity 모델, 템플릿, IDP, 판단

> **🌱 17세 눈높이 비유: 거대한 학교의 종합 안내 데스크**
> - **학교(조직)** = 학생 300명, 동아리 100개, 교실 수십 개 (마이크로서비스 300개)
> - **혼돈(포털 없음)** = "축구 동아리는 누가 회장이고 어디서 모이지?" → 매번 수소문
> - **Software Catalog(동아리·시설 명부)** = 모든 동아리·교실이 담당자·위치·활동과 함께 한 명부에
> - **Software Template(동아리 창설 키트)** = "새 동아리 만들기" → 신청서+방배정+명부등록이 한 번에 (황금 경로)
> - **TechDocs(각 동아리 소개 게시판)** = 문서가 동아리방(레포) 옆에 있고 안내데스크에서 다 봄
> - **플러그인(현황판)** = 각 동아리 페이지에 활동 사진·예산·일정 통합
> - **핵심** = 흩어진 것을 한 안내 데스크로 — 단, 명부가 자동 갱신돼야 낡지 않음

---

## 1. 포털이 푸는 문제 — 발견성·인지 부하 (24의 규모)

```
마이크로서비스 규모가 만드는 문제 (통신 말고):
  발견성: "무엇이 있고 누구 것인가"를 모름
  인지 부하: 새 서비스·문서·배포 확인마다 재발견
  일관성 부재: 팀마다 다른 방식으로 시작

→ 지식이 사람 머리·흩어진 도구(위키·슬랙·깃헙·모니터링)에 분산

Backstage: 하나의 포털로 집약
  "단일 창(single pane of glass)"
  개발자가 일하는 곳을 하나로
```

## 2. 세 기둥 + 플러그인

```
① Software Catalog
   모든 소프트웨어 자산의 목록 + 메타데이터 + 관계
   자동 수집: 각 레포의 catalog-info.yaml에서
   → 낡지 않음 (코드가 진실의 원천, 14의 정신)

② Software Templates (Scaffolder)
   새 프로젝트를 황금 경로로 생성
   단계: 파라미터 입력 → 레포 생성 → 파일 스캐폴딩
        → CI 설정 → 카탈로그 등록 → (41 인프라 프로비저닝)

③ TechDocs
   docs-as-code: Markdown이 레포에 → MkDocs로 빌드 → 포털에서 렌더
   → 문서가 코드와 함께 버전 관리·리뷰됨

+ 플러그인 (확장)
   Kubernetes(배포 현황), CI/CD, Grafana(06 모니터링),
   PagerDuty, 보안 스캔, 비용... 각 서비스 페이지에 통합
```

## 3. Software Catalog — Entity 모델

```
Entity(개체): 카탈로그의 항목, kind로 분류

핵심 kind:
  Component  — 소프트웨어 단위 (서비스·라이브러리·웹사이트)
  API        — Component가 제공/소비하는 인터페이스 (OpenAPI·gRPC)
  System     — 여러 Component의 묶음 (도메인 경계, 24의 바운디드 컨텍스트)
  Domain     — 여러 System의 상위 묶음
  Resource   — 인프라 (DB·버킷, 41의 Managed Resource와 연결)
  Group/User — 조직 (팀·사람, 소유권)

관계 (edges):
  ownedBy    — Component → Group (누가 소유)
  partOf     — Component → System (어디 속함)
  providesApi/consumesApi — Component ↔ API (누가 제공·소비)
  dependsOn  — Component → Resource (무엇에 의존)

→ 그래프: "결제 서비스는 payments-team 소유, payment-system의 일부,
          PaymentAPI를 제공, orders-db(Resource)에 의존"
→ 24의 서비스 의존 그래프를 눈으로 (누가 무엇을 쓰는지)
```

## 4. catalog-info.yaml (Entity의 실체)

```yaml
# 각 레포 루트의 catalog-info.yaml → Backstage가 자동 수집
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: payment-service
  description: 결제 처리 서비스
  annotations:
    backstage.io/kubernetes-id: payment-service   # k8s 플러그인 연동
    github.com/project-slug: myorg/payment-service
spec:
  type: service
  lifecycle: production        # experimental/production/deprecated
  owner: payments-team         # → Group Entity (ownedBy)
  system: payment-system       # → System (partOf)
  providesApis: [payment-api]  # → API (providesApi)
  dependsOn: [resource:orders-db]  # → Resource (dependsOn)

★ 코드 옆에 사는 메타데이터 → PR로 리뷰·버전관리 → 낡지 않음
  (위키의 실패 = 별도 관리라 낡음, catalog-info.yaml = 코드와 함께)
```

## 5. Software Template — 황금 경로 (41과 연결)

```
템플릿 = 파라미터 + 스캐폴딩 단계 + 액션

template.yaml (개념):
  parameters:
    - name, owner, system 입력
  steps:
    - fetch: 스켈레톤 코드 가져오기
    - publish:github: 새 레포 생성·푸시
    - catalog:register: 카탈로그에 등록
    - (커스텀) crossplane claim 생성 → 41의 인프라

결과: "새 서비스 만들기" 클릭 →
  코드·CI·문서·카탈로그 등록·인프라가 한 번에 (황금 경로)
  → 개발자는 표준 구조로 시작 (일관성)
  → 47의 "인지 부하를 플랫폼이 흡수"
```

## 6. IDP로의 결합 (41·14·15·47)

```
내부 개발자 플랫폼(IDP)의 층:
  포털(UI):      Backstage(42) — 개발자 접점
  인프라 API:    Crossplane(41) — 셀프서비스 백엔드
  배포:          ArgoCD/Flux(14·15) — GitOps 조정
  런타임:        Kubernetes — 실행

전형 흐름:
  개발자가 Backstage에서 "새 서비스" 클릭
    → 템플릿이 레포·CI 생성 + Crossplane Claim(DB) + Argo App
    → GitOps가 배포, Crossplane이 인프라 조정
    → Backstage 카탈로그에 자동 등록·현황 표시
  → 개발자는 YAML·kubectl 없이 포털에서 (셀프서비스)

★ 42는 IDP의 "얼굴", 41은 "손", 14·15는 "조정" — 47이 이 전체를 제품으로
```

## 7. 판단 — 언제 Backstage인가, 도구 아닌 문화

```
언제 도입:
  규모(수십~수백 서비스)로 발견성·인지 부하가 실제 문제일 때
  플랫폼 팀이 있어 지속 운영·황금 경로를 관리할 수 있을 때

언제 과함:
  서비스 10개 미만 (README·슬랙으로 충분)
  운영할 플랫폼 팀이 없음 (깔고 방치 → 낡은 포털)

★ 도구가 아니라 문화:
  카탈로그 정확성 ← 팀들의 catalog-info.yaml 관리 참여
  템플릿 유용성 ← 플랫폼 팀의 좋은 황금 경로
  → "제품으로서의 플랫폼"(47) 없이 Backstage만 깔면 실패

관리형 대안:
  Backstage는 Node 앱, 운영·업그레이드·플러그인 유지가 상당
  → Roadie·Spotify Portal 등 관리형 (39·40의 "관리형 우선"과 같은 판단)
```

## 8. 소스/도구에서 확인하기

- Backstage: https://backstage.io/docs — catalog, templates(scaffolder), techdocs, plugins
- catalog-info.yaml 스펙: https://backstage.io/docs/features/software-catalog/descriptor-format
- 41(Crossplane)·14·15(GitOps)·47(플랫폼 엔지니어링)·24(마이크로서비스) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| 푸는 문제? | 규모의 발견성·인지 부하 (24의 규모, 통신 아닌 지식 흩어짐) |
| 세 기둥? | Catalog(목록)·Templates(황금경로 생성)·TechDocs(docs-as-code) |
| Entity kind? | Component·API·System·Domain·Resource·Group/User + 관계 |
| catalog-info.yaml? | 코드 옆 메타데이터 → 자동 수집 → 낡지 않음(14의 정신) |
| Template? | 새 서비스를 황금 경로로 스캐폴딩(레포·CI·카탈로그·인프라41) |
| IDP 결합? | Backstage(UI)+Crossplane(API)+GitOps(조정)+K8s(런타임) → 47 |
| 도구인가 문화인가요? | 문화 — 팀 참여·플랫폼 팀 없으면 낡은 포털로 실패 |
| 관리형? | 운영 부담 커 Roadie 등 관리형 고려(39·40의 관리형 우선) |
