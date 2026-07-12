# 흔한 함정 5선

## 1. DB를 EFS에

"RWX니까 DB도 공유하면 HA?" — 이중 오류입니다: ① DB 파일의 동시 쓰기는 RWX가 아니라 DB 복제로 푸는 문제(k8s 19) ② EFS의 지연/랜덤IO 특성이 DB와 상극(lab-02 Step 5의 숫자). DB는 EBS+StatefulSet 또는 관리형(RDS)으로.

## 2. allowVolumeExpansion 없는 StorageClass

기본값이 false라 — 디스크 풀 새벽에 patch가 거부되고, 그제야 "마이그레이션으로 늘려야" 하는 대공사가 됩니다. **모든 StorageClass에 allowVolumeExpansion: true를 기본으로** — 비용 0의 보험입니다. (확장은 늘리기만, 축소 불가도 기억)

## 3. 스냅샷 무한 적재

"보험"으로 찍은 스냅샷이 정리 정책 없이 수백 개 — 증분이라도 쌓이면 비용이고, 막상 복원하려니 "어느 게 정상 시점인지" 모릅니다. 스냅샷엔 라벨/설명(무엇의 언제, 왜) + TTL/정리 루틴 — 정책적 백업은 Velero 스케줄(k8s 36)이나 DLM으로 일원화.

## 4. EFS 보안그룹/마운트타겟 누락

PVC는 Bound인데 Pod이 마운트에서 영원히 멈춤 — 원인 1순위: 노드 SG에 NFS(2049) 인바운드 부재 또는 그 AZ에 mount target 없음. 증상은 Pod 이벤트의 mount timeout. EFS 문제의 절반은 K8s가 아니라 **네트워크 배선**(SG/MT)입니다.

## 5. S3 CSI를 만능 파일시스템으로

POSIX 기대(잠금, 이어쓰기, rename, mmap)를 가진 앱을 S3 CSI에 — 미묘하게 깨지거나 성능이 무너집니다. +작은 파일 수백만 GET의 요청 과금. S3 CSI는 "대용량 읽기 파이프라인"용 특수 도구 — 일반 파일 요구는 EFS, 객체 요구는 SDK 직접이 정도(正道).

## 실무 사고 사례

> 이미지 서버를 3 replica로 늘리며 업로드 디렉터리를 EBS PVC 그대로 둔 팀 — 두 번째 Pod부터 Multi-Attach 에러로 Pending(k8s 08의 그 에러를 운영에서). 급한 김에 hostPath로 우회했다가 노드마다 파일이 달라 "업로드한 이미지가 가끔 404". 결국 EFS로 이주 — 그런데 이번엔 mount target을 2개 AZ에만 만들어 세 번째 AZ 노드의 Pod이 마운트 실패. 전 AZ에 MT 생성으로 종결. 교훈: ① 다중 Pod 공유 = 처음부터 RWX(EFS) 설계 ② hostPath 우회는 더 큰 미스터리를 만든다 ③ EFS는 "전 AZ 배선"까지가 설치입니다.
