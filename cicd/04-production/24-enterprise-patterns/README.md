# 24 — 엔터프라이즈 패턴: 50개 팀의 파이프라인을 다스리는 법

> 팀이 5개일 때 파이프라인의 다양성은 활력이지만, 50개가 되면 같은 다양성이 감사 불능·보안 구멍·중복 노력이 됩니다. 이 모듈은 자율과 통제의 트레이드오프를 다룹니다 — 승인 게이트와 직무 분리(SoD), 컴플라이언스가 파이프라인에 실제로 요구하는 것(추적성·불변 감사), 그리고 강제 대신 "포장도로(golden path)"로 표준을 이기게 만드는 플랫폼 팀의 설계. DORA 연구의 불편한 발견 — 무거운 변경자문위원회(CAB)는 안정성을 올리지 못합니다 — 도 정면으로 다룹니다.

## 학습 목표

1. 승인 게이트를 설계합니다 — environment 승인(06)·SoD(개발자≠승인자)·고무도장화를 막는 장치
2. 컴플라이언스(SOX/PCI류)가 CI/CD에 요구하는 3요소(추적성·승인 기록·불변 감사)를 파이프라인으로 구현합니다
3. 감사 리포트("누가 무엇을 언제, 어떤 다이제스트로")를 실행 이력에서 추출합니다
4. 멀티팀 거버넌스의 도구 — 조직 룰셋, 허용 액션 목록, reusable workflow(06)의 golden path — 를 배치합니다
5. 정책을 코드로(Policy as Code) — 워크플로 YAML 자체를 OPA/conftest로 검사하는 게이트를 만듭니다

## 선행: 02(브랜치 보호), 03(허용 액션·SHA 고정), 06(environments·reusable), 21(서명 정책), 23(측정) · 도구: gh, conftest
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-approval-and-audit.md](./lab-01-approval-and-audit.md) — 승인 게이트·SoD·감사 리포트
3. [lab-02-policy-as-code.md](./lab-02-policy-as-code.md) — 워크플로 정책을 conftest 게이트로
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
