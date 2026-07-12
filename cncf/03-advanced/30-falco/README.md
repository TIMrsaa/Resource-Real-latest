# 30 — Falco 심층: 런타임 위협을 시스템콜에서 잡습니다

> 07의 보안 시간선에서 "실행 중(런타임)" 축의 주인. admission(예방)이 못 막는 것 — 통과한 정상 이미지가 실행 중 침해되는 것 — 을 보는 유일한 층입니다(07 사고 사례). 이 모듈은 그 탐지가 어떻게 가능한지를 팝니다: Falco가 시스템콜을 어디서 어떻게 가로채는가(커널 모듈 → eBPF의 진화), 규칙 언어(무엇을 이상으로 볼지), 그리고 22의 Cilium/Tetragon과 무엇이 겹치고 다른지. 탐지는 예방이 아니라는 한계와, 경보를 대응으로 잇는 법까지 정직하게 다룹니다.

## 학습 목표

1. Falco의 아키텍처(드라이버=시스템콜 소스 + 룰 엔진 + 출력)와 eBPF/커널모듈 드라이버를 압니다
2. 시스템콜 기반 탐지의 원리와 한계(탐지지 예방 아님, 규칙 밖은 못 봄)를 압니다
3. 규칙 언어(condition/output/priority, 매크로·리스트)를 읽고 커스텀 규칙을 만듭니다
4. 경보를 대응으로 잇습니다(Falcosidekick → 알림·자동 격리)
5. Falco vs Tetragon(22) vs 강제(seccomp/AppArmor)의 자리를 구분합니다

## 선행: 07(보안 시간선 — 필수), 22(eBPF), 03(시스템콜·런타임), 26(containerd) · 도구: kind, kubectl, helm
## 비용: 없음 (kind — eBPF 드라이버 커널 지원 확인)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-detection-and-rules.md](./lab-01-detection-and-rules.md) — 탐지 재현, 규칙 읽기·작성
3. [lab-02-response-and-comparison.md](./lab-02-response-and-comparison.md) — 대응 연결, Tetragon·강제와 비교
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h

> ⚠️ 이 모듈은 방어 목적의 런타임 탐지 실습입니다. 탐지 규칙이 울리는지 확인하려면 탐지 대상 행위(컨테이너 내 셸 실행 등)를 재현하는데, 이는 Falco 공식 문서의 표준 데모와 동일하며 전부 격리된 실습 클러스터에서 수행합니다.
