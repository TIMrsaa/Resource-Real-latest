# 이론 — OIDC 신뢰 흐름과 `sub` 클레임의 문법

> **🌱 17세 눈높이 비유: 학생증 대신 하루짜리 방문증**
> - **장기 액세스 키** = 복사 가능한 마스터키를 주머니에 넣고 다니기. 잃어버리면 자물쇠를 다 바꿔야 하고, 누가 복사했는지 모릅니다
> - **OIDC** = 학교(GitHub)가 발급하는 **오늘 날짜·이름·소속 반이 적힌 방문증**. 은행(AWS)은 학교의 도장(공개키)을 미리 알고 있어서 위조를 알아봅니다
> - **`sub` 클레임** = 방문증에 적힌 신원 문구: `repo:회사/앱:ref:refs/heads/main` — "이 저장소의 main 브랜치에서 실행 중"
> - **신뢰 정책의 조건** = 은행의 규칙: "3학년 2반 학생증만 금고 A에 입장" — 문구를 얼마나 정확히 검사하느냐가 보안의 전부
> - **와일드카드 조건** = "이 학교 학생이면 아무나" — 옆 반 학생도, 오늘 전학 온 사람도 금고에 들어갑니다

---

## 1. 신뢰 흐름 4단계

```
① 워크플로가 GitHub OIDC 발급자에게 토큰 요청
   (permissions: id-token: write 가 있어야 함)
   → JWT: { iss: token.actions.githubusercontent.com,
            aud: sts.amazonaws.com,
            sub: "repo:org/repo:ref:refs/heads/main",
            repository, environment, job_workflow_ref, ... }

② 워크플로가 STS 호출: AssumeRoleWithWebIdentity(role_arn, jwt)

③ AWS가 검증:
   - 서명: GitHub의 공개키(OIDC 제공자 등록 시 확보한 thumbprint/JWKS)
   - 만료: 몇 분
   - 신뢰 정책의 조건: aud == sts.amazonaws.com, sub가 조건과 일치하는가

④ STS가 임시 자격증명 발급 (기본 1시간, 세션 정책으로 축소 가능)
```

**저장된 비밀이 없습니다.** 워크플로 실행 순간 발급되고 곧 만료됩니다.

## 2. `sub` 클레임 — 신원의 문법

GitHub이 발급하는 토큰의 `sub`는 컨텍스트에 따라 형태가 다릅니다:

| 실행 컨텍스트 | `sub` 값 |
|-------------|---------|
| main 브랜치 push | `repo:ORG/REPO:ref:refs/heads/main` |
| PR (같은 저장소) | `repo:ORG/REPO:pull_request` |
| 태그 | `repo:ORG/REPO:ref:refs/tags/v1.0.0` |
| **environment 사용** | `repo:ORG/REPO:environment:production` |

마지막이 특히 강력합니다 — 06의 승인 게이트를 통과한 잡만 그 `sub`를 갖습니다. 즉 **IAM 역할을 "승인된 프로덕션 배포"에만 묶을 수 있습니다.**

> 참고: environment를 지정하면 `sub`가 environment 형태로 **대체**됩니다(브랜치 형태가 아닙니다). 조건을 쓸 때 이 사실을 모르면 "왜 안 되지"가 됩니다.

## 3. 신뢰 정책 — 조건 설계가 전부

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:my-org/my-app:environment:production"
      }
    }
  }]
}
```

조건 설계의 사다리 (위험 → 안전):

```
🚨 "sub": "repo:my-org/*:*"           조직의 아무 저장소·아무 브랜치·아무 PR
⚠️  StringLike "repo:my-org/my-app:*"  그 저장소의 모든 브랜치와 PR (포크 PR 제외되지만 내부 브랜치 전부)
✅  StringEquals "...:ref:refs/heads/main"   main에서만
✅✅ StringEquals "...:environment:production" 승인된 프로덕션 배포에서만
```

**`aud` 조건을 빼면 안 됩니다** — 다른 오디언스용으로 발급된 토큰이 재사용될 수 있습니다.

## 4. 워크플로 쪽 — 두 줄

```yaml
permissions:
  id-token: write        # ★ OIDC 토큰 요청 권한 (기본은 없음)
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::<acct>:role/gha-deploy
      aws-region: ap-northeast-2
      # role-session-name: 로 CloudTrail에 식별자를 남깁니다
```

이후 스텝의 AWS CLI/SDK는 자동으로 그 자격증명을 씁니다. `AWS_ACCESS_KEY_ID` 시크릿은 **존재하지 않습니다.**

## 5. 감사 — 누가 무엇을 했나

CloudTrail의 `AssumeRoleWithWebIdentity` 이벤트에 남는 것:

```
userIdentity.principalId, requestParameters.roleArn,
requestParameters.roleSessionName,     ← 워크플로가 지정
responseElements.assumedRoleUser.arn
```

`role-session-name`에 `${{ github.repository }}-${{ github.run_id }}`처럼 쓰면 — CloudTrail에서 **어느 저장소의 어느 실행이 그 API를 호출했는지** 역추적됩니다. eks 25의 감사 논의가 CI 경계에서 재등장.

## 6. 다른 클라우드·다른 소비자

| 발급자 | 소비자 | 이름 |
|--------|--------|------|
| 클러스터 OIDC | Pod → AWS | **IRSA** (eks 09) |
| GitHub | 워크플로 → AWS | 이 모듈 |
| GitHub | 워크플로 → GCP/Azure | Workload Identity Federation |
| GitHub | 워크플로 → HashiCorp Vault | JWT auth |

동일한 패턴: **신뢰할 수 있는 발급자 + 검증 가능한 클레임 + 단명 토큰.** 이것을 이해하면 어떤 조합이든 조립할 수 있습니다 — 22(시크릿 관리)에서 Vault로 확장합니다.

## 7. 한계와 주의

- OIDC는 **인증**(누구인가)입니다. **인가**(무엇을 할 수 있나)는 여전히 IAM 정책의 몫 — 역할에 `AdministratorAccess`를 붙이면 OIDC는 아무것도 안 지켜줍니다
- self-hosted 러너(08)에서도 동작하지만, 러너가 오염되면 그 러너에서 실행되는 워크플로의 토큰을 훔칠 수 있습니다
- `sub` 외에 `repository_owner`, `job_workflow_ref`(어느 reusable workflow가 실행 중인지) 등의 조건도 가능 — 06의 공용 워크플로를 신뢰 조건에 넣는 고급 패턴

## 8. 소스/도구에서 확인하기

- GitHub OIDC 클레임 명세: https://docs.github.com/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
- `aws-actions/configure-aws-credentials`: https://github.com/aws-actions/configure-aws-credentials
- AWS IAM: "Create an OpenID Connect (OIDC) identity provider"
- 토큰 직접 확인: `curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com"`

## 요약 카드

| 질문 | 답 |
|------|----|
| 원리? | IRSA(eks 09)와 동일 — 단명 OIDC 토큰을 STS가 IAM 역할로 교환 |
| 워크플로 쪽 필수? | `permissions: id-token: write` + configure-aws-credentials |
| 신원의 문구? | `sub` 클레임 — 저장소/브랜치/PR/**environment** |
| environment 사용 시? | `sub`가 `...:environment:production` 형태로 **대체**됩니다 |
| 가장 위험한 조건? | `repo:org/*:*` — 조직 전체 침해 경로 |
| 빼면 안 되는 조건? | `aud: sts.amazonaws.com` |
| OIDC가 안 지켜주는 것? | **인가** — 역할에 붙은 정책이 여전히 최소권한이어야 |
