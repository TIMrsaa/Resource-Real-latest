# 자가 점검 퀴즈

**Q1.** BuildKit의 파이프라인(frontend → LLB → solver → worker)에서 각 단계의 역할은? `# syntax=` 첫 줄은 무엇을 고정하나요?

**Q2.** 04의 규칙 "자주 바뀌는 것을 아래로"가 성립하는 원리를 LLB 캐시 키로 설명하세요. 파일을 touch만 하면(내용 동일) 캐시가 유지되는 이유는?

**Q3.** CI에서 `docker buildx create`(docker-container driver)가 사실상 필수인 이유 두 가지는?

**Q4.** 캐시 익스포트의 min과 max의 차이는? 멀티스테이지에서 min을 쓰면 어떤 증상이 나타나나요?

**Q5.** amd64 러너에서 arm64 이미지를 만드는 세 방법과 각각의 트레이드오프는? `FROM --platform=$BUILDPLATFORM`은 무엇을 하나요?

**Q6.** manifest list(OCI image index)의 구조와, eks 19의 `exec format error`가 발생하는 조건은? 멀티아치 이미지의 다이제스트 고정은 무엇의 digest로 해야 하나요?

**Q7.** ko와 buildpacks는 각각 어떤 상황의 답인가요? kaniko를 신규 도입하면 안 되는 이유는?

**Q8.** `--provenance --sbom`이 만드는 것은 무엇이고, 18의 verify-dist와 어떤 점에서 같은 질문인가요?

---

## 정답

**A1.** frontend는 Dockerfile을 LLB로 컴파일(번역기 — 이미지로 배포됨), LLB는 콘텐츠 주소 기반 빌드 DAG, solver는 정점별 캐시 판정과 병렬 실행 계획(공장장), worker가 실제 실행(containerd/OCI). `# syntax=docker/dockerfile:1.7`은 frontend 버전을 고정합니다 — 데몬 버전과 무관하게 같은 Dockerfile 문법이 같은 LLB로 컴파일되게.

**A2.** 정점의 캐시 키 = 연산 정의 + 모든 입력의 digest. RUN의 입력에는 부모 정점 digest가 포함되므로, 위쪽(부모)이 바뀌면 아래가 연쇄 미스 — 그래서 자주 바뀌는 것을 아래로 둬야 연쇄가 짧습니다. COPY의 입력 digest는 파일 **내용**의 해시라서 mtime 변경(touch)은 키를 안 바꿉니다 — 내용 기반 캐시.

**A3.** ① 멀티 플랫폼 빌드(`--platform` 다중 지정)가 기본 docker driver에서는 불가. ② 캐시 익스포트(registry/gha 등)가 기본 driver에서는 inline 외 불가. buildkitd를 컨테이너로 분리(docker-container driver)해야 둘 다 열립니다.

**A4.** min은 최종 스테이지의 레이어만, max는 중간 스테이지 전부를 익스포트. 멀티스테이지에서 min이면 빌드 스테이지(보통 제일 비싼 부분)의 캐시가 익스포트에 빠져, "캐시를 붙였는데 CI가 매번 풀빌드"가 됩니다 — 최종 스테이지의 COPY --from만 히트하고 그 위 스테이지는 전부 재실행.

**A5.** ① QEMU 에뮬레이션: 설정 최소, CPU 집약 작업 5~20배 느림(최후 수단). ② 크로스 컴파일: 네이티브 속도, 언어가 지원해야(Go/Rust 우수). ③ 네이티브 러너(GHA ubuntu-24.04-arm, ARC+Graviton): 네이티브 속도, 러너 준비 필요. `FROM --platform=$BUILDPLATFORM`은 그 스테이지를 타깃 아치가 아니라 **빌드 머신 아치**로 실행하게 합니다 — 컴파일은 네이티브로 돌리고 GOARCH 등으로 산출물만 타깃 아치로 내는 크로스 컴파일 패턴의 핵심.

**A6.** 태그가 image index를 가리키고, index가 아치별 manifest(각각 config+layers) 목록을 담습니다. 노드의 containerd가 자기 플랫폼에 맞는 manifest를 골라 pull합니다. `exec format error`는 index에 노드 아치의 manifest가 없거나(단일 아치 이미지) index 자체가 없을 때. 다이제스트 고정은 **index의 digest**로 — 아치별 manifest digest로 고정하면 그 아치 하나만 고정되고 다른 아치 노드는 실패합니다.

**A7.** ko: Go 서비스 — Dockerfile도 데몬도 없이 소스에서 멀티아치 이미지·push까지(재현성 높음, Tekton/Knative의 빌드 방식). buildpacks: 조직 표준화 — 소스 자동 감지 빌드 + rebase(앱 레이어 재빌드 없이 베이스만 교체 — 전사 일괄 OS 패치). kaniko: 2025년 저장소 아카이브(유지보수·CVE 대응 종료) — 신규 채택 금지, BuildKit rootless나 원격 buildkitd가 대체 경로. CI 도구도 공급망이므로 유지보수 상태가 도입 기준입니다.

**A8.** image index에 이미지와 나란히 attestation manifest를 첨부합니다 — provenance(어떤 소스·빌더·파라미터로 만들어졌나, SLSA)와 SBOM(무엇이 들어있나). 18의 verify-dist가 "커밋된 dist가 정말 이 src에서 나온 것"을 증명했듯, provenance는 "이 이미지가 정말 이 소스·이 빌드에서 나온 것"을 증명합니다 — 산출물과 소스의 일치를 보증하는 공급망 책임의 이미지판이며, 검증(소비자 관점)은 21에서 다룹니다.
