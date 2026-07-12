# 이론 — Velero의 해부, 볼륨 정합성, RTO/RPO 티어링

> **🌱 17세 눈높이 비유: 노트북이 죽기 전에 해두는 일**
> 과제 마감 전날의 백업 전략:
> - **타임머신 전체 복원**(etcd 스냅샷) = 노트북을 통째로 어제 상태로 — 어제 이후 깐 앱도 같이 사라집니다. 게다가 학교 노트북(EKS)이면 이 기능은 관리실만 만질 수 있습니다
> - **클라우드 드라이브에 과제 폴더만**(Velero) = "실수로 지운 과제 폴더 하나만" 골라 되살립니다 — 나머지는 그대로
> - **폴더 목록 따로, 대용량 파일 따로**(리소스 vs 볼륨) = 목차는 가볍게, 동영상 원본은 다른 방식으로
> - **RPO** = "몇 시간 치를 다시 써도 되나" → 자동 저장 주기. **RTO** = "제출까지 몇 시간 남았나" → 복구 방법
> - 그리고 진짜 고수는 **제출 전에 복원 리허설**을 합니다 — 드라이브 로그인이 풀려 있는 걸 그때 발견하면 늦으니까

---

## 1. Velero 해부 — 우리가 이미 아는 부품들

Velero는 새 개념이 아니라 **모듈 30에서 만든 Operator 패턴의 상용 제품**입니다:

```
velero CLI ──생성──▶ Backup/Restore/Schedule CRD
                          │ watch
                     Velero 컨트롤러 (velero ns의 Deployment)
                          │
        ┌─────────────────┴──────────────────┐
        ▼ 리소스                              ▼ 볼륨 데이터
  API 서버에서 객체 수집                  ① CSI/EBS 스냅샷 (VolumeSnapshotLocation)
  (--include-namespaces, --selector)     ② File System Backup — Kopia
        │                                    (Pod 볼륨을 파일 단위 복사)
        ▼
  tarball → S3 (BackupStorageLocation)
```

- **BSL**(BackupStorageLocation) = "백업이 사는 곳"(S3 버킷) — 이것이 `Available`이어야 모든 게 시작됩니다
- 권한: S3 읽기/쓰기 + EBS 스냅샷 생성 = IAM — Pod Identity/IRSA(08, eks 09)의 실전 소비자
- Schedule CRD는 cron 표현식(20)으로 Backup을 찍어내는 공장

## 2. 백업의 클러스터 독립성 — DR의 지렛대

S3에 올라간 백업은 **어느 클러스터의 소유도 아닙니다.** 새 클러스터에 Velero를 붙이고 같은 BSL을 바라보게 하면 restore가 됩니다. 이 하나의 성질에서 세 가지 능력이 나옵니다:

| 시나리오 | 방법 |
|----------|------|
| DR | 죽은 클러스터 대신 새 클러스터에 restore |
| 마이그레이션 | 다른 리전/버전 클러스터로 이사 |
| 클론 | prod 백업을 staging에 restore (마스킹 주의) |

모듈 35의 "클러스터 Blue/Green" 전략이 실제로 올라타는 토대가 이것입니다.

## 3. 볼륨 백업 — 두 방식과 정합성이라는 함정

| | CSI/EBS 스냅샷 | File System Backup (Kopia) |
|---|---|---|
| 원리 | 블록 스토리지 스냅샷 API | Pod 안 볼륨을 파일 복사해 S3로 |
| 속도 | 빠름 (증분) | 느림 (파일 순회) |
| 이식성 | **같은 클라우드/리전에 묶임** | 리전/클라우드 무관 — 어떤 볼륨이든 |
| 지정 | 기본 (CSI 연동) | Pod annotation `backup.velero.io/backup-volumes` |

### 정합성 — "찍는 순간 쓰고 있었다면"

쓰기 중인 볼륨을 그대로 찍으면 절반만 쓰인 데이터(torn write)가 박제될 수 있습니다 — 일반 파일은 대개 견디지만 **DB는 복구 후 기동 실패**로 나타납니다. 층위별 대응:

```
1층  backup hook — 백업 직전 Pod 안에서 명령 실행 (pre: DB flush/fsfreeze → post: 해제)
2층  애플리케이션 백업 병행 — pg_dump, 논리 복제, WAL 아카이브
     → 진짜 DB의 1순위는 2층입니다. Velero는 "클러스터 리소스 + 일반 볼륨" 담당
```

## 4. RPO/RTO — 두 숫자가 전략을 고릅니다

```
비용 ▲
     │ ④ 액티브-액티브 (멀티리전 동시 운영)      RPO≈0, RTO≈0
     │ ③ 웜 스탠바이 (축소판 상시 가동)          RPO 분, RTO 분
     │ ② 파일럿 라이트 (핵심만 최소 가동)        RPO 분~시간, RTO 시간
     │ ① 백업/복구 (Velero + 새로 짓기)          RPO=백업주기, RTO=시간
     └───────────────────────────────▶ 요구 엄격도
```

핵심 규율은 **티어링**입니다 — 서비스마다 RPO/RTO를 먼저 적고, 그 숫자가 고르는 전략을 줍니다. 결제 서비스에 ①은 도박이고, 사내 분석에 ④는 낭비입니다. "전사 표준 DR 하나"는 설계가 아니라 회피입니다.

## 5. Game Day — 백업의 완성 조건

백업은 만든 날이 아니라 **복구된 날** 완성됩니다. 분기마다:

```
1. 격리 환경(별도 ns/클러스터)에 실제 restore
2. RTO 실측 — restore 시작~서비스 정상까지 (계획값과 비교)
3. RPO 검증 — 복구 데이터의 최신성
4. 막힌 곳 기록 → runbook 반영 (권한 만료, 절차 구멍이 여기서 드러납니다)
```

## 6. 소스/도구에서 확인하기

- Velero: https://github.com/vmware-tanzu/velero — `pkg/backup/`(수집 파이프라인), `pkg/restore/`(재생성 순서 로직)
- backup hooks: https://velero.io/docs/main/backup-hooks/
- AWS DR 백서(전략 4단계의 원전): https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/

## 요약 카드

| 질문 | 답 |
|------|----|
| Velero의 정체? | Backup/Restore/Schedule CRD + 컨트롤러 — 30의 Operator 패턴 |
| etcd 스냅샷과의 분업? | 전체 되감기(AWS 몫) vs 선택 복구(우리 몫) |
| DR·이사·클론의 공통 토대? | 백업의 클러스터 독립성 (S3 = 중립지대) |
| 볼륨 2방식? | EBS 스냅샷(빠름/종속) vs Kopia(느림/이식) |
| DB 백업의 1순위? | 애플리케이션 백업 (Velero hook은 보조) |
| RPO/RTO가 정하는 것? | 백업 주기 / 복구 방식 — 서비스별 티어링 |
| 백업의 완성? | Game Day에서 복구가 증명된 날 |
