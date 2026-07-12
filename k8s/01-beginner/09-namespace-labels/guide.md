# 학습 가이드 — "무엇이 격리되고 무엇이 안 되는지"가 전부

## 이 모듈의 함정 주의보

Namespace라는 단어 때문에 "방화벽 쳐진 독립 공간"을 상상하기 쉽습니다. 실제로는:

| 격리됨 ✅ | 격리 안 됨 ❌ |
|----------|--------------|
| 이름 충돌 (ns마다 같은 이름 가능) | **네트워크** — 다른 ns의 Pod/Service에 그냥 접속됨 |
| RBAC 권한 경계 (모듈 11) | 노드 자원 (쿼터를 안 걸면) |
| ResourceQuota 적용 범위 | 클러스터 리소스 (Node, PV, StorageClass...) |

**"dev 네임스페이스에서 prod DB로 접속되더라"** 는 버그가 아니라 기본 동작입니다. 네트워크 격리는 NetworkPolicy(모듈 15)로 따로 겁니다. 이 구분만 가져가도 이 모듈은 성공.

## Label은 K8s의 조인(join) 키

지금까지 본 모든 연결이 라벨이었습니다: Service→Pod, Deployment→RS→Pod, (앞으로) NetworkPolicy→Pod, affinity→Node. RDB로 치면 **외래키가 전부 라벨**인 시스템. 그래서 라벨 설계 = 스키마 설계이고, 표준 라벨 세트가 존재합니다 — lab-02에서 손에 익힙니다.

## Label vs Annotation 한 줄 구분

- **Label**: 선택(select)당하기 위한 것 — 짧고, 검색 가능, 시스템이 사용
- **Annotation**: 메모 — 길어도 됨, 검색 불가, 사람/도구가 읽음 (배포 시각, 담당자, 컨트롤러 설정값)

"selector로 찾을 일이 있는가요?" — yes면 label, no면 annotation.
