# Lab 02 — 이미지 빌드, 레이어 해부, ECR 푸시

> **목표**: 이미지를 직접 만들고, 레이어 구조를 눈으로 확인하고, OCI Distribution Spec(레지스트리)을 ECR로 체험합니다.
> **비용**: ECR 스토리지 $0.10/GB·월 — 마지막에 cleanup.sh로 삭제하면 사실상 0원.

---

## Step 1. 작은 웹 앱과 Dockerfile 만들기

```bash
mkdir -p ~/lab-image && cd ~/lab-image

cat > app.py <<'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import os

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Hello from {os.uname().nodename}\n".encode())

HTTPServer(("0.0.0.0", 8080), H).serve_forever()
EOF

cat > Dockerfile <<'EOF'
FROM python:3.13-slim
WORKDIR /app
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
EOF
```

## Step 2. 빌드하고 레이어 캐시 체험

```bash
docker build -t hello-k8s:v1 .
```

예상 출력 (끝부분):
```
=> [1/3] FROM docker.io/library/python:3.13-slim
=> [2/3] WORKDIR /app
=> [3/3] COPY app.py .
=> => naming to docker.io/library/hello-k8s:v1
```

이제 **app.py를 한 글자만 고치고** 다시 빌드해보세요:

```bash
sed -i 's/Hello/Hi/' app.py
docker build -t hello-k8s:v2 .
```

✅ **검증 포인트**: `[1/3] FROM...`, `[2/3] WORKDIR` 단계에 `CACHED` 표시가 뜹니다. 바뀐 줄(`COPY`)부터만 다시 실행 — 이것이 레이어 캐시입니다.

## Step 3. 레이어 해부

```bash
docker history hello-k8s:v1
```

예상 출력:
```
IMAGE     CREATED BY                          SIZE
xxxx      CMD ["python" "app.py"]             0B      ← 메타데이터만
xxxx      EXPOSE map[8080/tcp:{}]             0B
xxxx      COPY app.py . # buildkit            ~400B   ← 파일 추가된 레이어
xxxx      WORKDIR /app                        0B
<missing> ... (python:3.13-slim의 레이어들)    ~120MB
```

```bash
# 이미지를 OCI 형식 그대로 풀어서 내부 구조 직접 보기
docker save hello-k8s:v1 -o img.tar && mkdir -p img && tar -xf img.tar -C img
ls img/blobs/sha256/ | head    # 레이어와 config가 전부 평범한 파일(blob)
cat img/index.json             # OCI Image Spec의 진입점
```

✅ **검증 포인트**: 이미지의 실체는 "tar 묶음 + JSON 매니페스트"일 뿐입니다. 마법이 없습니다.

## Step 4. 실행하고 접속

```bash
docker run -d --name web -p 8080:8080 hello-k8s:v1
curl -s localhost:8080
```

예상 출력:
```
Hello from f3a91c2e8b12      ← 컨테이너 ID가 hostname (UTS namespace!)
```

## Step 5. ECR 리포지토리 생성 & 푸시

```bash
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr create-repository --repository-name hello-k8s --region $AWS_REGION
```

예상 출력(JSON)에서 `repositoryUri` 확인:
```
"repositoryUri": "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/hello-k8s"
```

```bash
# 로그인 (12시간 유효 토큰)
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 태그 후 푸시
docker tag hello-k8s:v1 $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/hello-k8s:v1
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/hello-k8s:v1
```

예상 출력:
```
v1: digest: sha256:abcd... size: 1573
```

```bash
# 푸시 확인
aws ecr describe-images --repository-name hello-k8s --region $AWS_REGION \
  --query 'imageDetails[].{tag:imageTags[0],size:imageSizeInBytes}'
```

✅ **검증 포인트**: 이 이미지는 다음 모듈들에서 EKS Pod로 배포됩니다. "내가 만든 이미지 → 레지스트리 → 클러스터" 파이프라인의 첫 절반이 완성됐습니다.

## Step 6. (보너스) digest의 의미 — 태그는 거짓말할 수 있습니다

```bash
docker tag hello-k8s:v2 $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/hello-k8s:v1   # v2를 v1 태그로!
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/hello-k8s:v1
```

같은 `v1` 태그인데 내용이 바뀌었습니다. **태그는 옮겨 붙일 수 있는 포스트잇**이고, 내용이 보장되는 것은 `sha256:...` digest뿐입니다. 실무에서 `latest` 태그를 금기시하고, 보안 파이프라인이 digest 고정(pinning)을 쓰는 이유입니다 (cicd 파트 공급망 보안에서 심화).

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `no basic auth credentials` | ECR 로그인 토큰 만료(12h) — Step 5 로그인 재실행 |
| `denied: ... not authorized` | IAM에 `AmazonEC2ContainerRegistryPowerUser` 정책 필요 |
| push가 매우 느림 | 120MB 베이스 첫 푸시는 정상. 두 번째부터 "Layer already exists" |
| WSL2에서 aws 명령 없음 | `pip install awscli` 또는 공식 installer, `aws configure`로 자격증명 설정 |

## 정리

```bash
docker rm -f web
bash cleanup.sh   # ECR 리포지토리 삭제
```
