# 이론 — 시크릿의 2축 분류, 플랫폼 시크릿의 실체, Vault, GitOps 3해법, 유출 대응

> **🌱 17세 눈높이 비유: 기숙사 열쇠 관리**
> - **장기 정적 시크릿** = 복사 가능한 마스터키 — 잃어버리면 전 객실 자물쇠 교체 (전면 순환)
> - **없애기(OIDC)** = 열쇠 대신 얼굴 인식 — 훔칠 열쇠 자체가 없음 (07)
> - **동적 시크릿(Vault)** = 1시간짜리 일회용 카드키 — 주웠어도 이미 만료
> - **GitOps 난제** = 규칙("모든 것은 게시판(Git)에 공지")과 비밀("금고 비밀번호는 게시판에 못 씀")의 충돌
>   - **sealed-secrets** = 게시판에 잠긴 상자를 붙임 — 사감(클러스터 컨트롤러)만 열쇠 보유
>   - **SOPS** = 게시판에 암호문을 붙임 — 해독 키는 별도 금고(KMS), 어느 줄이 바뀌었는지는 보임
>   - **ESO** = 게시판에는 "비밀번호는 사감실 금고 3번 칸" 쪽지만 — 진실은 금고에
> - **유출 대응** = 마스터키 분실 신고 절차 — "어느 방들이 그 키로 열리는지"를 아는 것이 첫걸음

---

## 1. 분류가 전략을 정합니다 — 2축과 결정 트리

```
                     ┌ 없앨 수 있나요? ─ Yes → OIDC(07)/IRSA(eks)/keyless(21) — 끝
모든 시크릿에 대해 ──┤
                     └ No → 동적 발급 가능한가? ─ Yes → Vault 동적 시크릿 (TTL)
                            └ No (서드파티 API 키 등) → 스토어 보관 + 주입 + 순환 계획
```

| 축 | 값 | 예 | 유출 시 |
|---|---|---|---|
| 수명 | 장기 정적 | AWS 키, PAT, API 키 | **순환 전까지 유효** — 최악 |
| | 단명 동적 | OIDC 토큰(10분), Vault DB 계정(1h) | 대부분 이미 만료 |
| 보관 | CI 플랫폼 | GHA secrets | 플랫폼 침해 시 일괄 노출 (CircleCI 2023) |
| | 외부 스토어 | Vault, AWS Secrets Manager | 접근 제어·감사·순환 중앙화 |
| | Git(암호화) | sealed-secrets, SOPS | 암호문 노출 + 키 유출 시에만 |

## 2. CI 플랫폼 시크릿의 실체 — GHA 기준

```
저장: 조직/저장소/environment 3층 (environment가 최우선)
주입: 워크플로가 참조한 것만 러너 프로세스에 — needs 없는 잡에는 안 감
마스킹: 로그 출력 시 문자열 치환 — 03에서 봤듯 인코딩(base64, rev)이면 우회됨
fork PR: pull_request 이벤트에는 시크릿 미제공 (03의 신뢰 경계) — pull_request_target이 위험한 이유
environment: 승인·브랜치 제한(06)과 결합 — "prod 시크릿은 승인된 main 배포에만"
```

플랫폼 시크릿의 한계 두 가지: ① **플랫폼이 뚫리면 일괄 노출**(CircleCI 2023 — 플랫폼 자체가 단일 장애점), ② 순환·감사가 저장소별로 파편화. 그래서 규모가 커지면 "플랫폼에는 스토어 접근 자격(그마저 OIDC로)만 두고, 실제 시크릿은 스토어에"로 이동합니다.

## 3. Vault — 동적 시크릿이 게임을 바꿉니다

Vault의 본질 기여는 보관(금고)이 아니라 **발급(조폐)**입니다:

```
CI 잡 → Vault에 JWT 인증 (GHA OIDC 토큰! — 07이 여기서도) 
      → Vault가 DB에 실제 계정을 그 자리에서 생성 (CREATE ROLE ... VALID UNTIL 1h)
      → 잡이 쓰고 → TTL 만료 시 Vault가 자동 폐기 (revoke)
★ "유출된 자격증명"이라는 개념 자체가 약해짐 — 훔쳐도 1시간짜리·이미 사용처 기록됨
```

| 기능 | 내용 | CI/CD 접점 |
|---|---|---|
| 동적 시크릿 | DB/클라우드 계정을 TTL로 발급·자동 폐기 | 마이그레이션 잡(11)의 DB 접근 |
| JWT/OIDC 인증 | CI의 OIDC 토큰으로 Vault 로그인 — 장기 토큰 불필요 | 07의 패턴 재사용 |
| transit | 암호화 서비스 (키는 Vault 밖으로 안 나감) | 앱 데이터 암호화 |
| K8s 통합 | Agent Injector(사이드카) / CSI / **VSO**(Operator — Secret으로 동기화) | eks·k8s 워크로드 주입 |

## 4. GitOps 시크릿 3해법 — 구조와 철학

14의 원칙("Git이 진실, 클러스터는 그 반영")과 시크릿의 충돌을 푸는 세 구조:

### sealed-secrets — "클러스터만 열 수 있는 상자를 Git에"

```
kubeseal(CLI)이 컨트롤러의 공개키로 암호화 → SealedSecret CR을 Git에 커밋
클러스터의 컨트롤러가 개인키로 복호화 → Secret 생성
```

- 장점: 추가 인프라 없음(컨트롤러 하나), Git이 진실 유지
- 약점: **개인키가 클러스터에 종속** — 클러스터 재구축(36의 DR!) 시 키 백업 없으면 전부 재암호화, 멀티클러스터면 클러스터별 재암호화

### SOPS — "값만 암호화된 YAML을 Git에"

```
sops -e secret.yaml → 키(name 등)는 평문, 값만 암호문 → Git에 커밋
복호화 키: age(로컬 키쌍) 또는 KMS(AWS KMS 등 — IAM으로 접근 제어)
CD 측(Flux는 내장, ArgoCD는 플러그인)이 적용 시 복호화
```

- 장점: **diff가 의미 있음**(어느 키의 값이 바뀌었는지 리뷰 가능), KMS면 키 관리를 클라우드에 위임
- 약점: 복호화 자격의 배포 문제(CD가 KMS 접근 필요), ArgoCD는 네이티브 아님

### External Secrets Operator — "Git에는 포인터만"

```
Git: ExternalSecret CR ("ASM의 prod/db-password를 Secret으로 만들어라") — 시크릿 값 없음!
ESO 컨트롤러: 스토어에서 값을 읽어 Secret 생성·주기적 동기화 (refreshInterval)
```

- 장점: **진실이 스토어에** — 순환이 스토어에서 한 번(Git 커밋 불필요), 감사·접근제어 중앙화, 멀티클러스터 자연스러움
- 약점: 외부 스토어 의존(운영 대상 +1), "Git만 보면 전부"라는 GitOps 순수성 약화

### 결정표

| 기준 | sealed-secrets | SOPS | ESO |
|---|---|---|---|
| 진실의 위치 | Git(암호문) | Git(암호문) | **스토어** |
| 추가 인프라 | 없음 | 없음(age)/KMS | 스토어 필요 |
| 순환 | 재암호화+커밋 | 재암호화+커밋 | **스토어에서 한 번** |
| 멀티클러스터 | 클러스터별 키 ⚠️ | 키 공유 가능 | 자연스러움 |
| diff 리뷰 | 불가(통암호문) | **값 단위 가능** | CR이라 평문(값 없음) |
| 자리 | 소규모·단일 클러스터 | Git 순수주의+리뷰 중시 | **스토어 있는 조직 표준** |

## 5. 주입과 전파 — Secret을 만들고 나서의 문제

```
env로 주입: Pod 시작 시 고정 — 순환해도 재시작 전까지 옛 값 ⚠️
volume 마운트: kubelet이 주기 갱신 (subPath 쓰면 갱신 안 됨! — k8s의 유명 함정)
앱이 감지 못 하면: Reloader 등으로 Secret 변경 시 롤링 재시작 트리거
```

순환이 "스토어 갱신"으로 끝나지 않는 이유 — **전파 경로 전체**(스토어 → Secret → Pod → 앱 메모리)가 갱신돼야 완료입니다. 순환 절차서에는 마지막 홉(앱 재시작 여부)까지 적혀야 합니다.

## 6. 유출 대응 — 절차가 있어야 사고가 사건으로 끝납니다

```
0. 사전: 스캔을 게이트로 (gitleaks pre-commit + CI) — 커밋 전 차단이 최선
1. 탐지: 어디에 노출됐나 (Git 이력? 로그? 퍼블릭?) — Git 이력은 rewrite해도 포크·클론에 남음 → 순환이 유일한 해법
2. 파악: 이 시크릿으로 무엇이 열리나 — "시크릿 → 권한 지도"가 미리 있어야 분 단위 대응
3. 순환: 새 값 발급 → 전파(§5) → 옛 값 폐기 (폐기 전 사용 로그로 악용 여부 확인)
4. 사후: 왜 장기 시크릿이었나요? — 없애기(OIDC)/줄이기(동적)로 재발 구조 제거
```

## 7. 소스/도구에서 확인하기

- GHA 시크릿: https://docs.github.com/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
- Vault 동적 시크릿: https://developer.hashicorp.com/vault/docs/secrets/databases
- sealed-secrets: https://github.com/bitnami-labs/sealed-secrets · SOPS: https://github.com/getsops/sops
- External Secrets Operator: https://external-secrets.io
- gitleaks: https://github.com/gitleaks/gitleaks

## 요약 카드

| 질문 | 답 |
|------|----|
| 순서? | 없애기(OIDC/keyless) → 줄이기(동적·TTL) → 관리하기(스토어) — 도구부터 고르면 화약고 정리 |
| 플랫폼 시크릿 한계? | 플랫폼 침해 시 일괄 노출(CircleCI 2023), 순환·감사 파편화 |
| Vault의 본질? | 보관이 아니라 **발급** — TTL 자격증명은 유출돼도 이미 만료 |
| GitOps 3해법? | sealed(클러스터 키로 암호문), SOPS(KMS/age 암호문+diff), ESO(포인터만 — 스토어가 진실) |
| 순환의 끝? | 스토어 갱신이 아니라 **앱 메모리까지 전파** (env는 재시작 필요, subPath는 갱신 안 됨) |
| 유출 대응 핵심? | "시크릿 → 권한 지도"의 사전 존재 — Git 이력 rewrite는 해법 아님, 순환만이 해법 |
