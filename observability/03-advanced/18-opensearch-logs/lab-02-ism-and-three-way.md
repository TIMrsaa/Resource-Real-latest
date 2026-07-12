# Lab 02 — ISM 수명 관리와 3파전 최종 판단

> 인덱스의 노화(hot→delete)를 ISM 정책으로 자동화하고, 로그 저장소 3파전을 사용 패턴 기준으로 최종 정리합니다. advanced 트랙(AWS 관측)의 마무리입니다.

## 0. 준비 (lab-01 이어서)

```bash
kubectl -n logging port-forward svc/opensearch 9200:9200 &
sleep 3
```

## 1. ISM 정책 — 노화의 자동화

실습용으로 시간을 압축한 정책(실전은 일/월 단위):

```bash
curl -s -X PUT localhost:9200/_plugins/_ism/policies/logs-lifecycle \
  -H 'Content-Type: application/json' -d '{
  "policy": {
    "description": "hot -> warm(replica 0, read only) -> delete",
    "default_state": "hot",
    "states": [
      { "name": "hot",
        "actions": [],
        "transitions": [{ "state_name": "warm", "conditions": { "min_index_age": "10m" } }] },
      { "name": "warm",
        "actions": [ { "read_only": {} } ],
        "transitions": [{ "state_name": "delete", "conditions": { "min_index_age": "30m" } }] },
      { "name": "delete",
        "actions": [ { "delete": {} } ],
        "transitions": [] }
    ],
    "ism_template": [{ "index_patterns": ["logs-app-*"], "priority": 100 }]
  }
}'

# 새 인덱스부터 적용 — 날짜를 바꿔 새 인덱스 유도 (Fluent Bit Index 수정) 또는:
curl -s -X POST localhost:9200/_plugins/_ism/add/logs-app-* \
  -H 'Content-Type: application/json' -d '{ "policy_id": "logs-lifecycle" }'

# 상태 관찰
curl -s localhost:9200/_plugins/_ism/explain/logs-app-* | python3 -m json.tool | grep -E '"state"|"index"' | head -6
# "state": "hot" → (10분 후) "warm" → (30분 후) 인덱스 소멸
```

**관찰** — 시간이 지나며 인덱스가 스스로 read_only(warm)가 되고 결국 삭제됩니다. 실전 정책은 여기에 warm 노드 이동·레플리카 축소·(AWS) UltraWarm/cold_migration·스냅샷(S3)이 들어갑니다 — **저장 단가가 노화 계단을 따라 내려가는 구조**. 수명 정책 없는 OpenSearch는 "디스크가 차서 죽는 예약"입니다(pitfalls 사고).

## 2. AWS 관리형에서의 대응물

```
Amazon OpenSearch Service:
  hot: 데이터 노드 (인스턴스 타입·수 = 용량 설계는 우리 몫)
  UltraWarm: S3 기반 웜 계층 (조회 가능, 단가↓)
  cold storage: 더 싼 보관 (붙였다 뗐습니다)
  ISM 정책으로 계층 간 자동 이동
OpenSearch Serverless: OCU 자동 확장 — 용량 설계 부담↓, 단가 모델 다름
→ "관리형인데 설계는 남는다"(13~15의 결론)의 최대 사례:
  샤드 전략·매핑·ISM은 Serverless가 아닌 한 우리 몫
```

## 3. 3파전 최종 판단 — 사용 패턴 문진표

자기 조직에 다음을 묻고 저장소를 배정하세요:

```
문진 ① 주 조사 패턴은?
  "namespace·app으로 좁혀 최근 에러를 본다" → Loki (라벨 조사)
  "복합 조건·풀텍스트·집계로 탐색한다"     → OpenSearch
  "AWS 콘솔·알람과 통합해 가볍게"          → CW Logs

문진 ② 볼륨과 보존은?
  대량 + 장기 + 검색 필요        → OpenSearch + ISM (비용 설계 전제)
  대량 + 장기 + 검색 거의 불필요  → S3 (+Athena) — 색인 값을 내지 마세요
  중소량 + 단기                  → Loki/CW 어느 쪽이든

문진 ③ 운영 여력은?
  없음        → CW Logs (완전 관리) 또는 OpenSearch Serverless
  가벼움 가능  → Loki (단일 바이너리~중간)
  전담 가능    → 자체 OpenSearch (최중량 — 정말 필요할 때만)

문진 ④ 보안·감사(SIEM) 요구가 있나요?
  있음 → OpenSearch가 사실상 기본 후보 (분석력·생태)

실전 조합 예 (patterns → copy 배선, 07):
  K8s 앱 조사: Loki(단기) 또는 CW
  audit·보안: OpenSearch (ISM 90일+)
  전체 원본: S3 (Athena — 규정·재처리용)
  → 06의 tag 라우팅 + 07의 copy가 이 조합의 구현 수단이었습니다 —
    intermediate에서 배운 파이프라인이 설계의 자유도였던 것
```

## 4. advanced 트랙 회고 — AWS 관측 스택 완성도

```
13: CW Logs·Container Insights — 로그 기본 + 요금의 물리
14: AMP — 메트릭 장기 저장 (절단선: 수집은 우리, 저장은 AWS)
15: AMG — 화면·SSO·IAM 통합
16: ADOT — 수집 한 번, 목적지 셋
17: X-Ray — AWS 구간까지 잇는 트레이스 + 조사 동선
18: OpenSearch — 전문 검색·분석 + 3파전 결론

관통 결론: "AWS는 물리를 맡고, 규약은 남는다"
  요금표 읽기(13)·절단선과 평가 주체(14)·as code(15)·
  접합부 규약(16)·공백의 목록화(17)·색인의 절제(18)
→ 오픈소스(06~12)와 관리형(13~18) 양쪽을 알면
  혼합·전환·협상이 전부 가능해집니다 — 이것이 이 트랙의 목적이었습니다
```

## 5. SIGNALS-MAP 최종 갱신 (과제)

```
로그 저장소 줄 완성:
  선택지: Loki(라벨 조사) / OpenSearch(전문·분석, ISM) / CW(AWS 통합) / S3(아카이브)
  우리의 배정: (자기 조직 문진 결과를 기록)
  배선: Fluent Bit tag 라우팅 + Fluentd copy (06·07)
갱신 로그: "18 수료 — AWS 트랙 완료, 저장소 3파전 결론"
```

## 6. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name opensearch
rm -f /tmp/fb-os.yaml
# AWS 경로를 썼다면: 도메인 삭제 필수! (시간당 과금)
```

## 정리

- ISM = 노화의 자동화 (hot→warm→delete) — 없으면 디스크가 차서 죽는 예약
- AWS 관리형에서도 샤드·매핑·ISM 설계는 남습니다 (Serverless가 일부 흡수)
- 3파전은 문진으로: 조사 패턴·볼륨/보존·운영 여력·SIEM 요구 — 실전은 조합(copy 배선)
- 검색 필요 없는 보관에 색인 값을 내지 마세요 — S3가 그 자리
- **★ advanced 수료: 오픈소스와 관리형 양쪽을 알면 혼합·전환·협상이 가능합니다 — "AWS는 물리, 규약은 우리"**
