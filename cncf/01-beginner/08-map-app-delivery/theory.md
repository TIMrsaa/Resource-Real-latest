# 이론 — 추상 사다리 5단, Helm vs Kustomize, 오퍼레이터 관통, 5단의 네 주민

> **🌱 17세 눈높이 비유: 집을 짓고 사람이 살게 하기**
> - **1단 매니페스트** = 벽돌 하나하나의 설계도 (Deployment YAML)
> - **2단 패키징** = 조립식 주택 키트 — **Helm**은 "옵션을 골라 주문하는 카탈로그"(템플릿+변수), **Kustomize**는 "기본 설계도에 수정 스티커를 덧붙이기"(오버레이)
> - **3단 배달** = 시공사 — 설계도(Git)를 보고 실제로 짓고, 어긋나면 다시 맞춥니다 (ArgoCD/Flux)
> - **4단 점진 전환** = 이사를 한 번에 안 하고 방부터 옮기기 — 문제 생기면 되돌립니다 (Rollouts/Flagger)
> - **5단 상위 추상** = "집"을 몰라도 살게 해주는 서비스들 — 호텔(Knative: 안 쓰면 방을 없앰), 룸서비스(Dapr: 앱이 필요한 것을 옆방에서), 부동산 대행(Crossplane: 땅·전기를 대신 계약), 안내 데스크(Backstage: 어디에 뭐가 있는지)
> - **오퍼레이터** = 상주 관리인 — 도메인 지식("DB는 이렇게 백업한다")을 코드로 담아 계속 돌봅니다

---

## 1. 추상 사다리 — 이 지도의 좌표축

| 단 | 질문 | 대표 | 커리큘럼 |
|---|---|---|---|
| 1 매니페스트 | 무엇을 원하는가(선언) | Deployment/Service YAML | k8s 초급 |
| 2 패키징 | 어떻게 재사용·환경별 변형? | **Helm**, **Kustomize** | k8s 중급 |
| 3 배달 | 누가 클러스터에 반영·수렴? | **ArgoCD**, **Flux** | cicd 14·15 |
| 4 점진 전환 | 어떻게 안전하게 바꾸나요? | **Argo Rollouts**, **Flagger** | cicd 17 |
| 5 상위 추상 | k8s를 덜 알고도 되게? | Knative, Dapr, Crossplane, Backstage, KubeVirt | 이 모듈이 소개 |

판정 규칙: **같은 단끼리만 비교가 성립합니다.** "Helm vs ArgoCD"는 2단 vs 3단(함께 씁니다 — ArgoCD가 Helm 차트를 렌더링해 배달), "Crossplane vs Helm"은 5단 vs 2단(대상 자체가 다릅니다).

## 2. 2단 해부 — Helm과 Kustomize의 철학

| | Helm | Kustomize |
|---|---|---|
| 방식 | **템플릿 + values** (Go template) | **베이스 + 오버레이 패치** (템플릿 없음) |
| 산출 | 렌더링된 매니페스트 | 병합된 매니페스트 |
| 배포 단위 | Release (설치 상태를 추적) | 없음 (kubectl apply -k) |
| 강점 | 배포·공유·버저닝(차트 저장소), 복잡한 조건 | YAML이 끝까지 YAML(문법 오염 없음), 순수 병합 |
| 약점 | 템플릿이 YAML을 문자열로 다룸(들여쓰기 지옥) | 복잡한 조건·루프 표현 불가 |
| 자리 | **배포되는 소프트웨어**(제3자에게 나눠줄 것) | **내 조직의 환경별 변형** |

실무 조합: 외부 컴포넌트는 Helm 차트로 설치, 우리 앱은 Kustomize 오버레이 — 그리고 ArgoCD/Flux가 둘 다 렌더링해 배달합니다(3단이 2단을 소비). Helm은 v4 시대(루트 버전표) — v3의 릴리스 저장 방식·훅 개념은 유지되며 심층 15에서.

**렌더링은 언제 일어나는가**가 GitOps의 오랜 논쟁입니다:

```
CI에서 렌더링 → 완성된 YAML을 Git에 (rendered manifests 패턴) — diff가 정직, 감사 쉬움
CD에서 렌더링 → 차트/오버레이를 Git에 (ArgoCD가 렌더) — 저장소 단순, 그러나 "Git의 것"과 "적용될 것"이 다름
```

cicd 14에서 본 "Git이 진실"의 정밀도 문제 — 무엇을 진실로 둘지의 선택입니다.

## 3. 오퍼레이터 — 사다리를 관통하는 확장 문법

```
CRD(새 리소스 타입) + 컨트롤러(reconcile 루프) = 오퍼레이터
  = "운영 지식의 코드화" — 백업·페일오버·업그레이드를 사람이 아니라 컨트롤러가

이 커리큘럼에서 만난 오퍼레이터들:
  Rook(05, Ceph 운영) · cert-manager(07, 인증서) · ArgoCD(cicd 14, 앱 배달)
  Karpenter(eks 17, 노드) · Strimzi(09 지도, Kafka) · Crossplane(§4, 클라우드 리소스)
```

| 도구 | 무엇 | 성숙도 |
|---|---|---|
| **Operator Framework / SDK** | 오퍼레이터 작성·패키징·수명주기(OLM) | Incubating |
| Kubebuilder | (k8s-sigs) 컨트롤러 스캐폴딩 — k8s 파트의 그것 | k8s-sigs |
| Metacontroller 등 | 경량 오퍼레이터 작성 | Sandbox~ |

오퍼레이터 성숙도 모델(Level 1~5: 설치 → 업그레이드 → 백업 → 인사이트 → 자동 파일럿)은 "이 오퍼레이터를 프로덕션에 믿고 맡길 수 있나"의 채점표입니다 — 05의 Rook 평가에 그대로 적용됩니다.

## 4. 5단의 네 주민 — "무엇 위의 추상인가"

| 프로젝트 | 성숙도 | 무엇 위의 추상 | 핵심 능력 | 대가 |
|---|---|---|---|---|
| **Knative** | Incubating | 워크로드(서빙·이벤트) | **스케일 투 제로**, 리비전·트래픽 분할, 이벤트 소싱 | 콜드스타트, 추상 누수 |
| **Dapr** | Graduated | 앱 코드(런타임) | 사이드카 API로 상태·pub/sub·시크릿·서비스호출 — 언어 중립 | 사이드카 비용, 또 하나의 API |
| **Crossplane** | Graduated | 클라우드 인프라 | RDS·S3·VPC를 K8s 리소스로 — 오퍼레이터의 극단 | 상태 관리의 무게(Terraform과의 비교) |
| **Backstage** | Incubating | 조직·개발자 경험 | 서비스 카탈로그·스캐폴딩 템플릿·기술 문서 포털 | 플랫폼 팀의 운영 부담 |
| KubeVirt | Incubating | VM | 가상머신을 Pod처럼 (레거시 공존) | 가상화 인프라 요구 |
| Keptn / Argo Workflows 등 | 각기 | 배포 수명주기·워크플로 | — | — |

47(플랫폼 엔지니어링)의 부품 목록이 이 표입니다: Backstage(입구) + Crossplane(인프라 프로비저닝) + ArgoCD(배달) 조합이 오늘날 IDP의 전형.

## 5. 추상 누수 — 5단의 공통 위험

```
"K8s를 몰라도 됩니다" (5단의 약속)
  → 잘 될 때는 사실입니다
  → 안 될 때: Knative 서비스가 안 뜨는데 원인은 Pod의 이미지 pull 에러(1단)
             Crossplane의 Composition이 안 도는데 원인은 IAM 권한(클라우드)
             Dapr 사이드카가 주입 안 되는데 원인은 admission webhook(k8s)
  → 결국 아래 단을 알아야 디버깅됩니다 — 그리고 그때는 '추상 + 원본' 둘 다 알아야 합니다
```

이것이 이 커리큘럼이 k8s(Part 1)를 먼저 45개 모듈로 다룬 이유입니다. 5단은 아래를 대체하지 않고 **덮습니다** — 덮인 것을 아는 사람만 5단을 안전하게 씁니다.

## 6. 소스/도구에서 확인하기

- Helm: https://helm.sh/docs (v4) / Kustomize: https://kubectl.docs.kubernetes.io/references/kustomize/
- Operator Framework: https://operatorframework.io — capability levels
- Knative: https://knative.dev / Dapr: https://dapr.io
- Crossplane: https://crossplane.io / Backstage: https://backstage.io
- 성숙도 재확인: lab-01 (landscape.yml)

## 요약 카드

| 질문 | 답 |
|------|----|
| 지도의 축? | 추상 사다리 5단 — 매니페스트/패키징/배달/점진전환/상위추상 |
| 비교 규칙? | 같은 단끼리만 — "Helm vs ArgoCD"는 2단 vs 3단(함께 씀) |
| Helm vs Kustomize? | 템플릿+values(배포용 소프트웨어) vs 오버레이 패치(우리 환경 변형) — 공존이 표준 |
| 렌더링 시점 논쟁? | CI에서 렌더(정직한 diff) vs CD에서 렌더(단순한 저장소) — "Git의 진실" 정밀도 |
| 오퍼레이터? | CRD+컨트롤러 = 운영 지식의 코드화 — 사다리를 관통하는 확장 문법 |
| 5단 구분? | 무엇 위의 추상인가 — 워크로드(Knative)/코드(Dapr)/인프라(Crossplane)/조직(Backstage) |
| 5단의 위험? | 추상 누수 — 덮인 아래 단을 아는 사람만 안전하게 씁니다 |
