# 07 — ConfigMap과 Secret: 설정과 코드의 분리

> "환경마다 다른 값"을 이미지에서 분리합니다. 그리고 Secret이 왜 "자물쇠가 아닌지", 진짜 보안은 어디서 오는지까지.

## 학습 목표

1. 설정을 이미지에서 분리해야 하는 이유(12-factor)를 설명합니다
2. ConfigMap/Secret을 환경변수와 볼륨 마운트로 주입하고 차이(갱신 전파!)를 압니다
3. Secret의 base64가 암호화가 아님을 확인하고, 보호 계층(RBAC/암호화/외부 매니저)을 이해합니다
4. immutable ConfigMap, 갱신 전파 시간, subPath 함정을 다룹니다

## 선행: 모듈 04 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-configmap.md](./lab-01-configmap.md) — 주입 2방식 + 실시간 갱신 실험
3. [lab-02-secret.md](./lab-02-secret.md) — base64 까보기, 이미지풀 시크릿, 보호 계층
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 1.5h
