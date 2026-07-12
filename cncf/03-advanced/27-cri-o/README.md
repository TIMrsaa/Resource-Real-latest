# 27 — CRI-O 심층: K8s만을 위한 런타임

> 03의 런타임 지도에서 containerd(26)의 반대편. CRI-O는 같은 자리(CRI 레벨)를 정반대 철학으로 채웁니다 — "쿠버네티스가 필요한 것만, 그 이상은 안 합니다." containerd가 범용 컨테이너 데몬(Docker·nerdctl·다양한 워크로드)이라면 CRI-O는 **CRI 명세만 구현하고 K8s 릴리스에 보조를 맞추는** 미니멀리스트입니다. OpenShift의 기본이고, 이 모듈은 그 설계 철학(왜 덜 하나)과 구조(라이브러리 조합), 그리고 containerd와 나란히 놓았을 때의 선택 기준을 팝니다. 26과 함께 읽으면 25(Linkerd)에서 배운 "단순함도 설계"가 런타임 층에서 반복됩니다.

## 학습 목표

1. CRI-O의 아키텍처(CRI만 구현 + 라이브러리 조합)와 containerd와의 구조적 차이를 압니다
2. "K8s 버전과 함께 가는" 버저닝 정책과 그것이 주는 이점·제약을 압니다
3. 이미지·저장(containers/storage, containers/image 라이브러리 공유 생태계)을 이해합니다
4. crun(기본 OCI 런타임)과 성능·경량 특성을 압니다
5. containerd vs CRI-O 선택 기준과 "대부분 플랫폼이 정해준다"의 의미를 압니다

## 선행: 26(containerd — 대비), 03(런타임 지도), 25(단순함도 설계) · 도구: kind, podman/crictl (개념 중심)
## 비용: 없음 (개념 + kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-crio-architecture.md](./lab-01-crio-architecture.md) — CRI-O 구조, containers 생태계
3. [lab-02-comparison-and-choice.md](./lab-02-comparison-and-choice.md) — containerd와 직접 대비, 선택
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
