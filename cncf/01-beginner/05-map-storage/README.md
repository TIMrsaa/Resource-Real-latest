# 05 — 지도: 스토리지 — 상태를 맡길 곳의 지형도

> "컨테이너는 갈아치워도 데이터는 못 갈아치운다" — 스토리지는 클라우드 네이티브에서 가장 보수적이어야 할 카테고리입니다. 이 지도는 세 번째 인터페이스 CSI(CRI·CNI에 이은)를 중심에 놓고, 로고 벽을 역할로 가릅니다: 스토리지 **시스템**(Ceph·MinIO류), 그것을 K8s에서 부리는 **오케스트레이터**(Rook), K8s 네이티브로 지어진 것들(Longhorn·OpenEBS), 그리고 백업(Velero — k8s 36의 그것). eks에서 EBS CSI 드라이버를 쓰기만 했다면, 여기서는 CSI의 사이드카 구조를 열어봅니다.

## 학습 목표

1. CSI가 CRI·CNI와 같은 "교체 가능성의 인터페이스"임을 이해하고, 사이드카 패턴(provisioner/attacher/registrar)을 그립니다
2. 로고를 역할로 가릅니다 — 시스템 vs 오케스트레이터 vs K8s 네이티브 vs 백업 — Rook이 "스토리지가 아니다"를 설명합니다
3. 블록/파일/오브젝트의 3형태와 워크로드 매칭(DB/공유/아카이브)을 압니다
4. kind에 CSI 드라이버를 설치해 PVC→PV 프로비저닝의 전 과정을 관찰합니다
5. "클라우드 관리형 vs 자체 운영"의 판단 축과 데이터 중력(data gravity)을 압니다

## 선행: 01(범례), k8s 중급(PV/PVC/StorageClass), k8s 36(Velero), eks(EBS CSI) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 목록·역할 분류
3. [lab-02-csi-anatomy.md](./lab-02-csi-anatomy.md) — CSI 드라이버 해부: 프로비저닝의 여정
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
