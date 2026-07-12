# 학습 가이드 — "탈출 시나리오"에서 역산하는 보안

## 위협 모델부터

공격자가 컨테이너 하나를 장악했다고 합시다(취약한 웹앱). 다음 행보는:

```
① 컨테이너 안에서 권한 상승       → root로 실행 중이면 공짜
② 호스트로 탈출                  → privileged, hostPath, 커널 취약점 + capabilities
③ 노드에서 클러스터로            → SA 토큰(모듈 11), kubelet 자격증명
④ 옆으로 번지기                  → 네트워크(모듈 15), 다른 노드
```

이 모듈의 손잡이들은 ①②를 막습니다 (③은 11, ④는 15에서 이미). 각 설정을 "무슨 단계를 끊는가"로 기억하면 외울 게 없습니다:

| 설정 | 끊는 단계 |
|------|----------|
| runAsNonRoot / runAsUser | ① root 시작 차단 |
| allowPrivilegeEscalation: false | ① setuid류 상승 차단 |
| capabilities drop ALL | ②의 무기(특권 시스템콜) 회수 |
| seccompProfile | ②의 통로(시스템콜) 필터 |
| readOnlyRootFilesystem | 악성코드 설치/변조 방해 |
| user namespaces | ② 성공해도 호스트선 일반 유저 |

## PSA의 위치

이 손잡이들을 Pod마다 손으로 챙기는 건 불가능합니다 → **네임스페이스 단위로 표준 묶음을 강제**하는 내장 admission이 PSA입니다. 3단계(privileged/baseline/restricted) × 3모드(enforce/audit/warn) — 모듈 23의 "Audit→Warn→Deny 점진 도입"이 내장 기능으로 제공되는 셈.

## 목표 상태 미리 보기

이 모듈의 산출물은 **"restricted 통과 Pod 템플릿"** 입니다 — 이후 모든 운영 워크로드의 기본값으로 복사해 쓸 보안 베이스라인. (참고폴더 스타일로 말하면: 이게 이 모듈의 mini-project입니다)
