# 이론 — 클러스터 보안 체계: CIS, 이미지 공급망, 감사 루틴

> **🌱 17세 눈높이 비유: 학교 안전 점검의 체계화**
> 소화기 위치(개별 지식)는 다 압니다 — 문제는 **"전 교실을, 빠짐없이, 매 학기"** 점검하는 체계입니다.
> - **CIS 벤치마크** = 교육청이 배포한 표준 점검표 ("비상구 잠금 금지" 같은 항목 수백 개)
> - **kube-bench** = 점검표를 자동으로 채워주는 점검 로봇
> - **이미지 스캔** = 급식 재료의 원산지/유통기한 검사 — 조리(배포) 전에
> - **이미지 서명** = 재료 봉인 스티커 — 배송 중 바꿔치기 방지

---

## 1. CIS 벤치마크와 kube-bench

CIS(Center for Internet Security)가 관리하는 K8s 설정 점검 표준 — 항목 예시:

```
1.2.x  apiserver 플래그 (anonymous-auth 비활성 등)   ← EKS에선 AWS 책임
4.1.x  kubelet 설정 파일 권한                         ← 노드 = 우리 책임
5.1.x  RBAC (cluster-admin 최소화, 와일드카드 금지)    ← 우리 책임
5.2.x  Pod Security (privileged 제한...)              ← 우리 책임 (PSA — 모듈 32)
```

- **kube-bench**: 점검을 자동 실행. EKS 전용 프로파일(`eks-1.x`)이 있어 "AWS 책임 항목"을 건너뜁니다
- 결과 해석의 원칙: FAIL 전부를 0으로 만드는 게 목표가 아닙니다 — **WARN/FAIL마다 "수용/수정/예외 문서화" 결정**을 남기는 것이 감사의 본질

## 2. 이미지 공급망 — 스캔, 서명, 정책의 3종 세트

### 스캔 (trivy)

```bash
trivy image myapp:v1.2     # OS 패키지 + 언어 의존성의 CVE 목록
```

- 우선순위 규칙: **CRITICAL/HIGH + Fixed 버전 존재 + 실제 노출 경로**부터. CVE 수백 개에 질리지 않는 법은 필터링입니다 (`--severity CRITICAL,HIGH --ignore-unfixed`)
- 스캔 시점 3곳: CI(빌드 시 — cicd 파트), 레지스트리(ECR 자동 스캔), 클러스터(trivy-operator 상시)

### 서명 (cosign — 개념, 실습은 cicd 파트 21)

"이 이미지는 우리 CI가 만든 그대로다"의 암호학적 증명. digest 고정(모듈 01)의 다음 단계.

### 정책으로 강제 (모듈 23의 응용)

스캔/서명을 "사람이 챙기는 것"에서 "admission이 막는 것"으로:

```
- :latest 금지, digest 강제          → VAP(CEL)로 이미 만들었습니다 (모듈 23 lab)
- 사내 레지스트리만 허용              → CEL 한 줄
- 서명 검증, CVE 임계 차단            → 정책 엔진/웹훅 (Kyverno verifyImages 등)
```

## 3. 노드/런타임 하드닝 요약

| 항목 | 내용 | 우리가 배운 곳 |
|------|------|----------------|
| 노드 OS | Bottlerocket(컨테이너 전용 불변 OS) 검토, SSH 차단(SSM만) | eks 파트 05 |
| kubelet | 익명 접근 차단, 인증서 회전 — EKS AMI 기본 양호 | 26 |
| 런타임 탐지 | "이상 행동"(셸 실행, 민감 파일 접근) 실시간 — Falco | cncf 파트 30 |
| 워크로드 | restricted PSA + 모범 템플릿 | 32 |

## 4. 분기 감사 체크리스트 (이 모듈의 산출물 골격)

```
[ ] kube-bench 실행 → 전회 대비 diff 리뷰
[ ] cluster-admin 바인딩 전수 조회 (모듈 11)
[ ] 와일드카드 RBAC / secrets 읽기 권한 보유자 목록
[ ] PSA 미적용/privileged ns 목록 (모듈 32)
[ ] NetworkPolicy 없는 ns 목록 (모듈 15)
[ ] 만료 임박 인증서 (웹훅 — 모듈 23)
[ ] trivy: 운영 이미지 CRITICAL 미해결 목록
[ ] 감사 로그 활성 + 보관 정책 확인 (모듈 21)
[ ] EKS 보안 권고/버전 지원 확인
```

각 항목이 어느 모듈의 지식인지 보이는가 — **감사란 배운 것의 주기적 재실행**입니다.

## 5. 소스코드/도구에서 확인하기

- kube-bench: https://github.com/aquasecurity/kube-bench — `cfg/`에 벤치마크 항목이 YAML로 (검사 로직이 곧 문서)
- trivy: https://github.com/aquasecurity/trivy
- EKS 모범사례 가이드: https://docs.aws.amazon.com/eks/latest/best-practices/security.html

## 요약 카드

| 질문 | 답 |
|------|----|
| 설정 감사 도구/기준? | kube-bench / CIS (EKS 프로파일) |
| CVE 홍수의 우선순위? | CRITICAL·HIGH + 수정판 존재 + 노출 경로 |
| 스캔을 강제로 바꾸는 곳? | admission 정책 (VAP/Kyverno) |
| EKS에서 내 책임 아닌 것? | control plane 플래그/etcd (CIS의 1.x 다수) |
| 감사의 본질? | FAIL 0이 아니라 항목별 결정의 문서화 + 주기 반복 |
