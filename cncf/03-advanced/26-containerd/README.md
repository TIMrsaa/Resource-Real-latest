# 26 — containerd 심층: kubelet 아래, runc 위

> 03의 런타임 지도에서 CRI 레벨의 사실상 기본값. EKS·GKE·kind가 모두 이것을 쓰고, Docker 내부에서도 이것이 일합니다. 03에서 "체인의 한 고리"로 봤다면, 이 모듈은 그 고리를 열어봅니다: containerd의 아키텍처(코어 + 플러그인 + shim), CRI 구현이 kubelet의 요청을 어떻게 처리하는지, 이미지 관리(스냅샷터·콘텐츠 저장)의 실제, 그리고 왜 containerd가 "runwasi로 Wasm을, nerdctl로 Docker 호환을" 담는 확장 플랫폼이 됐는지. 03의 lab에서 프로세스 트리로 봤던 것을 이제 구조로 이해합니다.

## 학습 목표

1. containerd 아키텍처(daemon + 플러그인 + shim v2)와 클라이언트(kubelet/ctr/nerdctl)를 압니다
2. CRI 플러그인이 RunPodSandbox→CreateContainer→StartContainer를 처리하는 흐름을 압니다
3. 스냅샷터(overlayfs 등)와 콘텐츠 저장소로 이미지 레이어가 어떻게 관리되는지 이해합니다
4. shim v2가 왜 존재하는지(containerd 재시작에도 컨테이너 생존)를 실물로 확인합니다
5. 확장(runwasi로 Wasm, 대체 스냅샷터, nerdctl)과 진단(ctr·crictl)을 다룹니다

## 선행: 03(런타임 지도 — 필수), eks 19(런타임·아치), 20(노드 진단) · 도구: kind, docker, ctr, crictl
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-architecture-and-cri.md](./lab-01-architecture-and-cri.md) — 플러그인·CRI 흐름·shim 관찰
3. [lab-02-images-snapshots-extensions.md](./lab-02-images-snapshots-extensions.md) — 스냅샷터·콘텐츠·확장
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
