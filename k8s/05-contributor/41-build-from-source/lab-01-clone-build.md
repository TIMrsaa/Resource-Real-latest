# Lab 01 — 클론, 빌드, 그리고 첫 수정

> **환경**: WSL2(Ubuntu). 디스크 여유 40GB, 메모리 8GB+ 확인 후 시작.

## Step 0. 도구 준비

```bash
sudo apt-get update && sudo apt-get install -y build-essential rsync jq
go version          # 모듈 30에서 설치함 — 버전은 Step 1에서 리포 기준과 대조
docker version --format '{{.Server.Version}}'
```

## Step 1. 클론 — 미래의 PR을 위한 모양으로

```bash
mkdir -p ~/go/src/k8s.io && cd ~/go/src/k8s.io
# 본인 GitHub 계정으로 fork 해뒀다면 (45에서 필요):
#   git clone https://github.com/<내계정>/kubernetes.git && cd kubernetes
#   git remote add upstream https://github.com/kubernetes/kubernetes.git
# 일단 읽기 전용으로 시작해도 됨:
git clone --depth 50 https://github.com/kubernetes/kubernetes.git
cd kubernetes

# 이 리포가 요구하는 Go 버전 확인 (불일치 시 빌드 거부될 수 있음)
cat .go-version
go version    # 다르면 해당 버전 설치 (golang.org/dl 또는 gimme)
```

> `--depth 50`: 풀 히스토리는 수 GB — 학습엔 얕은 클론으로 충분합니다. (45에서 PR 보낼 땐 필요한 만큼 fetch)

## Step 2. 거대함 체감 — 그러나 구조는 단순

```bash
ls cmd/                                     # 아는 이름들이 전부 있습니다
find . -name "*.go" -not -path "./vendor/*" | wc -l    # 수만 개 — 그러나
ls cmd/kubectl/                              # 진입점은 이렇게 작습니다
cat cmd/kubectl/kubectl.go | head -30        # main()이 한눈에
```

✅ `cmd/kubectl/kubectl.go`의 main은 몇 줄 — 본체는 `staging/src/k8s.io/kubectl/`에 있습니다(theory §1). "거대한 코드 = 작은 진입점 + 깊은 패키지"라는 Go 프로젝트의 전형.

## Step 3. kubectl만 빌드

```bash
time make WHAT=cmd/kubectl
ls -lh _output/bin/kubectl
_output/bin/kubectl version --client
```

예상: 수 분 내 완료, 버전에 `v1.NN.N-beta...` + 커밋 해시 — **방금 내 노트북에서 태어난 kubectl**입니다.

```bash
# 진짜 클러스터에도 통합니다 (EKS kubeconfig 그대로)
_output/bin/kubectl get nodes 2>/dev/null || echo "(EKS 미접속 환경이면 생략)"
```

## Step 4. 첫 수정 — 흔적 남기기

`kubectl version`의 출력을 찾아 고쳐봅시다. **"이 문구 어디서 나오지?" → grep** 이 기여자의 기본기:

```bash
grep -rn "Client Version" staging/src/k8s.io/kubectl/pkg/cmd/version/ | head -3
```

`staging/src/k8s.io/kubectl/pkg/cmd/version/version.go`에서 출력부를 찾아, Client Version 줄 출력 직전에 한 줄 추가:

```go
fmt.Fprintf(o.Out, "Built by: my-first-build\n")    // ← 추가 (위치는 runE의 출력부)
```

재빌드 → 확인:

```bash
make WHAT=cmd/kubectl
_output/bin/kubectl version --client
```

예상:
```
Built by: my-first-build        ← 내 코드가 삽니다!
Client Version: v1.NN...
```

✅ **수정 → 빌드 → 확인 루프 완주.** 이 유치한 한 줄이 증명한 것: kubernetes는 수정하고 빌드해볼 수 있는 평범한(크긴 한) Go 프로젝트입니다. 45의 진짜 PR도 이 루프의 반복일 뿐입니다.

## Step 5. 원상 복구 (기여자의 git 습관)

```bash
git status                      # 무엇이 더러워졌나
git diff | head -20             # 내 변경 확인
git checkout -- .               # 깨끗하게 (진짜 작업은 브랜치에서 — 45)
git status                      # clean
```

## Step 6. (선택) 단위 테스트 맛보기 — 모듈 44 예고

```bash
# 방금 만진 version 패키지의 테스트만
go test k8s.io/kubectl/pkg/cmd/version/... 2>/dev/null \
  || (cd staging/src/k8s.io/kubectl && go test ./pkg/cmd/version/...)
```

✅ ok가 떨어집니다 — 변경할 때마다 이 단위 테스트가 1차 안전망(theory §3 사다리의 1단).

## 정리

리포는 lab-02와 42~45에서 계속 씁니다. 지우지 말 것.
