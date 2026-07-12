# 03. Config & Storage — ConfigMap, Secret, PV/PVC, StatefulSet

## 학습 목표

앱 설정과 데이터를 K8s스럽게 다루는 법을 배운다.

- **ConfigMap / Secret** — 코드와 설정 분리 (12-factor)
- **Volume / PV / PVC** — Pod 라이프사이클을 넘어서는 데이터 저장
- **StatefulSet** — 데이터를 가진 워크로드 (DB, Kafka, Redis 등)

## 선행 지식

- 모듈 02 완료
- EKS 클러스터에 EBS CSI Driver 가 기본 설치되어 있어야 함
  ```bash
  kubectl get csidrivers ebs.csi.aws.com
  ```
  없으면:
  ```bash
  eksctl create addon --cluster eks-study --name aws-ebs-csi-driver \
    --service-account-role-arn arn:aws:iam::<acct>:role/AmazonEKS_EBS_CSI_DriverRole
  ```
  (Part 2에서 IRSA로 더 자세히 다룸. 본 모듈은 노드 IAM Role에 EBS 권한이 있다고 가정)

## 진행 순서

1. [theory.md](./theory.md) — 이론 (20분)
2. [lab-01-configmap-secret.md](./lab-01-configmap-secret.md) — ConfigMap/Secret 마운트 (25분)
3. [lab-02-pv-pvc.md](./lab-02-pv-pvc.md) — PVC + EBS 사용 (30분)
4. [lab-03-statefulset.md](./lab-03-statefulset.md) — StatefulSet으로 Redis (30분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)
7. `bash cleanup.sh`

## 소요 시간

총 **약 2 ~ 2.5시간**.

## 예상 비용

EBS 볼륨 사용 (gp3, 1~5 GB) → 학습 1시간 기준 약 0.01 USD. 무시 가능.
**단, lab 끝나고 PVC 삭제 → EBS 볼륨까지 삭제되는지 확인 필수.**

## 다음 모듈

→ [04-rbac-helm](../04-rbac-helm/)
