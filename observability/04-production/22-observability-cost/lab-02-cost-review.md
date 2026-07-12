# Lab 02 — 비용 리뷰 실전: 계산 → 통제 → 가치 평가

> 분기 비용 리뷰를 실전 형식으로 수행합니다 — lab-01의 계측으로 현황을 계산하고, 레버리지 순서대로 통제를 적용해 효과를 정량화하고, 가치 평가로 폐기·재투자를 결정합니다. 조직에서 반복할 절차의 원형입니다.

## 0. 준비 (lab-01 이어서 — noisy 팀이 볼륨을 지배 중)

## 1. 현황 계산 — 방정식에 대입

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3

# 로그: 일일 볼륨과 월 추정
curl -s 'localhost:9090/api/v1/query?query=cost:log_bytes:per_day/1e6' | grep -o '"value":\[[^]]*\]'
# 예: 850 MB/일

# 메트릭: 월 샘플 수 (AMP라면 곧 요금)
curl -s 'localhost:9090/api/v1/query?query=cost:metric_samples:per_month/1e9' | grep -o '"value":\[[^]]*\]'
# 예: 5.2 (십억 샘플/월)

# 리뷰 시트 기록 (조직 절차의 원형):
#  신호 | 볼륨 | 월 추정 비용 | 전 분기 대비 | 지배 기여자
#  로그 | 850MB/d | $... | +40% | team-b(noisy) 85%
#  메트릭 | 5.2B/월 | $... | +5% | kube-state-metrics 30%...
```

## 2. 통제 ① — 수문 (최대 레버리지의 실증)

noisy의 debug 로그를 수문에서 자릅니다 (02의 레벨 규율 + 06의 필터):

```bash
# Fluent Bit에 debug 제외 필터 추가
cat >> /tmp/fb-meta.yaml <<'EOF'
EOF
# filters 섹션 교체: grep 필터 추가
sed -i 's|  filters: |\n    [FILTER]\n        Name    grep\n        Match   kube.*\n        Exclude log debug|' /tmp/fb-meta.yaml 2>/dev/null || true
```

명확성을 위해 values의 filters를 직접 다음으로 교체:

```yaml
  filters: |
    [FILTER]
        Name    kubernetes
        Match   kube.*
        Merge_Log On
    [FILTER]
        Name    grep
        Match   kube.*
        Exclude $level debug
```

```bash
helm upgrade fluent-bit fluent/fluent-bit -n monitoring -f /tmp/fb-meta.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s
sleep 300   # 30m 창이라 효과 반영 대기 (실습은 5분 창으로 봐도 됨)

# 효과의 정량화 (수문 전후 비교 — 통제는 측정으로 증명)
curl -s 'localhost:9090/api/v1/query?query=sum(rate(fluentbit_output_proc_records_total[5m]))' | grep -o '"value":\[[^]]*\]'
# noisy의 debug가 지배했으므로 출력 레코드율이 ~85% 감소!
```

**리뷰 시트 갱신** — "조치: debug 수문(전사 정책 — 프로덕션 debug는 기간 한정), 효과: 로그 볼륨 -85%, 월 $X 절감". **효과를 숫자로 남기는 것**이 다음 리뷰의 신뢰를 만듭니다. 동시에 team-b에는 02의 레벨 규율을 안내(소스에서 안 만드는 것이 더 상류의 수문).

## 3. 통제 ② — 메트릭 수문 (08의 재적용)

```bash
# 범인 순위에서 안 쓰는 무거운 메트릭 확인
curl -s 'localhost:9090/api/v1/query?query=topk(5,count%20by%20(__name__)({__name__=~".%2B"}))' | head -c 500
# 예: apiserver_request_duration_seconds_bucket이 수천 시계열

# 판단: 이 히스토그램을 우리가 쓰는가요? (가치 평가와 연결)
#  → 컨트롤 플레인 상세 조사에 안 쓴다면: 기본 ServiceMonitor의
#    metricRelabelings로 drop (08 lab-02의 수문을 무거운 것에 적용)
#  → 쓴다면 유지 — "무겁다"가 아니라 "무겁고 안 쓴다"가 폐기 조건
```

## 4. 가치 평가 — 폐기와 재투자

```
절차 실습 (가상의 사용 데이터로):
  ① 미사용 후보: 90일간 대시보드·알림·쿼리에서 참조 0인 메트릭/로그 스트림
     (Grafana 사용 통계·쿼리 로그가 원천 — 실습에선 목록만 작성)
  ② 등급 보정: audit 로그(감사)·SLO 시계열(계약)은 빈도 무관 유지
  ③ 폐기 실행: 저장소 삭제가 아니라 ★ 수문에서 차단
     (metricRelabelings drop / Fluent Bit 필터 / 계측 제거 PR)
  ④ 재투자 결정: 아낀 만큼 어디에?
     — 이 파트의 흐름이라면: 트레이스 커버리지 확대(04의 반쪽 전파 해소),
       프로파일링 도입(20), 합성 모니터링(21의 측정 지점)

리뷰 시트 최종형:
  현황(방정식) → 조치(수문·계층) → 효과($) → 폐기 목록 → 재투자안
  → 이 한 장이 분기 리뷰의 산출물 — 삭감 보고서가 아니라 정렬 보고서
```

## 5. 조직 장치의 코드화 (개념)

```
가드레일 (리뷰 사이를 지키는 것):
  sampleLimit(08) 전 ServiceMonitor 기본화
  정책 엔진(cncf 32): "라벨 수 > N인 메트릭 노출 금지" 같은 규칙
  신규 서비스 온보딩 체크리스트: 로그 레벨·라벨 심사·예상 볼륨 견적

showback:
  네임스페이스별 볼륨 대시보드를 팀에 공개 —
  "우리 팀이 40%"의 가시화가 리뷰 없이도 행동을 바꿉니다 (공유지의 해법)
```

## 6. SIGNALS-MAP 갱신 (과제)

```
비용 열 추가:
  자기 계측: 3층(볼륨·건강·비용 추정) + 워치독 ✅
  수문 현황: debug 차단·go_* drop·sampleLimit (효과 수치와 함께)
  리뷰 주기: 월간(비용)·분기(가치 평가) — 시트 템플릿 링크
```

## 7. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name metaobs
rm -f /tmp/fb-meta.yaml
```

## 정리

- 리뷰의 골격: 현황(방정식 대입) → 통제(레버리지 순서) → 효과 정량화 → 가치 평가 → 재투자
- 수문의 효과를 숫자로(-85%) — 측정이 다음 리뷰의 신뢰를 만듭니다
- 폐기 조건은 "무겁다"가 아니라 "무겁고 안 쓴다" — 등급 면제(감사·SLO)와 함께
- 폐기는 저장소 삭제가 아니라 수문 차단 — 그리고 아낀 것은 재투자(정렬)
- **★ 분기 리뷰 시트 한 장이 이 모듈의 산출물 — 삭감 보고서가 아니라 정렬 보고서**
