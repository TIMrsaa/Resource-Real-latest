# 02 — 로깅의 원리: stdout에서 파일까지, 그리고 구조화

> 01에서 로그의 원산지(`/var/log/pods/`)를 봤습니다. 이 모듈은 그 경로를 끝까지 팝니다 — **왜 컨테이너는 파일이 아니라 stdout에 로그를 쓰는가**(12-factor), containerd가 스트림을 파일로 만드는 형식(CRI 로그 포맷), kubelet의 로그 로테이션(무한히 쌓이지 않는 이유), `kubectl logs`의 옵션들(--previous가 살리는 죽은 컨테이너의 유언), 사이드카·볼륨 로그 같은 예외 패턴, 그리고 **구조화 로깅(JSON)** — 로그를 "사람이 읽는 문장"에서 "기계가 질의하는 데이터"로 바꾸는 실무의 분기점. 이 기초가 튼튼해야 06(Fluent Bit)의 파서·필터가 당연해집니다.

## 학습 목표

1. 컨테이너 로깅 표준(stdout/stderr)의 이유(12-factor·불변성)를 설명할 수 있습니다
2. CRI 로그 파일 형식과 kubelet 로테이션(containerLogMaxSize/Files)을 압니다
3. `kubectl logs`의 주요 옵션(-f·--previous·--since·-l·--prefix)을 실전에서 씁니다
4. stdout이 안 되는 경우의 패턴(사이드카 스트리밍)과 트레이드오프를 압니다
5. 구조화 로깅(JSON)의 가치와 설계 원칙(필드 규약·레벨·컨텍스트 필드)을 압니다

## 선행: 01(원산지 투어 — 필수), k8s 파트 초급 · 도구: kind, kubectl
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-log-path-deep-dive.md](./lab-01-log-path-deep-dive.md) — CRI 포맷·로테이션·kubectl logs 옵션 실전
3. [lab-02-structured-logging.md](./lab-02-structured-logging.md) — 비구조화 vs JSON 로그의 조사력 차이 체감
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
