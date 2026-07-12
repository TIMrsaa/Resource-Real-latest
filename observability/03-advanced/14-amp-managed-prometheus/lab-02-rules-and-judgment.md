# Lab 02 — AMP 규칙·요금 계산·판단 정리

> AMP 쪽에 recording rule을 올려 평가 위치의 선택지를 확인하고, 샘플 요금을 직접 계산해 카디널리티·간격의 감각을 요금으로 번역하고, "자체 vs AMP vs Thanos/Mimir" 판단을 정리합니다.

## 0. 준비 (lab-01 이어서)

## 1. AMP 관리형 규칙 — 평가를 원격에서

```bash
# Prometheus 형식 그대로의 룰 파일
cat > /tmp/amp-rules.yaml <<'EOF'
groups:
  - name: cluster.record
    rules:
      - record: cluster:node_cpu:avg_idle
        expr: avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))
EOF

# 룰 네임스페이스로 업로드
aws amp create-rule-groups-namespace --region $REGION \
  --workspace-id $WS_ID --name curriculum-rules \
  --data fileb:///tmp/amp-rules.yaml

sleep 120   # 평가 대기
awscurl --service aps --region $REGION \
  "${AMP_ENDPOINT}api/v1/query?query=cluster:node_cpu:avg_idle" | head -c 300
# 결과가 나오면: ★ AMP가 원격에서 룰을 평가해 새 시계열을 만들고 있습니다
```

**평가 위치의 선택** — 하이브리드(로컬 Prometheus 유지)면 룰을 로컬(08·10)에서 평가하는 것이 단순하고, 에이전트 모드면 평가 주체가 없으므로 AMP 룰이 필수입니다. 알림도 마찬가지: AMP alerting rule → 관리형 Alertmanager → SNS 경로가 에이전트 모드의 짝입니다. **원칙: 평가 주체를 한 곳으로 — 양쪽에 중복 정의하면 08 사고(정의 분기)의 재연입니다.**

## 2. 요금 계산 훈련 — 카디널리티를 돈으로 번역

```bash
# 현재 활성 시계열 수 (AMP로 가는 양의 근사)
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3
SERIES=$(curl -s 'localhost:9090/api/v1/query?query=prometheus_tsdb_head_series' | grep -o '"value":\["[^"]*","[0-9]*"' | grep -o '[0-9]*$')
echo "활성 시계열: $SERIES"
kill %1

# 샘플/월 계산 (scrape 30s 가정)
python3 - <<EOF
series = $SERIES
interval = 30
samples_month = series * (30*24*3600 / interval)
print(f"월 샘플 수: {samples_month/1e9:.1f}십억")
print(f"→ AMP 요금표의 '10억 샘플당 단가'를 곱해 추정 (최신 요금표 확인)")
print(f"scrape 15s면 2배, 시계열 10배(카디널리티 사고)면 10배")
EOF
```

**감각 훈련** — 두 손잡이의 확인: ① 카디널리티(시계열 수 — 08의 수문이 그대로 요금 수문), ② scrape 간격(15s→30s면 요금 절반 — 정말 15s가 필요한 메트릭인지). 03의 "라벨은 곱셈"이 여기서 "요금도 곱셈"이 됩니다.

## 3. 수문의 재확인 — relabeling이 AMP 요금을 지킵니다

```
08 lab-02에서 건 것들이 그대로 AMP 방어선:
  metricRelabelings drop (go_* 등)   → 그 시계열은 AMP로 안 감 = 과금 없음
  sampleLimit                        → 폭발 타깃이 AMP 요금 폭발로 이어지지 않음
+ remote_write 자체의 필터도 가능:
  remoteWrite[].writeRelabelConfigs  → "보낼 것만 골라 보내기" (원격 전용 수문)
  예: 로컬엔 전부 두고, AMP엔 핵심(RED·SLI·용량)만 — 계층화의 메트릭판
```

## 4. 판단 정리 — 세 갈래의 조건

lab의 경험(연결의 단순함·요금 구조)을 바탕으로 theory 6절의 표를 자기 언어로 채워라:

```
질문 세트 (조직 시나리오 훈련 — cncf 48의 3층 적용):
  Q1. 클러스터 1개, 보존 2주면 충분, 팀 3명
      → 자체(로컬만). AMP는 과함 — 요금·의존만 늘어남
  Q2. EKS 3클러스터, 보존 13개월(규정), 플랫폼 1명, AMG 사용 예정
      → AMP. 멀티클러스터 집약 + 장기 + 운영 최소 + AWS 생태 정합
      (13개월 자체 운영은 1명으론 위험 — 09의 "관리형 우선")
  Q3. 온프레+멀티클라우드 50클러스터, 시계열 수천만, 전담 플랫폼 팀
      → Thanos/Mimir 검토(24) — AWS 종속 회피 + 규모의 비용 최적화 여지
      + 단 운영 비용을 정직하게 (cncf 45의 "설치≠운영")

공통 전제 (어느 갈래든):
  08의 수집 체계 + 03의 카디널리티 규율 — 이건 갈래와 무관한 기본기
  remote_write 표준 덕에 갈아타기 가능 — 결정을 ADR로(재평가 조건 포함, cncf 48)
```

## 5. SIGNALS-MAP 갱신 (과제)

```
메트릭 줄 갱신:
  저장: 로컬 2h(하이브리드) + AMP(장기) — remote_write(IRSA·SigV4)
  수문: metricRelabelings(로컬) + writeRelabelConfigs(원격 전용) 선택지
  룰: 로컬 평가(하이브리드) — 에이전트 모드 전환 시 AMP 룰로
  요금: 시계열 × 빈도 = 샘플 (계산식 기록)
```

## 6. 정리

```bash
bash cleanup.sh   # 워크스페이스·IRSA·룰 삭제
```

## 정리

- AMP 룰 = 원격 평가 — 평가 주체는 한 곳으로 (중복 정의는 정의 분기 사고의 재연)
- 요금 = 시계열 × scrape 빈도 — 두 손잡이를 계산하는 습관 (03의 곱셈이 요금으로)
- 수문의 이중화: metricRelabelings(전역) + writeRelabelConfigs(원격 전용 선별)
- 판단: 소규모 자체 / AWS 중심·운영 최소 AMP / 초대규모·멀티클라우드 Thanos·Mimir(24)
- **★ remote_write 표준이 갈아타기를 보장 — 결정은 ADR로, 재평가 조건과 함께 (cncf 48)**
