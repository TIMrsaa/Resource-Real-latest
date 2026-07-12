# 흔한 함정 5선

## 1. 로컬 캐시를 "항상 빠름"으로 믿기

`LOCAL_DOCKER_LAYER_CACHE`는 빌드 호스트가 재사용될 때만 히트합니다 — CodeBuild가 새 호스트에 배정하면 콜드 스타트입니다(03의 "러너는 매번 새 VM"과 같은 문제). 그래서 로컬 캐시는 "운이 좋으면 빠름"이고, 안정적 재현을 원하면 S3 캐시나 Docker의 ECR 레지스트리 캐시(04)를 써야 합니다. 로컬 캐시에만 의존한 벤치마크는 프로덕션에서 재현되지 않습니다.

## 2. VPC 빌드를 켜고 NAT 비용에 놀라기

프라이빗 리소스 접근을 위해 VPC 구성을 하면, 그 빌드가 외부(ECR public, PyPI, npm)로 나가는 모든 트래픽이 NAT GW를 지납니다(eks 22 숨은 3대장). 대량 빌드에서 이 요금이 컴퓨트 비용을 넘기도 합니다. 처방: ECR/S3/CloudWatch Logs용 VPC 엔드포인트를 두어 NAT를 우회(eks 22 pitfall 5). 그리고 애초에 "이 빌드가 정말 프라이빗 접근이 필요한가"를 물어라 — 대부분의 빌드는 VPC가 필요 없습니다.

## 3. 서비스 역할에 과도한 권한

"편하게" CodeBuild 역할에 `AdministratorAccess`나 `PowerUserAccess`를 붙이면 — privilegedMode(Docker)로 실행되는 그 빌드가 탈취될 경우(악성 의존성, 공급망 공격) 계정 전체가 위험합니다. 역할은 자원 ARN 단위로: ECR는 그 리포지토리만, EKS는 그 클러스터의 그 네임스페이스만(access entry + RBAC). 09에서 배운 스테이지별 IAM 분리가 빌드 안에서도 적용됩니다.

## 4. 시크릿을 buildspec에 하드코딩하거나 로그로 흘리기

`env.variables`에 API 키를 평문으로 넣으면 buildspec이 저장소에 커밋되어 유출됩니다. 그리고 `env.secrets-manager`로 안전하게 주입해도, `echo $API_KEY`나 `set -x`로 로그에 찍으면 CloudWatch Logs(그리고 그 수집 비용, eks 12)에 남습니다. 시크릿은 Secrets Manager/Parameter Store에서 주입하되 **로그에 절대 출력하지 말 것** — 04의 `ARG` 시크릿 함정과 같은 교훈입니다.

## 5. privilegedMode로 신뢰할 수 없는 코드 빌드

Docker 빌드에 필요한 `privilegedMode: true`는 08의 dind와 같은 위험을 안습니다 — 관리형이라 격리는 AWS가 주지만, 그 빌드 컨테이너 안에서 임의 코드가 privileged로 돕니다. 포크 PR이나 신뢰할 수 없는 소스를 이 프로젝트로 빌드하면(webhook 트리거) 그 코드가 privileged 컨테이너에서 실행됩니다. 오픈소스 저장소의 CI라면 별도 격리(GitHub-hosted 러너)를 쓰거나, 빌드 자체를 rootless로.

## 실무 사고 사례

> 한 팀이 CodeBuild로 야간 통합 테스트를 돌렸습니다 — 테스트가 프라이빗 RDS에 붙어야 해서 VPC 구성을 켰습니다. 첫 달은 문제없었습니다. 그런데 팀이 성장하며 빌드가 하루 5회에서 200회로 늘었고, 각 빌드가 컨테이너 이미지 3개를 ECR public에서 pull하며 NAT를 거쳤습니다. 다음 달 청구서에서 NatGateway 항목이 CodeBuild 컴퓨트 비용의 3배가 됐습니다 — 아무도 "빌드가 NAT를 지난다"는 것을 몰랐습니다. 조사해보니 대부분의 빌드는 RDS에 붙는 몇 개의 테스트 때문에 VPC를 켰을 뿐, 나머지 90%의 빌드 작업(이미지 pull, 패키지 설치)은 프라이빗 접근이 필요 없었습니다. 조치: ① ECR/S3용 VPC 엔드포인트로 이미지 pull의 NAT 우회 ② VPC가 필요한 테스트만 별도 프로젝트로 분리, 나머지는 VPC 없이 ③ 베이스 이미지를 사내 ECR로 미러링. NAT 비용이 90% 줄었습니다. 교훈: **VPC 빌드는 편의가 아니라 비용이 붙는 결정입니다** — eks 22의 "숨은 3대장"이 CI 인프라에서 정확히 재현됐고, 답도 같았습니다(엔드포인트로 NAT 우회).
