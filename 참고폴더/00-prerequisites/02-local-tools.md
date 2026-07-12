# 02. 로컬 도구 설치

## 필요 도구 목록

| 도구 | 용도 | 최소 버전 |
|------|------|----------|
| `aws` | AWS CLI v2 — AWS API 호출 | 2.15+ |
| `kubectl` | Kubernetes API 클라이언트 | 1.29+ |
| `eksctl` | EKS 클러스터 생성/관리 | 0.170+ |
| `helm` | K8s 패키지 매니저 | 3.14+ |
| `terraform` | IaC 도구 (Part 3 후반) | 1.7+ |
| `go` | 시나리오 앱 빌드 | 1.22+ |
| `docker` | 컨테이너 빌드/로컬 실행 | 24+ |
| `k9s` | TUI 기반 K8s 대시보드 | 0.32+ |
| `stern` | 멀티-Pod 로그 tail | 1.30+ |
| `jq`, `yq` | JSON/YAML CLI 가공 | 최신 |
| `protoc` | gRPC 코드 생성 (Task 6) | 26+ |

## macOS (Homebrew)

```bash
brew update
brew install awscli kubectl eksctl helm terraform go k9s stern jq yq protobuf
brew install protoc-gen-go protoc-gen-go-grpc
brew install --cask docker
```

Docker Desktop 실행 후 메뉴바에 고래 아이콘이 떠야 합니다.

## Linux (apt 기반)

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# eksctl
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"
tar -xzf eksctl_$(uname -s)_amd64.tar.gz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# terraform
sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# go
sudo snap install go --classic

# docker, jq, yq 등
sudo apt-get install -y docker.io jq
sudo curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq
```

## 버전 확인

```bash
aws --version
kubectl version --client
eksctl version
helm version --short
terraform version | head -1
go version
docker --version
jq --version
yq --version
```

또는 자동 점검:
```bash
bash scripts/check-tools.sh
```

## 쉘 자동완성 (선택, 강력 추천)

```bash
# zsh
echo 'source <(kubectl completion zsh)' >> ~/.zshrc
echo 'alias k=kubectl' >> ~/.zshrc
echo 'compdef __start_kubectl k' >> ~/.zshrc
echo 'source <(helm completion zsh)' >> ~/.zshrc
echo 'source <(eksctl completion zsh)' >> ~/.zshrc
source ~/.zshrc
```

## 트러블슈팅

| 증상 | 해결 |
|------|------|
| `command not found: kubectl` | PATH에 `/usr/local/bin` 포함 확인 |
| `docker: Cannot connect to the Docker daemon` | Docker Desktop 미실행. 실행 후 재시도 |
| `eksctl version` 너무 오래됨 | `brew upgrade eksctl` 또는 GitHub release 재설치 |

## 다음 단계

→ [03-cost-guardrails.md](./03-cost-guardrails.md)
