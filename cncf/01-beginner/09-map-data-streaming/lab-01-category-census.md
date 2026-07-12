# Lab 01 — 데이터·스트리밍 전수 조사와 스테이트풀 판단 프레임 적용

전수 목록을 세 부류로 가르고, 실제 후보 하나에 판단 프레임(theory §4)을 돌려봅니다.

전제: 01 lab-01의 landscape.yml.

## Step 1. 관련 서브카테고리 전수

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
kw = ['database','streaming','messaging','key-value','coordination']
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        if not any(k in sub['name'].lower() for k in kw): continue
        items = sub.get('items', [])
        cncf = [i for i in items if i.get('project')]
        print(f"\n=== {cat['name']} / {sub['name']} — {len(items)}개 (CNCF {len(cncf)}) ===")
        for it in sorted(cncf, key=lambda x: x['name'].lower()):
            print(f"{it['project']:12s} {it['name']}")
EOF
```

예상: etcd·TiKV·Vitess(graduated), NATS·CloudEvents(graduated), Strimzi(incubating) 등 + 상용 DB 로고 다수.

## Step 2. 세 부류 + 모델 축 분류

```bash
python3 <<'EOF'
groups = {
 'K8s의 심장 (선택 아님)': [('etcd (Graduated)','Raft KV — 선형화 읽기·watch·lease')],
 '메시징 — 큐':            [('NATS core (Graduated)','초경량 fire-and-forget'),('RabbitMQ*','AMQP·비CNCF')],
 '메시징 — 스트림':        [('NATS JetStream','같은 NATS의 스트림 모드!'),('Strimzi→Kafka (Incubating)','오퍼레이터+시스템'),('Pulsar*','Apache — 저장/서빙 분리')],
 '이벤트 표준':            [('CloudEvents (Graduated)','봉투 형식 — 브로커 중립')],
 '분산 DB':                [('TiKV (Graduated)','분산 트랜잭션 KV'),('Vitess (Graduated)','MySQL 수평 샤딩')],
}
for g, items in groups.items():
    print(f"\n[{g}]")
    for n, d in items: print(f"   {n:32s} {d}")
print("\n→ 'NATS vs Kafka'는 모드를 밝혀야 성립: core(큐) vs Kafka(스트림)는 층 혼동")
EOF
```

## Step 3. 판단 프레임 실행 — 가상 후보로 연습

```bash
cat <<'EOF'
# 시나리오: "이벤트 파이프라인이 필요합니다. Kafka를 K8s에 올릴까요?"
① 관리형? → MSK(AWS)가 있습니다. 쓸 수 있는가요?
     쓸 수 있다면 증명 책임은 "K8s에 올리자"는 쪽에 (운영 위험 대비 이득)
     못 쓴다면(온프레·비용·주권) → ②
② 오퍼레이터 Level? → Strimzi의 문서에서 백업·복구·롤링 업그레이드 범위 확인
     kubectl explain kafka.spec 로 CRD가 무엇까지 선언하는지 (L2? L3?)
③ 스토리지? → Kafka는 블록(RWO)·고IOPS. 05의 3형태 매칭 + 스냅샷·복원 리허설
④ 사람? → 브로커 리밸런싱·ISR·언더레플리케이션을 새벽에 읽을 사람
⑤ K8s 함정? → 브로커 Pod의 안티어피니티(AZ 분산), PDB, 노드 드레인 = 페일오버
결론 템플릿: "관리형 __ 이므로 __ 를 선택. 오퍼레이터 L__ 이므로 __ 는 우리 몫."
EOF
```

✅ 이 프레임의 출력은 "무엇을 쓴다"가 아니라 **"무엇이 우리 몫으로 남는다"**의 명시다 — 그것이 스테이트풀 결정의 정직한 형식.

## Step 4. 오퍼레이터 성숙도 실측

```bash
# Strimzi의 CRD가 무엇을 선언 대상으로 삼는지 = 자동화 범위의 지표
gh api repos/strimzi/strimzi-kafka-operator --jq '.description'
gh api "repos/strimzi/strimzi-kafka-operator/releases?per_page=3" --jq '.[] | "\(.tag_name)  \(.published_at)"'
echo "→ 릴리스 노트에서 'rolling update', 'backup', 'rebalance'(Cruise Control) 키워드를 찾아"
echo "   Capability Level을 추정하세요 (08의 채점표)"
```

## Step 5. etcd 특별 취급 확인

```bash
cat <<'EOF'
etcd는 이 지도에서 유일하게 '채택 판단'이 없는 프로젝트입니다 — 이미 쓰고 있습니다.
확인할 것은 채택이 아니라 운영 지표:
  - wal_fsync_duration_seconds (디스크 지연 — p99가 25ms를 넘으면 경보)
  - etcd_server_leader_changes_seen_total (리더 교체 = 불안정 신호)
  - db_total_size_in_bytes (컴팩션·디프래그 필요 시점)
  - 백업: etcdctl snapshot save — k8s 36의 그 백업
→ lab-02에서 watch·lease를 직접 만지고, 심층 21에서 Raft·컴팩션까지
EOF
```

## Step 6. 산출물

```markdown
# 데이터·스트리밍 지도 — 조사 결과 (조사일: ____)
- 우리 스테이트풀 인벤토리: DB ___ / 메시징 ___ / 캐시 ___
- 각각 관리형/자체운영 여부와 그 근거: ___
- 자체 운영 중인 것의 오퍼레이터 Level과 "우리 몫" 목록: ___
- etcd 운영 지표 대시보드 존재 여부: ___ (없으면 최우선 과제)
- 심층 예약: 21(etcd) 36(Vitess) 37(TiKV) 38(NATS) 40(Strimzi·CloudEvents)
```

## 정리

landscape.yml 유지.
