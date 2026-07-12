# 흔한 함정 5선

## 1. Deployment(replicas>1) + RWO PVC 하나

lab-02 Step 5의 Multi-Attach error. EBS류 RWO 볼륨은 한 노드에만 붙습니다. 선택지: ① 인스턴스마다 자기 디스크가 필요하면 StatefulSet의 volumeClaimTemplates(모듈 19) ② 진짜 공유가 필요하면 EFS(RWX) ③ 애초에 공유 디스크가 아니라 S3/DB로 설계.

## 2. 롤링 업데이트 + RWO = 데드락

기본 RollingUpdate는 새 Pod를 먼저 띄우는데(maxSurge), 새 Pod는 옛 Pod가 쥔 볼륨을 기다리고, 옛 Pod는 새 Pod가 Ready 되길 기다립니다 — 서로 대기. PVC 쓰는 단일 replica 앱은 `strategy: Recreate`(manifests/storage.yaml에 한 이유).

## 3. reclaimPolicy를 모르고 PVC 삭제

`Delete` 정책에서 PVC 삭제 = **EBS와 데이터 영구 삭제.** "정리 좀 했어요"가 데이터 손실 사고가 됩니다. 운영 DB류는 `Retain` + 스냅샷 백업(eks 파트 10, 모듈 36). 반대로 학습 환경에서 Retain을 쓰면 고아 EBS가 쌓여 과금 — 환경에 맞게.

## 4. Immediate 바인딩 + AZ 불일치

`volumeBindingMode: Immediate`(옛 기본값)면 PVC 생성 즉시 임의 AZ에 볼륨이 생기고, Pod가 다른 AZ에 스케줄되면 영원히 Pending. 멀티 AZ 클러스터의 StorageClass는 **WaitForFirstConsumer**가 표준.

## 5. "용량 줄여야지" — 축소는 없습니다

PVC 확장은 가능, **축소는 불가능**(파일시스템 축소의 위험성 때문에 스펙 자체가 없음). 줄이려면 새 PVC 만들어 데이터 이사. 처음에 "넉넉하게 1TB"를 신청하는 습관이 비싼 이유.

## 실무 사고 사례

> 네임스페이스를 통째로 지워 환경을 정리한 팀. 그 안의 PVC들이 같이 삭제됐고 StorageClass가 Delete 정책 → 운영 데이터 EBS까지 연쇄 삭제. EBS 스냅샷도 안 만들어둔 상태였습니다. 교훈: ① 운영 데이터는 Retain + 자동 스냅샷 ② `kubectl delete namespace`는 안에 뭐가 있는지 보고 누르는 버튼입니다 (`kubectl get all,pvc -n X` 먼저).
