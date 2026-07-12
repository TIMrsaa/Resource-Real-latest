# Lab 01 — 관측 전수 조사: 격자에 채워 넣기

landscape의 Observability 대분류를 뽑아 신호×단계 격자로 재배치합니다.

전제: 01 lab-01의 landscape.yml.

## Step 1. Observability 칸 전수

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
for cat in data['landscape']:
    if 'Observability' not in cat['name']: continue
    for sub in cat.get('subcategories', []):
        items = sub.get('items', [])
        cncf = [i for i in items if i.get('project')]
        print(f"\n=== {sub['name']} — {len(items)}개 (CNCF {len(cncf)}) ===")
        for it in sorted(cncf, key=lambda x: x['name'].lower()):
            print(f"{it['project']:12s} {it['name']}")
EOF
```

예상: Monitoring에 Prometheus·Thanos, Logging에 Fluentd, Tracing에 Jaeger·OpenTelemetry 등 — 서브카테고리가 대략 신호 축과 일치합니다. 그리고 이 칸은 **상용 로고의 밀도가 최고 수준**(APM 벤더 전원 입주)입니다 — CNCF 필터의 가치가 가장 큰 칸.

## Step 2. 격자 배치 — 행(신호)과 열(단계)을 함께

```bash
python3 <<'EOF'
grid = {
 ('메트릭','수집·저장·질의'): ['Prometheus (Graduated)'],
 ('메트릭','장기 저장'):      ['Thanos (Incubating)','(Mimir — Grafana·비CNCF)'],
 ('로그','전송·가공'):        ['Fluentd (Graduated)','Fluent Bit'],
 ('로그','저장·질의'):        ['(Loki — 비CNCF)','(ES/OpenSearch — 외부)'],
 ('트레이스','저장·질의·UI'): ['Jaeger (Graduated)','(Tempo — 비CNCF)'],
 ('전 신호','수집·전송 표준'): ['OpenTelemetry (Incubating — 규모 2위)'],
 ('전 신호','화면'):          ['(Grafana — 비CNCF·AGPL)'],
}
for (row, col), items in grid.items():
    print(f"[{row:6s} × {col}]")
    for i in items: print(f"   {i}")
print("\n→ 괄호 = CNCF 밖. '표준 스택'의 화면·로그 저장이 밖에 있다는 것이 이 지도의 특징")
EOF
```

✅ 격자를 채우고 나면 대표 혼동들이 무의미해집니다: "Loki vs Prometheus"(다른 행), "OTel vs Jaeger"(다른 열 — 수집 vs 저장).

## Step 3. 대통일의 증거 — OTel의 규모를 데이터로

```bash
# OpenTelemetry의 저장소 수와 활동 — "K8s 다음"의 실감
gh api "orgs/open-telemetry/repos?per_page=100" --jq 'length'
gh api "repos/open-telemetry/opentelemetry-collector/releases?per_page=3" \
  --jq '.[] | "\(.tag_name)  \(.published_at)"'
echo "→ devstats.cncf.io에서 프로젝트별 기여자 수 비교 — OTel의 위치 확인"
```

## Step 4. 비CNCF 주민의 소견서 — Grafana 축 조정 연습

```bash
cat <<'EOF'
Grafana/Loki/Tempo 채택 시 01의 소견서에서 조정되는 항목:
- 유지보수자 다양성 → "단일 회사(Grafana Labs) 소유"가 전제 — 다양성 대신
  회사의 지속성·오픈소스 정책 이력을 봅니다
- 라이선스 → AGPL(2021 전환 이력 있음!) — 우리 사용 형태의 저촉 여부 법무 확인
- 상표·자산 → 회사 소유 — 01의 재단 보험 없음. 대안 경로(포크·교체 비용) 평가
→ "쓰지 마라"가 아니라 "리스크 축이 다름을 명시하고 채택" — 관측의 화면 대안이
  마땅치 않은 현실도 판단의 일부입니다
EOF
```

## Step 5. 산출물

```markdown
# 관측 지도 — 조사 결과 (조사일: ____)
- 우리 스택의 격자: 메트릭 ___ / 로그 ___ / 트레이스 ___ / 수집 ___ / 화면 ___
- OTel 수렴 상태: 트레이스 __ / 메트릭 __ / 로그 __ (신호별 도입 여부)
- 비CNCF 의존: ___ (라이선스·소유 리스크 명시)
- 심층 예약: 11(Prometheus) 12(OTel) 13(Jaeger) 14(Fluentd)
```

## 정리

landscape.yml 유지.
