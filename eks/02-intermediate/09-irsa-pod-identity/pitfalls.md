# 흔한 함정 5선

## 1. 신뢰 정책 sub 오타 (IRSA 고장 1위)

`system:serviceaccount:iam-lab:s3-reader`에서 ns/SA 철자 하나 — STS가 조용히 거부하고, 에러는 앱 로그의 `Not authorized to perform sts:AssumeRoleWithWebIdentity`로만. 디버깅 루틴: Pod의 토큰 sub(lab-01 Step 5)와 신뢰 정책 Condition을 **나란히 놓고 글자 대조**. Pod Identity로 가면 이 함정 자체가 사라집니다.

## 2. 조용한 IMDS 폴백

배선이 빠졌는데 "동작은 한다" — SDK 체인이 노드 역할(IMDS)로 폴백한 것. 노드 역할에 우연히 권한이 있으면 **잘못된 신분으로 일하는 셈**이고, 감사에서 "이 API 누가 불렀어?"가 노드로 뭉개집니다. 대응: 노드 역할 최소화 + caller-identity를 배포 검증에 포함("assumed-role/<의도한 역할>인가") + IMDS hop limit 1.

## 3. 변경 후 재시작 누락

어노테이션/association을 바꿨는데 "안 먹어요" — 주입은 **Pod 기동 시** webhook이 합니다. 기존 Pod엔 소급 없음(k8s 07 ConfigMap env와 같은 결). 변경 → rollout restart까지가 한 세트.

## 4. 만능 역할 하나로 전 워크로드

"편하게 PowerUser 역할 하나를 모든 SA에" — Pod 단위 신분증의 의미가 소멸하고, 침해 반경이 클러스터 전체가 됩니다. 워크로드(SA)마다 역할, 역할마다 최소 정책 — k8s 11 RBAC에서 한 그 작업을 IAM에서도. 역할 수가 부담스러우면 Pod Identity의 세션 태그 조건으로 공유 역할을 정밀 분할.

## 5. 토큰 파일을 Secret으로 오해해 복사/보관

`AWS_WEB_IDENTITY_TOKEN_FILE`의 토큰을 "백업"하거나 다른 곳에 옮겨 쓰는 시도 — 그 토큰은 짧은 수명+해당 Pod 문맥용이고, 옮겨 쓰는 순간 설계(단명 자격증명)를 부수는 것입니다. 자격증명이 필요한 곳엔 **그곳의 신분 배선**을 만들어라(다른 Pod엔 그 Pod의 SA, CI엔 OIDC 연합 — cicd 파트).

## 실무 사고 사례

> 보안 감사에서 "S3 버킷 삭제 API를 노드 역할이 호출한 기록"이 발견됐습니다 — 범인 Pod 추적 불가(노드의 수십 개 Pod 중 누구든 가능). 진상: 한 팀이 IRSA 어노테이션 오타로 배선이 실패했는데, 노드 역할에 과거 PoC 때 붙인 S3FullAccess가 남아 있어 **폴백으로 "잘" 동작**해온 것. 그 권한을 이용한 스크립트 사고가 익명으로 묻힐 뻔했습니다. 조치: ① 노드 역할에서 워크로드성 권한 전면 제거 ② 배포 파이프라인에 caller-identity 검증 단계 ③ IMDS hop limit 1 ④ Pod Identity 전환으로 association 전수 감사 가능화. 교훈: **폴백은 편의가 아니라 침묵하는 구멍**입니다.
