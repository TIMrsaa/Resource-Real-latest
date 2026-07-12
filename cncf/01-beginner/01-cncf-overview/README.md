# 01 — CNCF란 무엇인가: 재단, 성숙도 사다리, 그리고 지도를 읽는 법

> 지금까지 쓴 도구들의 상당수 — Kubernetes(k8s), Helm, Prometheus, ArgoCD(cicd 14·27), containerd, Envoy — 는 한 재단의 지붕 아래 있습니다: **CNCF(Cloud Native Computing Foundation)**. 이 모듈은 그 재단이 무엇이고(왜 회사가 아니라 재단인가), 프로젝트가 어떻게 들어와 자라고 졸업하는지(Sandbox→Incubating→Graduated), 그리고 200+ 프로젝트의 지도(landscape)를 읽는 법을 다룹니다 — Part 4 전체의 프롤로그이자, "어느 프로젝트에 인생 시간을 걸지"를 판단하는 도구입니다.

## 학습 목표

1. CNCF의 구조(LF 산하, TOC·TAG·거버닝보드·엔드유저)를 그리고, "중립 재단"이 존재하는 이유(상표·라이선스·거버넌스)를 설명합니다
2. 성숙도 3단계(Sandbox/Incubating/Graduated)의 심사 기준과 각 단계가 채택 판단에 주는 신호를 압니다
3. landscape를 데이터로 다룹니다 — 카테고리 구조, 프로젝트 수, 성숙도 분포를 직접 집계합니다
4. 졸업 심사(due diligence)의 실물 문서를 읽고, 프로젝트 건강도(DevStats·유지보수자 다양성)를 측정합니다
5. "재단 프로젝트"가 아닌 것(오픈코어·단일 벤더)과의 차이를 실사례(라이선스 전환 사태들)로 압니다

## 선행: k8s·eks·cicd 파트 (특히 cicd 26~28의 거버넌스 3유형) · 도구: gh, python3/jq
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-landscape-as-data.md](./lab-01-landscape-as-data.md) — landscape를 집계·분석
3. [lab-02-graduation-dossier.md](./lab-02-graduation-dossier.md) — 졸업 심사 실물 읽기·건강도 측정
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
