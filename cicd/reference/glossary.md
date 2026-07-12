# CI/CD 용어집

> 괄호는 그 개념을 다루는 모듈. 정의는 이 커리큘럼의 맥락으로 — 일반 사전이 아니라 "우리가 배운 그 의미"다.

## 개념·지표

- **CI (Continuous Integration)** — 변경을 작게·자주 통합하고 자동 검증하는 실천. 도구가 아니라 규율 (01)
- **Continuous Delivery vs Deployment** — 항상 배포 가능한 상태 유지 vs 통과 시 자동 배포까지 (01)
- **DORA 4지표** — 배포 빈도·변경 리드타임·변경 실패율·MTTR. 세트로 봐야 게이밍 방지 (01·23)
- **merge hell** — 통합 지연이 낳는 충돌 폭발. 배치가 클수록 위험은 제곱으로 (01)
- **lead time** — 커밋 → prod 도달 시간. 대개 병목은 파이프라인 밖(리뷰 대기) (23)
- **critical path** — 병렬 잡 그래프의 최장 경로. 경로 밖 최적화는 0초 단축 (23)
- **queue time** — 잡이 러너를 기다린 시간. 러너 부족의 선행 지표 (L=λW — 23, eks 13)
- **flaky test** — 같은 코드에 결과가 갈리는 테스트. 재시도로 숨기지 말고 격리 (05·23)
- **굿하트의 법칙** — 지표가 목표가 되면 좋은 지표이기를 멈춥니다 (23)

## GitHub Actions (03~08)

- **워크플로/잡/스텝** — 실행 모델의 계층. 잡마다 새 러너(격리 경계), 스텝은 같은 러너 공유 (03)
- **pull_request_target** — base 저장소 권한으로 도는 PR 이벤트 — checkout과 조합 시 인젝션 (03·24)
- **GITHUB_TOKEN** — 잡 수명의 자동 토큰. permissions로 최소화 (03)
- **reusable workflow / composite action** — 재사용 단위 (조직 표준 = 골든 패스의 재료) (06·24)
- **environment** — 배포 대상 추상화 + 승인·브랜치 제한·시크릿 스코프 (06·24)
- **OIDC (workload identity)** — "비밀번호 대신 신원 증명". sub 클레임 조건이 핵심 설계 (07)
- **ARC (actions-runner-controller)** — K8s 위 셀프호스티드 러너 오퍼레이터. ephemeral이 원칙 (08)
- **_diag** — 러너 내부 로그 (Listener/Worker의 일기) — 러너 이슈 리포트의 필수 재료 (26)

## 빌드·이미지 (04·19)

- **레이어 캐시** — 캐시 키 = 연산 + 입력 digest. "자주 바뀌는 것을 아래로"의 원리 (04·19)
- **멀티스테이지 빌드** — 빌드 도구와 실행물의 분리. 최종 이미지 최소화 (04)
- **다이제스트(@sha256)** — 내용 주소 참조. 태그는 움직이고 다이제스트는 불변 (04)
- **BuildKit / LLB / frontend / solver** — 빌드 엔진의 내부: 번역(LLB)·캐시 판정·병렬 실행 (19)
- **캐시 익스포트 min/max** — max만 중간 스테이지 포함. 멀티스테이지 + min = "캐시가 안 먹어요" (19)
- **manifest list (image index)** — 태그 하나가 아치별 manifest 목록을 가리킴 — 멀티아치의 실체 (19)
- **QEMU 에뮬레이션 / 크로스 컴파일 / 네이티브 러너** — 멀티아치 3법 (느림/언어 의존/러너 준비) (19)
- **ko** — Go 소스→이미지 직행 (Dockerfile·데몬 없음). Tekton의 개발 루프 (19·28)
- **buildpacks (CNB)** — 소스 감지 빌드 + rebase(베이스만 교체 — 전사 일괄 패치) (19)

## GitOps·배포 (11·14·15·17)

- **GitOps** — Git이 진실, 컨트롤러가 pull·수렴. push 배포의 역전 (14)
- **refresh vs sync** — 비교(diff 계산)와 적용(클러스터 변경)의 구분 (14)
- **selfHeal / prune** — 드리프트 자동 복원 / Git에서 사라진 리소스 삭제 — 둘 다 양날 (14)
- **sync wave / hook** — sync 내 순서 제어 (마이그레이션 → 앱) (14·11)
- **ApplicationSet** — 앱을 생성하는 생성기 (멀티클러스터·모노레포 디렉터리 = 앱) (14·20)
- **gitops-engine** — diff·sync·health의 별도 저장소 — 기여 시 경계 판정 대상 (27)
- **Progressive Delivery** — 배포를 관찰과 결합해 점진 확대 — 카나리·자동 롤백 (17)
- **AnalysisTemplate** — "관찰이 게이트": 메트릭 기준 미달 시 자동 롤백 (17)
- **expand-contract** — 스키마를 넓히고(호환) → 전환 → 좁히는 무중단 마이그레이션 (11)

## 공급망·시크릿 (21·22)

- **SLSA** — 빌드 신뢰 등급 (L1 provenance 존재 ~ L3 빌드 격리) (21)
- **provenance** — "어떻게 만들어졌나"의 증명서. 19의 --provenance가 재료 (19·21)
- **SBOM** — 성분표. 진짜 가치는 신규 CVE의 소급 조회 (21)
- **cosign keyless** — OIDC 신원 → Fulcio 단명 인증서 → Rekor 공개 로그. 유출될 장기 키가 없음 (21)
- **Rekor** — append-only 투명성 로그 — 서명의 존재·시점을 사후 증명 (21)
- **admission 검증** — 서명·신원 없는 이미지의 클러스터 진입 거절 — 최후 방어선 (21, k8s 34)
- **dependency confusion** — 사내 패키지명을 공개 레지스트리에 — 해석 우선순위 공격 (21)
- **sealed-secrets / SOPS / ESO** — GitOps 시크릿 3해법: 클러스터 키 암호문 / KMS 암호문+diff / 스토어 포인터 (22)
- **동적 시크릿** — TTL 자격증명 발급 (Vault). "유출돼도 이미 만료" (22)
- **break-glass** — 긴급 우회 경로. 금지 대신 고비용·고가시성으로 설계 (24)

## 모노레포·거버넌스 (20·24)

- **affected** — 변경 프로젝트 + 역방향 전이 의존자. 모노레포 CI의 본질 질문 (20)
- **path filter의 맹점** — 의존성 무지. 필터 목록 = 그래프의 낡는 사본 (20)
- **hermetic build** — 선언된 입력만 접근 가능한 빌드 (Bazel의 강제) — 캐시 신뢰의 근거 (20)
- **golden path (포장도로)** — 표준을 강제 대신 "제일 편한 길"로 — 보안이 내장되어 공짜 (24)
- **SoD (직무 분리)** — 작성자 ≠ 승인자. prevent_self_review + CODEOWNERS (24)
- **CAB** — 변경자문위원회. DORA: 속도만 죽이고 안정성 못 올림 (24)
- **Policy as Code** — 정책을 게이트로 (conftest/OPA — 파이프라인 정의 자체를 검사) (24)

## 기여 (26~28)

- **OWNERS / Prow / lgtm·approve** — k8s식 리뷰 권한·봇 프로세스 (tektoncd가 이식) (28, k8s 43)
- **TEP / proposal / ADR** — 설계 합의 형식 (tekton / argo / actions) — 코드보다 합의 먼저 (26~28)
- **good first issue** — 유지보수자가 표시한 진입 이슈 — 온도 측정의 지표이기도 (26~28)
- **재현 테스트 우선** — 버그 수정 PR = 빨강 테스트 → 수정 → 초록 (27, k8s 44)
- **개발 루프** — 수정→실행→확인의 최소 사이클. 프로젝트 착수 시 첫 확보 대상 (26~28)
