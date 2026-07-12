# 02 — 지도: 스케줄링 & 오케스트레이션 — K8s가 이긴 동네와 그 주변부

> 첫 지도 모듈. "오케스트레이션은 K8s가 이겼다"는 문장은 절반만 맞습니다 — 표준 전쟁의 승자는 정해졌지만, 그 주변에 **K8s가 못 푸는 문제를 푸는 프로젝트들**(배치·갱 스케줄링, 멀티클러스터, 엣지, 워크로드 확장)이 자라고 있고, K8s 밖의 대안(Nomad)도 특정 조건에서 여전히 선택됩니다. 이 모듈은 그 지형 전체를 한 장에 그리고, "왜 기본 스케줄러로 부족한가"를 갱 스케줄링 실습으로 몸에 새깁니다.

## 학습 목표

1. 오케스트레이션 전쟁의 역사(Mesos·Swarm·K8s)와 승부를 가른 구조적 이유를 압니다
2. 카테고리 전수 지도를 그립니다 — 배치(Volcano·Kueue), 멀티클러스터(Karmada·OCM), 엣지(KubeEdge), 워크로드 확장(OpenKruise), 대안(Nomad)
3. 기본 스케줄러의 한계(Pod 단위 결정)와 갱 스케줄링이 필요한 이유(all-or-nothing)를 실습으로 확인합니다
4. 멀티클러스터의 두 접근(중앙 배분 vs 클러스터 API 연합)을 구분합니다
5. "K8s 밖 대안"의 자리와 라이선스 리스크(Nomad BSL — 01의 재단 논리)를 판단합니다

## 선행: 01(지도 범례), k8s 전 파트(특히 스케줄러·kubelet), eks 17(Karpenter) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — landscape 데이터로 전수 목록·분류
3. [lab-02-gang-scheduling.md](./lab-02-gang-scheduling.md) — 기본 스케줄러의 한계와 배치 스케줄러 시식
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
