# 01. AWS 계정 셋업

## 1. IAM 사용자 생성

학습용 별도 IAM 사용자를 만듭니다 (루트 계정 직접 사용 금지).

### 콘솔에서 생성

1. AWS Console → IAM → Users → **Create user**
2. 이름: `eks-study-admin`
3. **Provide user access to the AWS Management Console** 체크 (선택)
4. 권한 옵션: **Attach policies directly** → `AdministratorAccess`
   - 학습 편의를 위해 Admin 권한 부여
   - 운영 환경에서는 절대 이렇게 하지 말 것 (최소 권한 원칙)
5. 생성 완료 후 **Access key** 발급 (Use case: CLI)

### 명령어로 검증

```bash
aws configure
# AWS Access Key ID: <발급받은 값>
# AWS Secret Access Key: <발급받은 값>
# Default region name: ap-northeast-2
# Default output format: json
```

## 2. 자격증명 검증

```bash
aws sts get-caller-identity
```

**기대 출력:**
```json
{
    "UserId": "AIDAxxxxxxxxxxxxxxxx",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/eks-study-admin"
}
```

## 3. 리전 통일

본 커리큘럼은 **`ap-northeast-2` (서울)** 을 기본 리전으로 사용합니다.

```bash
echo "export AWS_REGION=ap-northeast-2" >> ~/.zshrc
source ~/.zshrc
echo "${AWS_REGION}"
```

## 4. (선택) MFA 설정

학습용이라도 MFA를 활성화하면 좋습니다:
- Console → IAM → Users → `eks-study-admin` → Security credentials → Assign MFA device

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `Unable to locate credentials` | `aws configure` 미실행 또는 `~/.aws/credentials` 없음 |
| `An error occurred (AuthFailure)` | Access Key가 비활성/삭제됨. IAM에서 재발급 |
| `Could not connect to the endpoint URL` | 리전 미설정 또는 VPN/방화벽 이슈 |

## 다음 단계

→ [02-local-tools.md](./02-local-tools.md)
