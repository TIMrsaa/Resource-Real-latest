# 35 — Dragonfly 심층: P2P 이미지 배포로 스케일의 벽을 넘습니다

> 루트 버전표의 "최신 Graduated(2026-01)". 34(Harbor)가 레지스트리를 보안 관문으로 만들었다면, Dragonfly는 정반대의 문제를 풉니다 — **대규모 이미지 배포의 스케일**. 수천 노드가 동시에 같은 이미지를 pull하면 레지스트리가 병목이 되고 네트워크가 포화됩니다(대규모 배포·AI 워크로드의 실제 고통). Dragonfly의 답은 P2P입니다: 노드들이 서로에게서 이미지 조각을 받아, 레지스트리 부하를 분산합니다. 이 모듈은 그 P2P 배포 원리, 이미지 pull이 대규모에서 왜 병목인지, 그리고 이것이 26(containerd)·18(콜드스타트)·AI 워크로드와 어떻게 연결되는지를 팝니다.

## 학습 목표

1. 대규모 이미지 배포의 병목(레지스트리 대역·동시 pull·네트워크 포화)을 이해합니다
2. Dragonfly의 P2P 아키텍처(scheduler·seed peer·peer)와 조각 공유 원리를 압니다
3. 이미지 pull 경로에 Dragonfly가 끼어드는 방식(registry mirror·P2P)을 압니다
4. 지연 로딩(26의 stargz)과 P2P의 관계, AI 워크로드(대형 이미지)에서의 가치를 압니다
5. "언제 P2P 배포가 필요한가"(규모의 임계) 판단을 압니다

## 선행: 34(레지스트리), 26(containerd 이미지), 18(콜드스타트), 04(이미지) · 도구: kind, kubectl, helm (개념 중심)
## 비용: 없음 (kind — P2P는 규모가 본질이라 개념 중심)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-pull-bottleneck-and-p2p.md](./lab-01-pull-bottleneck-and-p2p.md) — 병목 이해, P2P 구조
3. [lab-02-integration-and-judgment.md](./lab-02-integration-and-judgment.md) — 통합·지연로딩·판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
