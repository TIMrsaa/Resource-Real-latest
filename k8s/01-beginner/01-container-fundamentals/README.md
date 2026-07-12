# 01 — 컨테이너의 정체 (Container Fundamentals)

> K8s를 배우기 전에 "컨테이너가 실제로 무엇인지"를 커널 수준에서 이해합니다.
> 이걸 건너뛰면 K8s의 모든 개념이 마법처럼 보이고, 이걸 이해하면 전부 당연해집니다.

## 학습 목표

1. 컨테이너 = "리눅스 커널 기능(namespace + cgroup)으로 격리된 평범한 프로세스"임을 직접 확인합니다
2. 컨테이너 이미지의 레이어 구조와 OCI 표준을 이해합니다
3. 이미지를 직접 빌드하고 Amazon ECR에 푸시합니다
4. "VM vs 컨테이너" 차이를 정확히 설명할 수 있습니다

## 선행 지식

- 리눅스 기본 명령 (`ls`, `ps`, `cd`)
- 없어도 됨: Docker/K8s 경험

## 준비물

| 항목 | 용도 | 비용 |
|------|------|------|
| Docker Desktop (WSL2) 또는 EC2 t3.small | 컨테이너 실행/관찰 | 로컬 무료 / EC2 약 $0.026/h |
| AWS CLI + ECR | 이미지 푸시 실습 | ECR 스토리지 $0.10/GB·월 (실습 후 삭제) |

## 진행 순서

1. [guide.md](./guide.md) — 학습 전략
2. [theory.md](./theory.md) — 이론: namespace, cgroup, 이미지 레이어, OCI
3. [lab-01-process-isolation.md](./lab-01-process-isolation.md) — 컨테이너가 프로세스임을 직접 확인
4. [lab-02-image-build-ecr.md](./lab-02-image-build-ecr.md) — 이미지 빌드 + 레이어 관찰 + ECR 푸시
5. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md)
6. `bash cleanup.sh` — ECR 리포지토리 정리

소요 시간: 이론 1.5h + 실습 2h

## 다음 모듈을 위한 준비 — 공유 EKS 클러스터

모듈 02부터는 EKS 클러스터가 필요합니다. 미리 만들어 두려면:

```bash
eksctl create cluster --name k8s-study --region ap-northeast-2 \
  --version 1.36 \
  --nodegroup-name workers --node-type t3.medium --nodes 2 \
  --spot --managed
# 약 15~20분 소요. control plane $0.10/h + spot 노드 2대
```

> 학습 안 하는 날엔 `eksctl delete cluster --name k8s-study --region ap-northeast-2` 로 삭제할 것.
