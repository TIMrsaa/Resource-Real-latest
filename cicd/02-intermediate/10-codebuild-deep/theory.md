# 이론 — buildspec 페이즈, 캐시 3종, VPC, 컴퓨트 경제학

> **🌱 17세 눈높이 비유: 요리 경연 부스**
> - **buildspec** = 레시피 카드: **재료 준비(install) → 밑작업(pre_build) → 조리(build) → 마무리·플레이팅(post_build)**
> - **페이즈 실패** = 조리 중 태우면 마무리로 안 넘어갑니다 (단, "타도 접시는 치우자"는 on-failure로)
> - **캐시** = 매번 시장에 안 가고 냉장고(로컬)·창고(S3)에서 꺼내기
> - **VPC 빌드** = 부스를 건물 안쪽(프라이빗 서브넷)에 두기 — 사내 식자재 창고(RDS)엔 가깝지만, 바깥 시장에 가려면 정문(NAT)을 거쳐야 하고 통행료가 듭니다
> - **컴퓨트 타입** = 화구 크기: 큰 요리엔 큰 화구, 작은 요리에 큰 화구는 낭비

---

## 1. buildspec 페이즈 모델

```yaml
version: 0.2

env:
  variables: { LOG_LEVEL: info }
  parameter-store: { DB_HOST: /myapp/db/host }        # SSM Parameter Store
  secrets-manager: { API_KEY: myapp/api:key }          # Secrets Manager (eks 25)

phases:
  install:
    runtime-versions: { golang: 1.23 }                 # 관리형 런타임
    commands: [ "echo 준비" ]
  pre_build:
    commands: [ "aws ecr get-login-password | docker login ..." ]
  build:
    commands: [ "docker build -t $IMAGE ." ]
    finally: [ "echo 이 페이즈 끝나면 항상 실행" ]      # 성공/실패 무관
  post_build:
    commands: [ "docker push $IMAGE" ]

artifacts:
  files: [ imagedefinitions.json ]                     # CodePipeline/ECS로 전달
cache:
  paths: [ "/root/.cache/**/*", "/go/pkg/mod/**/*" ]
reports:                                               # 테스트 리포트 (05)
  unit:
    files: [ "junit.xml" ]
    file-format: JUNITXML
```

페이즈 실패 규칙: 한 페이즈가 실패하면 **다음 페이즈로 안 넘어갑니다**(단 `finally`는 실행). `on-failure: ABORT`(기본) vs `CONTINUE`로 조정. Actions의 `if: always()`(03)에 대응하는 것이 `finally`.

## 2. 캐시 3종 — 04의 원리를 CodeBuild로

| 종류 | 저장 위치 | 특징 |
|------|----------|------|
| **로컬** | 빌드 호스트(재사용 시) | DOCKER_LAYER / SOURCE / CUSTOM 모드, 빠름, 보장 안 됨(호스트 재활용에 의존) |
| **S3** | S3 버킷 | 명시적·안정적, 다운로드 시간 있음 |
| **커스텀** | buildspec의 `cache.paths` | 지정 디렉터리를 S3로 (의존성 캐시) |

로컬 캐시의 `LOCAL_DOCKER_LAYER_CACHE`가 04의 레이어 캐시에 해당 — 단 **빌드 호스트가 재사용될 때만** 히트합니다(GitHub-hosted 러너가 매번 새 VM이라 캐시가 안 남는 것과 같은 문제, 03). 안정적 캐시는 S3, 그리고 Docker 빌드라면 **BuildKit + ECR 레지스트리 캐시**(04)가 CodeBuild에서도 최선입니다.

## 3. VPC 구성 — 프라이빗 접근의 거래

```
CodeBuild VPC 구성 없음:  AWS 관리 네트워크에서 실행 (인터넷 O, 프라이빗 리소스 X)
CodeBuild VPC 구성 있음:  지정한 VPC/서브넷/SG에서 ENI를 만들어 실행
   → 프라이빗 RDS·ElastiCache·내부 API 접근 O
   → 인터넷 접근은? 프라이빗 서브넷 + NAT GW 필요 (eks 16·18의 그 경로)
```

주의점 (전부 eks 파트에서 본 것):

- **IP 소비**: 빌드마다 ENI가 IP를 잡습니다 — 대량 동시 빌드가 서브넷 IP를 소모(eks 16)
- **NAT 비용**: VPC 빌드가 외부(ECR public, 패키지 레지스트리)에 나가면 NAT 처리 요금(eks 22 숨은 3대장)
- **VPC 엔드포인트**: ECR/S3/CloudWatch용 엔드포인트를 두면 NAT를 우회(eks 22 pitfall 5) — VPC 빌드의 비용 최적화 1순위

## 4. 컴퓨트 타입 — 빌드의 화구

| 타입 | vCPU/메모리 | 자리 |
|------|-----------|------|
| SMALL | 2/3GB | 가벼운 빌드, 테스트 |
| MEDIUM | 4/7GB | 일반 |
| LARGE | 8/15GB | 큰 컴파일, 이미지 빌드 |
| 2XLARGE / GPU / ARM | 대용량·가속·arm64 | 특수(eks 19의 Graviton 빌드!) |

경제학: 빌드 시간 × 컴퓨트 단가 = 비용. **큰 컴퓨트가 빌드를 절반으로 줄이면 단가가 두 배여도 본전**이고, 캐시가 잘 되면 작은 컴퓨트로 충분합니다. ARM 컴퓨트는 x86보다 저렴하니 multi-arch 빌드(eks 19)의 arm 부분은 ARM 컴퓨트에서 — 크로스 컴파일보다 네이티브가 빠르고 쌉니다.

## 5. 권한 — 서비스 역할 (OIDC 아님)

GitHub Actions는 OIDC로 역할을 assume했지만(07), CodeBuild는 **자신에게 붙은 서비스 역할**로 실행됩니다(eks 09의 Pod가 Pod Identity를 갖는 것과 유사):

```
CodeBuild 프로젝트 → 서비스 역할 → ECR push, EKS 접근, Secrets Manager 등
```

- 이 역할이 곧 빌드의 권한 경계 — 최소권한(자원 ARN 단위)
- EKS 배포라면 이 역할을 클러스터 access entry(eks 02)에 매핑 → `kubectl`/`helm`이 동작
- Secrets Manager 통합(§1의 `secrets-manager`)으로 시크릿을 env에 안전하게 주입 — 단 로그 노출 주의

## 6. 소스/도구에서 확인하기

- buildspec 레퍼런스: https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html
- 로컬 빌드 에이전트(codebuild_build.sh): 로컬에서 buildspec 디버깅
- VPC 구성·엔드포인트: CodeBuild 문서 "Use CodeBuild with Amazon VPC"
- 컴퓨트 타입·요금: CodeBuild pricing

## 요약 카드

| 질문 | 답 |
|------|----|
| 페이즈 모델? | install→pre_build→build→post_build (+finally, artifacts, cache, reports) |
| `finally`의 대응물? | Actions의 `if: always()` |
| 캐시 안정성? | 로컬(호스트 재사용 의존) < S3/레지스트리(명시·안정) — 04의 레이어 원리 |
| VPC 빌드의 대가? | ENI IP 소비 + NAT 비용 → VPC 엔드포인트로 완화 |
| 컴퓨트 선택? | 시간×단가 — 캐시 좋으면 작게, arm 빌드는 ARM 컴퓨트 |
| 권한? | 서비스 역할(OIDC 아님) — EKS는 access entry로 매핑 |
