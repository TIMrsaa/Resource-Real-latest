# 이론 — 샤딩 문제, Vitess 아키텍처, 라우팅, 리샤딩, 판단

> **🌱 17세 눈높이 비유: 대형 도서관의 분관 체계**
> - **단일 MySQL** = 책이 다 들어간 한 건물 — 책이 많아지면 건물이 터집니다
> - **샤딩** = 책을 여러 분관으로 나눔 (A-F는 1관, G-M은 2관...)
> - **앱이 샤딩하면** = 이용자가 "내 책이 몇 관?"을 직접 계산 (복잡·실수)
> - **Vitess(VTGate)** = 통합 안내 데스크 — 이용자는 "이 책 주세요"만 하면 데스크가 알아서 맞는 분관에서 가져옵니다
> - **여러 분관에 걸친 검색** = 데스크가 각 분관에 물어서 모아줍니다 (scatter-gather)
> - **리샤딩** = 분관을 늘리며 책을 재배치 — 이용자 모르게 (무중단)
> - **극단적 스테이트풀** = 책(데이터)이 수백 분관에 — 백업·이사·화재 대응이 다 복잡

---

## 1. 샤딩 문제 — 앱이 하면 지옥

```
샤딩 = 데이터를 여러 DB로 수평 분할 (user_id % 100 → 100 샤드)

앱이 샤딩할 때의 복잡성:
  ① 라우팅: 모든 쿼리에 "어느 샤드?" (user_id로 계산)
  ② 크로스 샤드 쿼리: JOIN·집계가 여러 샤드에 걸침 → 직접 구현
  ③ 크로스 샤드 트랜잭션: 2PC 등 직접
  ④ 리샤딩: 샤드 추가 시 앱 수정 + 데이터 이동 + 다운타임
  ⑤ 스키마 변경: 모든 샤드에 적용

→ 애플리케이션 코드가 분산 시스템 코드가 됩니다 (도메인 로직이 묻힘)
```

## 2. Vitess 아키텍처

```
앱 ──MySQL 프로토콜──▶ VTGate ──▶ VTTablet ──▶ MySQL (샤드)
                        │            (샤드당)
                        │
                     라우팅 결정 (VSchema로)

컴포넌트:
  VTGate:    프록시 — 앱에 하나의 MySQL로 보임, 쿼리를 샤드로 라우팅
             (23의 Envoy처럼 프록시, but MySQL 프로토콜)
  VTTablet:  각 MySQL 앞의 에이전트 — 쿼리 관리, 헬스, 백업, 복제
  MySQL:     실제 데이터 (샤드마다 primary + replica)
  Topology:  클러스터 메타데이터 (etcd/ZooKeeper — 21의 etcd처럼)
             어떤 샤드·태블릿이 있나, 누가 primary인가
  VTctld:    관리 (리샤딩·스키마 변경 오케스트레이션)
  VSchema:   샤딩 스키마 (어떤 테이블이 어떻게 샤딩되나)
```

## 3. 쿼리 라우팅 — VSchema와 VIndex

```
VSchema: "이 테이블이 어떻게 샤딩되나"
  keyspace(논리 DB) → 샤딩 여부, 샤딩 키, VIndex

VIndex (Vitess Index): 샤딩 키 → 샤드 매핑
  hash: user_id를 해시 → 균등 분산 (가장 흔함)
  lookup: 별도 테이블로 매핑 (secondary index 샤딩)
  → "user_id로 어느 샤드인지" 계산

라우팅 종류:
  단일 샤드: WHERE user_id = 123 → 그 user_id의 샤드 하나로
  scatter-gather: WHERE created > ... → 모든 샤드에 보내 결과 모음 (비쌈!)
  ★ 샤딩 키를 WHERE에 안 쓰면 scatter (전 샤드 쿼리) → 느림
     → 쿼리 설계가 샤딩 키를 고려해야 (앱이 완전히 투명하진 않습니다)
```

## 4. 리샤딩 — 무중단 데이터 이동

```
문제: 100 샤드가 부족 → 200 샤드로 (데이터 절반씩 이동)
전통(앱 샤딩): 다운타임 + 앱 수정 + 수동 데이터 이동 (악몽)

Vitess 리샤딩:
  1. 새 샤드 생성 (빈)
  2. VReplication: 기존 샤드 → 새 샤드로 데이터 복제 (온라인)
  3. 복제가 따라잡으면 트래픽 전환 (읽기 먼저, 쓰기 나중)
  4. 검증 후 기존 샤드 정리
  → 앱 무중단, Vitess가 오케스트레이션

VReplication: Vitess의 핵심 — 샤드 간 데이터 흐름
  리샤딩, 물질화 뷰, 마이그레이션(다른 DB → Vitess)에 사용
```

## 5. 09의 판단 극대화 — 상태의 무게

```
Vitess = 가장 스테이트풀 (09의 판단 프레임 최대 적용):

관리형 대안?
  Aurora, PlanetScale(Vitess 기반 관리형!), TiDB Cloud 등
  → 대부분 관리형이 낫습니다 (운영 복잡도 회피)

자체 운영 시 (09의 프레임):
  오퍼레이터: Vitess Operator (성숙도 확인)
  스토리지: 각 샤드가 블록 스토리지 (05)
  백업: 샤드별 백업 + Topology 백업 (21의 etcd처럼)
  사람: MySQL + 분산 시스템 + Vitess 3중 지식
  K8s 함정: 각 VTTablet의 안티어피니티, primary 재선출...

운영 복잡도:
  샤드 수백 개 × (primary + replica) = MySQL 인스턴스 수천
  리샤딩·스키마 변경·장애가 전부 분산 스케일
  → "새벽 3시에 이것을 고칠 사람"이 정말 필요 (09)
```

## 6. 판단 — 단일 DB의 벽

```
Vitess가 필요한 경우:
  단일 MySQL의 벽을 실제로 만남 (쓰기 처리량·데이터 크기·운영)
  MySQL 호환이 필수 (기존 앱·생태계)
  초대형 규모 (YouTube·Slack급)

Vitess가 아닌 경우 (대부분):
  단일 DB로 충분 (수직 확장·복제본·캐싱으로 아직 여유)
  관리형이 답 (PlanetScale = Vitess 관리형, Aurora, TiDB Cloud)
  MySQL 호환 불필요 → 다른 분산 DB(TiKV/TiDB — 37, CockroachDB)

★ 35(Dragonfly)와 같은 원칙:
  스케일의 벽을 만났으면, 아니면 오버엔지니어링
  Vitess는 "단일 DB로 안 되는 게 증명된" 조직의 도구
  → 대부분은 관리형 분산 DB로 (운영 복잡도 회피)
```

## 7. 소스/도구에서 확인하기

- Vitess: https://vitess.io/docs — architecture, sharding, resharding
- VReplication: https://vitess.io/docs/reference/vreplication/
- Vitess Operator: https://github.com/planetscale/vitess-operator
- 09(데이터·판단)·05(스토리지)·37(TiKV 대비) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| 푸는 문제? | 단일 MySQL의 벽 — 샤딩을 앱에서 DB 계층으로 |
| 핵심 통찰? | 앱은 하나의 MySQL로 보임, Vitess가 샤딩 흡수(29·03의 추상) |
| 아키텍처? | VTGate(라우팅)·VTTablet(샤드 관리)·MySQL·Topology(etcd)·VSchema |
| 라우팅? | 샤딩 키 있으면 단일 샤드, 없으면 scatter-gather(비쌈) |
| 리샤딩? | VReplication으로 온라인 데이터 이동 → 무중단 |
| 09 판단? | 가장 스테이트풀 — 오퍼레이터·스토리지·사람 3중 지식 최대 |
| 언제? | 단일 DB의 벽 + MySQL 호환 필수 — 대부분은 관리형이 답 |
| 대안? | PlanetScale(Vitess 관리형)·Aurora·TiDB(37)·CockroachDB |
