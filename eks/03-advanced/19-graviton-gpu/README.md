# 19 — 이기종 컴퓨팅: Graviton(arm64)과 GPU/Neuron

> 지금까지의 노드는 전부 "같은 언어(amd64)"를 썼습니다. 이 모듈은 두 방향의 이탈을 다룹니다 — **더 싸게**(Graviton/arm64: 같은 일을 20~40% 싸게, 단 이미지가 그 언어로 번역돼 있어야) 그리고 **더 특별하게**(GPU/Neuron: 스케줄러에게 "장비"를 자원으로 가르치는 법). 둘 다 본질은 같습니다: 이기종 노드를 스케줄링 어휘(label·taint·extended resource)로 길들이기.

## 학습 목표

1. arm64 전환의 경제성과 전제 조건(multi-arch 이미지)을 이해합니다
2. `exec format error`를 직접 재현하고 — 아키텍처 불일치의 증상을 몸에 새깁니다
3. multi-arch manifest의 구조를 검사하고, 혼합 클러스터의 스케줄링 규칙을 세웁니다
4. GPU 노드를 만들고 device plugin이 **장비를 리소스로 등록**하는 순간을 관찰합니다
5. GPU 공유(time-slicing vs MIG)와 Neuron(inf/trn)의 자리, Karpenter(17)와의 결합을 압니다

## 선행: eks 05(노드그룹/AMI), 13(측정 — 전환 검증), 17(Karpenter arch requirements) · 환경: 공유 EKS
## ⚠️ 비용: t4g(저렴)로 대부분 진행. lab-02의 GPU 노드는 **선택 실습**(시간당 $1+) — 최단 시간, 즉시 삭제

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-graviton.md](./lab-01-graviton.md) — arm 노드, exec format error, multi-arch 검사
3. [lab-02-gpu.md](./lab-02-gpu.md) — GPU 노드와 device plugin (선택), Neuron 지도
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ 노드그룹 삭제 확인)

소요: 이론 1.5h + 실습 2h (+GPU 선택 0.5h)
