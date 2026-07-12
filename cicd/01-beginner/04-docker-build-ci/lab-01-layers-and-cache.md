# Lab 01 — 캐시 무효화를 눈으로 보고, 시간으로 재기

Dockerfile 한 줄의 순서가 만드는 차이를 **초 단위로 실측**합니다. CI에 캐시를 붙이기 전에, 캐시가 왜 히트하지 않는지를 먼저 이해해야 합니다.

## Step 1. 실험 앱

```bash
mkdir -p ~/ci-lab/build && cd ~/ci-lab/build
cat > requirements.txt <<'EOF'
flask==3.1.0
requests==2.32.3
gunicorn==23.0.0
EOF
cat > app.py <<'EOF'
from flask import Flask
app = Flask(__name__)

@app.get("/")
def home():
    return {"version": "1"}
EOF
```

## Step 2. 나쁜 Dockerfile — 매번 의존성 재설치

```bash
cat > Dockerfile.bad <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY . .                                   # ★ 코드가 먼저 — 커밋마다 캐시 붕괴
RUN pip install --no-cache-dir -r requirements.txt
CMD ["gunicorn", "-b", "0.0.0.0:8000", "app:app"]
EOF

echo "--- 1차 빌드 (캐시 없음) ---"
time docker build -q -f Dockerfile.bad -t demo:bad . >/dev/null

echo "--- 코드 한 줄 수정 후 2차 빌드 ---"
sed -i 's/"version": "1"/"version": "2"/' app.py
time docker build -f Dockerfile.bad -t demo:bad . 2>&1 | grep -E "CACHED|RUN pip" | head -3
```

예상: 2차 빌드에서도 `RUN pip install`이 **다시 실행**됩니다(수십 초). `COPY . .`이 바뀌었으니 그 뒤 전부 무효 — theory §1의 규칙 그대로.

## Step 3. 좋은 Dockerfile — 의존성을 먼저

```bash
cat > Dockerfile.good <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .                    # ★ 변경 빈도 낮은 것 먼저
RUN pip install --no-cache-dir -r requirements.txt
COPY . .                                   # 코드는 마지막
CMD ["gunicorn", "-b", "0.0.0.0:8000", "app:app"]
EOF

echo "--- 1차 (캐시 채우기) ---"
docker build -q -f Dockerfile.good -t demo:good . >/dev/null

echo "--- 코드 수정 후 2차 ---"
sed -i 's/"version": "2"/"version": "3"/' app.py
time docker build -f Dockerfile.good -t demo:good . 2>&1 | grep -E "CACHED" | wc -l
```

예상: `RUN pip install`이 `CACHED`로 표시되고 빌드가 **1초 내외**. ✅ 같은 코드, 같은 도구, **줄 순서만 바꿔서** 얻은 결과입니다.

## Step 4. 숨은 캐시 파괴자 — .dockerignore

```bash
git init -q 2>/dev/null; mkdir -p node_modules && dd if=/dev/zero of=node_modules/junk bs=1M count=20 2>/dev/null

echo "--- .dockerignore 없이 빌드 컨텍스트 크기 ---"
docker build -f Dockerfile.good -t demo:good . 2>&1 | grep "transferring context" | tail -1

cat > .dockerignore <<'EOF'
.git
node_modules
*.pyc
__pycache__
.venv
Dockerfile*
EOF

echo "--- .dockerignore 적용 후 ---"
docker build -f Dockerfile.good -t demo:good . 2>&1 | grep "transferring context" | tail -1
```

✅ 컨텍스트가 줄면 전송 시간이 줄고, **무관한 파일 변경이 캐시를 깨지 않습니다.** 그리고 `.git`을 빼는 것은 보안 조치이기도 합니다 — 히스토리에 남은 옛 시크릿이 이미지로 배포되는 것을 막습니다.

## Step 5. 멀티스테이지 — 크기와 공격 표면

Go로 극적인 차이를 봅니다:

```bash
mkdir -p go-demo && cd go-demo
cat > main.go <<'EOF'
package main

import ("fmt"; "net/http")

func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintln(w, "hello")
    })
    http.ListenAndServe(":8080", nil)
}
EOF
cat > go.mod <<'EOF'
module demo

go 1.23
EOF

# 단일 스테이지
cat > Dockerfile.single <<'EOF'
FROM golang:1.23
WORKDIR /src
COPY . .
RUN go build -o /app .
CMD ["/app"]
EOF

# 멀티스테이지
cat > Dockerfile.multi <<'EOF'
FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app .

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
EOF

docker build -q -f Dockerfile.single -t demo:single . >/dev/null
docker build -q -f Dockerfile.multi  -t demo:multi  . >/dev/null
docker images demo --format "{{.Tag}}\t{{.Size}}"
```

예상:

```
single   ~900MB
multi    ~10MB
```

보안 차이를 직접 확인:

```bash
docker run --rm demo:single sh -c "which go; ls /usr/bin | wc -l"   # 컴파일러 + 수백 개 바이너리
docker run --rm demo:multi sh -c "echo hi" 2>&1 | head -1           # → 셸이 없습니다!
```

✅ 침해된 컨테이너에서 공격자가 쓸 도구가 없습니다 — eks 25 관문 ③의 실물. 크기가 곧 공격 표면입니다.

## Step 6. BuildKit 캐시 마운트 — 레이어를 넘는 캐시

```bash
cd ~/ci-lab/build
cat > Dockerfile.cachemount <<'EOF'
# syntax=docker/dockerfile:1
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt          # --no-cache-dir 제거! 캐시를 쓰게
COPY . .
CMD ["gunicorn", "-b", "0.0.0.0:8000", "app:app"]
EOF

DOCKER_BUILDKIT=1 docker build -q -f Dockerfile.cachemount -t demo:cm . >/dev/null
echo "requests==2.32.2" >> requirements.txt      # 의존성 하나 변경 → 레이어 캐시는 미스
time DOCKER_BUILDKIT=1 docker build -f Dockerfile.cachemount -t demo:cm . 2>&1 | tail -2
```

✅ 레이어 캐시는 깨졌지만 **휠 파일은 캐시 마운트에서** 나옵니다 — 재다운로드가 없습니다. 의존성이 수백 개인 프로젝트에서 이 차이가 분 단위가 됩니다.

## Step 7. 시크릿의 흔적 — ARG를 쓰면 안 되는 이유

```bash
cat > Dockerfile.leak <<'EOF'
FROM python:3.12-slim
ARG API_TOKEN
RUN echo "using token..." && test -n "$API_TOKEN"
EOF
docker build -q --build-arg API_TOKEN=super-secret-123 -f Dockerfile.leak -t demo:leak . >/dev/null

# 이미지 히스토리에 남아 있는가요?
docker history --no-trunc demo:leak | grep -o "API_TOKEN=[^ ]*" | head -1
```

예상: `API_TOKEN=super-secret-123` — **이미지를 받은 누구나 볼 수 있습니다.** 정답은 BuildKit 시크릿 마운트:

```bash
cat > Dockerfile.secret <<'EOF'
# syntax=docker/dockerfile:1
FROM python:3.12-slim
RUN --mount=type=secret,id=token \
    test -s /run/secrets/token && echo "token 사용됨 (흔적 없음)"
EOF
echo "super-secret-123" > /tmp/token
DOCKER_BUILDKIT=1 docker build -q --secret id=token,src=/tmp/token -f Dockerfile.secret -t demo:secret . >/dev/null
docker history --no-trunc demo:secret | grep -c "super-secret" || echo "✅ 히스토리에 흔적 없음"
rm /tmp/token
```

## Step 8. 실측 기록 (산출물)

```markdown
# 빌드 최적화 실측
| 변경 | 2차 빌드 시간 | 이미지 크기 |
|------|-------------|-----------|
| COPY . . 먼저 (bad) | __초 | __ |
| 의존성 먼저 (good) | __초 | __ |
| + 캐시 마운트 | __초 (의존성 변경 시에도) | __ |
| 단일 스테이지(Go) | — | ~900MB |
| 멀티스테이지 + distroless | — | ~10MB |

# 우리 Dockerfile 체크리스트
- [ ] 변경 빈도 낮은 것부터 위로 (베이스 → 시스템 → 의존성 → 코드)
- [ ] .dockerignore (.git, node_modules 필수)
- [ ] 멀티스테이지 + 최소 런타임 베이스 (distroless/scratch)
- [ ] 비 root 사용자 (USER nonroot)
- [ ] 시크릿은 --mount=type=secret (ARG 금지)
- [ ] 베이스 이미지 다이제스트 고정 (재현성 2층)
```

## 정리

```bash
docker rmi -f demo:bad demo:good demo:cm demo:leak demo:secret demo:single demo:multi 2>/dev/null || true
cd ~ && rm -rf ~/ci-lab/build
```
