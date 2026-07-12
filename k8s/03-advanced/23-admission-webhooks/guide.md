# 학습 가이드 — "관문에 끼어드는" 두 가지 방법

## 왜 admission 확장이 큰 주제인가

RBAC는 "누가 무엇을"까지만 봅니다. "컨테이너는 root 금지", "이미지는 사내 레지스트리만", "비용 라벨 필수" 같은 **내용 기반 규칙**은 admission의 영역입니다. 이 확장점 위에 생태계가 서 있습니다:

- Kyverno, OPA Gatekeeper (정책 엔진) = validating 웹훅의 제품화
- Istio/linkerd의 사이드카 자동 주입 = mutating 웹훅
- cert-manager의 인증서 주입, Vault agent injector... 전부 웹훅입니다

## 2026년의 선택 기준: CEL 먼저, 웹훅은 나중

| | ValidatingAdmissionPolicy (CEL) | 웹훅 |
|---|---|---|
| 실행 위치 | **API 서버 안에서** 식 평가 | 외부 HTTPS 서버 호출 |
| 지연/장애 | 거의 0 / 장애 지점 없음 | 네트워크 왕복 / **웹훅 다운 = 관문 마비 위험** |
| 표현력 | CEL 식으로 가능한 검증 | 무엇이든 (외부 조회, 복잡 로직) |
| 변형(mutate) | MutatingAdmissionPolicy(알파~베타 진행 중) | Mutating 웹훅 (성숙) |

규칙: **CEL로 되면 CEL로** (검증의 80%는 됩니다). 웹훅은 외부 데이터가 필요하거나 변형이 필요할 때만. lab도 이 순서입니다.

## 미리 겁주기: 웹훅은 클러스터의 SPOF가 될 수 있습니다

`failurePolicy: Fail` + 웹훅 서버 다운 = **해당 리소스 생성 전부 거부.** 그 웹훅이 모든 Pod를 보고 있었다면? 노드 장애 복구도, 스케일링도 멈춥니다. 모듈 06 pitfall(전사 라우팅 마비)의 admission판 — lab-02에서 직접 일으켜보고 방어 설계를 배웁니다.
