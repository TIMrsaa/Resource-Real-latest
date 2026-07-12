# 19 — BuildKit 심층: 빌드를 내부까지, 그리고 Dockerfile 너머

> 04에서 `docker build`를 규율 있게 쓰는 법(레이어 캐시, 멀티스테이지, 다이제스트)을 배웠습니다. 이 모듈은 그 명령 **안쪽**으로 들어갑니다 — BuildKit이 Dockerfile을 LLB(빌드 그래프)로 번역하고, 솔버가 캐시를 판정하며, 병렬로 실행하는 내부를 봅니다. 그리고 Dockerfile이 유일한 길이 아님을 배웁니다: ko(Go), buildpacks(CNB), kaniko(아카이브됨)의 자리와, 멀티아치 빌드(eks 19의 Graviton이 소비자라면 이 모듈은 생산자)까지.

## 학습 목표

1. BuildKit 아키텍처(frontend → LLB → solver → worker)와 레거시 빌더 대비 무엇이 달라졌는지 설명합니다
2. 캐시의 실체(콘텐츠 주소 기반 키, min/max 모드, inline/registry/gha 익스포트)를 실험으로 확인합니다
3. 멀티아치 이미지를 세 가지 방법(QEMU 에뮬레이션, 크로스 컴파일, 네이티브 러너)으로 만들고 트레이드오프를 압니다
4. manifest list(OCI image index)가 어떻게 "노드가 자기 아치를 자동으로 받는지"를 해부합니다
5. Dockerfile 없는 빌드 도구(ko, buildpacks)와 데몬 없는 빌드(rootless)의 자리를 압니다

## 선행: 04(빌드·캐시·멀티스테이지), 08(러너 위 빌드), eks 19(arm64 소비) · 도구: docker(buildx), gh
## 비용: 없음 (로컬 docker + GitHub Actions 무료 티어)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-buildkit-internals.md](./lab-01-buildkit-internals.md) — LLB·병렬 DAG·캐시 익스포트 관찰
3. [lab-02-multiarch-and-tools.md](./lab-02-multiarch-and-tools.md) — 멀티아치 3종 + ko/buildpacks 체험
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
