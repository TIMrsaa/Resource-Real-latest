# 02 — eksctl과 클러스터 생성: 선언형으로 인프라를

> 클러스터 생성을 "마법의 한 줄"에서 **읽고 수정할 수 있는 선언(설정 파일)**으로 바꿉니다. 그리고 kubectl이 EKS에 인증되는 진짜 경로(get-token→STS)와, 사람/역할에게 클러스터 권한을 주는 표준(access entries)을 해부합니다.

## 학습 목표

1. eksctl 설정 파일(ClusterConfig)을 읽고 작성합니다 — 생성의 선언형화
2. eksctl 뒤의 CloudFormation 스택을 확인합니다 (무엇이 만들어졌나)
3. kubeconfig의 exec 플러그인과 `aws eks get-token`의 동작(STS 서명)을 이해합니다
4. **access entries**로 IAM 주체에게 클러스터 권한을 부여합니다 (aws-auth ConfigMap의 후계)
5. IAM(인증) ↔ RBAC(인가)의 연결 고리를 그립니다 (k8s 11의 완성)

## 선행: 모듈 01, k8s 파트 11(RBAC) · 환경: 공유 EKS + AWS CLI/eksctl

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-clusterconfig-auth.md](./lab-01-clusterconfig-auth.md) — 설정 파일, CFN, get-token 해부
3. [lab-02-access-entries.md](./lab-02-access-entries.md) — 동료에게 권한 주기 (실전 시나리오)
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
