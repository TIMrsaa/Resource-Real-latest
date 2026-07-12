# 외부 링크 모음

> 본 레포 안의 자료를 먼저 보세요:
> - [BEGINNER-GUIDE.md](../BEGINNER-GUIDE.md) — 입문 가이드 (멘탈 모델 + kubectl 30분 생존)
> - [glossary.md](./glossary.md) — 가나다순 용어 사전
> - [cheatsheet-kubectl.md](./cheatsheet-kubectl.md), [-aws.md](./cheatsheet-aws.md), [-eksctl.md](./cheatsheet-eksctl.md), [-helm.md](./cheatsheet-helm.md)


## 공식 문서

### Kubernetes
- 공식 문서: https://kubernetes.io/docs/
- API Reference: https://kubernetes.io/docs/reference/kubernetes-api/
- kubectl Cheat Sheet: https://kubernetes.io/docs/reference/kubectl/quick-reference/

### Amazon EKS
- EKS User Guide: https://docs.aws.amazon.com/eks/latest/userguide/
- **EKS Best Practices**: https://aws.github.io/aws-eks-best-practices/
- EKS Workshop: https://www.eksworkshop.com/
- eksctl Docs: https://eksctl.io/

### Karpenter
- 공식 문서: https://karpenter.sh/docs/
- GitHub: https://github.com/aws/karpenter-provider-aws
- 마이그레이션 가이드 (CA → Karpenter): https://karpenter.sh/docs/getting-started/migrating-from-cas/

### KEDA
- 공식 문서: https://keda.sh/docs/
- Scalers (트리거 목록): https://keda.sh/docs/latest/scalers/
- GitHub: https://github.com/kedacore/keda

### Add-on
- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- AWS EBS CSI Driver: https://github.com/kubernetes-sigs/aws-ebs-csi-driver
- AWS VPC CNI: https://github.com/aws/amazon-vpc-cni-k8s
- ExternalDNS: https://kubernetes-sigs.github.io/external-dns/
- cert-manager: https://cert-manager.io/docs/

### 관측
- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Grafana Dashboards: https://grafana.com/grafana/dashboards/?dataSource=prometheus
- CloudWatch Container Insights: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html

### Terraform
- terraform-aws-modules/eks: https://github.com/terraform-aws-modules/terraform-aws-eks
- AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

## 한국어 자료

- AWS 한국 블로그 (EKS 태그): https://aws.amazon.com/ko/blogs/korea/category/compute/amazon-elastic-kubernetes-service-amazon-eks/
- 카카오 기술블로그: https://tech.kakao.com/
- 우아한기술블로그 EKS 검색: https://techblog.woowahan.com/?s=EKS
- 당근마켓 기술블로그: https://medium.com/daangn

## 추천 책

- "Kubernetes Up and Running" (Kelsey Hightower 외)
- "Kubernetes Patterns" (Bilgin Ibryam, Roland Huß)
- "Production Kubernetes" (Josh Rosso 외)
- "쿠버네티스 입문" (조훈, 심근우, 문성주)

## 추천 영상

- AWS re:Invent 세션 (`Karpenter` / `KEDA` / `EKS` 검색)
- KubeCon + CloudNativeCon 발표 영상
- TechWorld with Nana (YouTube): K8s 입문 영상

## 도구

- **k9s**: TUI 기반 클러스터 대시보드 — https://k9scli.io/
- **stern**: 멀티 Pod 로그 tail — https://github.com/stern/stern
- **kubectx / kubens**: 컨텍스트/네임스페이스 빠른 전환 — https://github.com/ahmetb/kubectx
- **kustomize**: 매니페스트 오버레이 — https://kustomize.io/
- **kubeshark**: K8s 트래픽 가시화 — https://kubeshark.co/
- **Lens IDE**: GUI 클러스터 관리 — https://k8slens.dev/

## 커뮤니티

- Kubernetes Slack (#kubernetes-novice 등): https://slack.k8s.io/
- KEDA Slack: https://kubernetes.slack.com/archives/CKZJ36A5D
- AWS EKS GitHub Issues: https://github.com/aws/containers-roadmap/issues
- 한국 K8s 사용자 모임 (Kubernetes Korea Group): https://www.facebook.com/groups/k8skr/
