# Lab 02 — 서킷 브레이커, 아웃라이어 감지, 그리고 통계로 보는 프록시

메시(24·25)가 "코드 수정 없이 복원력을 준다"고 할 때 그 복원력의 실체를 직접 만듭니다.

전제: lab-01의 컨테이너들(envoy, backend-a/b, envoy-lab 네트워크).

## Step 1. 복원력 설정을 담은 새 Envoy 설정

```bash
cd ~/cncf-lab/envoy
docker rm -f envoy >/dev/null 2>&1

# 느린/실패하는 백엔드 추가
docker rm -f backend-slow 2>/dev/null || true
docker run -d --name backend-slow --network envoy-lab \
  hashicorp/http-echo -text="SLOW" -listen=:5678 >/dev/null

cat > envoy-resilience.yaml <<'EOF'
admin: { address: { socket_address: { address: 0.0.0.0, port_value: 9901 } } }
static_resources:
  listeners:
    - name: main
      address: { socket_address: { address: 0.0.0.0, port_value: 8080 } }
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress
                http_filters:
                  - name: envoy.filters.http.router
                    typed_config: { "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router }
                route_config:
                  virtual_hosts:
                    - name: all
                      domains: ["*"]
                      routes:
                        - match: { prefix: "/" }
                          route:
                            cluster: backends
                            timeout: 2s               # ★ route 타임아웃
                            retry_policy:              # ★ 재시도
                              retry_on: "5xx,reset,connect-failure"
                              num_retries: 2
                              per_try_timeout: 1s
  clusters:
    - name: backends
      connect_timeout: 1s
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      circuit_breakers:                              # ★ 서킷 브레이커
        thresholds:
          - priority: DEFAULT
            max_connections: 10
            max_pending_requests: 5
            max_requests: 10
      outlier_detection:                             # ★ 아웃라이어 감지
        consecutive_5xx: 3
        interval: 5s
        base_ejection_time: 10s
        max_ejection_percent: 50
      load_assignment:
        cluster_name: backends
        endpoints:
          - lb_endpoints:
              - endpoint: { address: { socket_address: { address: backend-a, port_value: 5678 } } }
              - endpoint: { address: { socket_address: { address: backend-b, port_value: 5678 } } }
EOF

docker run -d --name envoy --network envoy-lab -p 8080:8080 -p 9901:9901 \
  -v $(pwd)/envoy-resilience.yaml:/etc/envoy/envoy.yaml envoyproxy/envoy:v1.31-latest >/dev/null
sleep 5
```

## Step 2. 서킷 브레이커 — 빠른 실패

```bash
echo "=== 서킷 브레이커 설정 확인 ==="
curl -s localhost:9901/stats | grep "circuit_breakers.default" | head -5

echo ""
echo "=== 동시 요청 폭주 (max_pending_requests=5 초과) ==="
for i in $(seq 1 50); do curl -s -o /dev/null localhost:8080 & done; wait 2>/dev/null
sleep 2
echo "pending overflow (서킷 브레이커 발동 횟수):"
curl -s localhost:9901/stats | grep -E "upstream_rq_pending_overflow|upstream_cx_overflow" | head -3
```

✅ 한도를 넘은 요청은 **즉시 실패**(pending_overflow) — 느린 백엔드가 프록시의 리소스를 다 먹고 전체를 마비시키는 것을 차단(theory §5). "빠른 실패"의 실체.

## Step 3. 아웃라이어 감지 — 죽어가는 인스턴스 격리

```bash
echo "=== backend-b를 죽여 연속 실패를 유발 ==="
docker stop backend-b >/dev/null

echo "요청을 보내 consecutive_5xx를 쌓습니다..."
for i in $(seq 1 20); do curl -s -o /dev/null --max-time 2 localhost:8080; done
sleep 6

echo ""
echo "=== 격리된(ejected) 엔드포인트 ==="
curl -s localhost:9901/clusters | grep -E "backends::.*(health_flags|ejection)" | head -6
curl -s localhost:9901/stats | grep -E "outlier_detection.ejections" | head -4
```

예상: backend-b가 `/failed_outlier_check` 또는 ejection 카운터 증가. ✅ **죽어가는 엔드포인트를 로드밸런싱 풀에서 자동 제외**(theory §5) — 수동 헬스체크가 필요 없습니다. 이후 요청은 살아있는 backend-a로만.

```bash
echo ""
echo "격리 후 요청은 A로만:"
for i in $(seq 1 6); do curl -s --max-time 2 localhost:8080; echo; done | sort | uniq -c

docker start backend-b >/dev/null; sleep 12
echo "base_ejection_time(10s) 후 backend-b 복귀:"
curl -s localhost:8080; echo
```

## Step 4. 재시도의 함정 — budget

```bash
cat <<'EOF'
재시도(retry)는 양날 (18의 KEDA 재시도 교훈과 같은 계열):
  좋음: 일시적 실패(reset, 5xx)를 투명하게 극복
  위험: 백엔드가 과부하일 때 재시도가 부하를 증폭 (재시도 폭풍)

방어:
  retry_budget: 전체 요청 대비 재시도 비율 상한 (예: 20%)
    → 재시도가 전체 트래픽의 일정 비율을 못 넘게
  per_try_timeout: 각 시도의 타임아웃 (전체 timeout보다 짧게)
  멱등 요청만: retry_on을 신중히 (POST 재시도는 중복 생성 위험)
    → GET·PUT·DELETE는 대체로 안전, POST는 조심

★ eks 14의 무중단 배포와 idle_timeout, 18의 재시도 규율이 여기서 만납니다
EOF
curl -s localhost:9901/stats | grep -E "upstream_rq_retry" | head -3
```

## Step 5. 통계 — 관측의 재료 (11과 연결)

```bash
echo "=== Envoy가 내뱉는 핵심 통계 ==="
curl -s localhost:9901/stats | grep -E "cluster.backends.upstream_rq_(2xx|4xx|5xx|time)" | head -6

cat <<'EOF'

Prometheus 통합 (11):
  /stats/prometheus 엔드포인트 → Prometheus가 스크레이프
  주요 메트릭:
    envoy_cluster_upstream_rq_total{envoy_response_code}
    envoy_cluster_upstream_rq_time_bucket (지연 히스토그램 → p99, 11의 histogram_quantile)
    envoy_cluster_outlier_detection_ejections_active (격리 중인 엔드포인트)
    envoy_cluster_circuit_breakers_default_rq_pending_open (서킷 열림!)

  ★ 카디널리티 주의(11): cluster 수 × stat 수. 메시에서 서비스가 많으면 폭발
    → stats_matcher로 불필요 통계 억제
EOF
curl -s localhost:9901/stats/prometheus 2>/dev/null | grep "envoy_cluster_upstream_rq_total" | head -2
```

## Step 6. 액세스 로그와 트레이싱

```bash
echo "=== Envoy 액세스 로그 (요청별 상세) ==="
docker logs envoy 2>&1 | grep -E "GET|POST" | tail -3

cat <<'EOF'

액세스 로그 포맷 (커스터마이즈 가능):
  %START_TIME% %REQ(:METHOD)% %REQ(:PATH)% %RESPONSE_CODE% %DURATION%
  %UPSTREAM_HOST% %RESP(x-envoy-upstream-service-time)%

분산 트레이싱 (12와 연결):
  Envoy가 x-request-id를 생성·전파하고 span을 만듭니다
  → tracing 설정으로 OTel Collector·Jaeger에 전송 (12·13)
  → 메시(24)에서 "코드 수정 없이 트레이스가 생기는" 것의 실체
  ★ 단 컨텍스트 전파(12)는 여전히 앱 책임 — Envoy는 자기 구간만 압니다
EOF
```

## Step 7. 산출물 — 복원력·관측 카드

```markdown
# Envoy 복원력 (cluster 수준)
- 서킷 브레이커: max_connections/requests/pending → 빠른 실패 (부하 격리)
- 아웃라이어 감지: consecutive_5xx → 죽어가는 엔드포인트 자동 격리
- 재시도: retry_on + num_retries + budget(폭풍 방지) + per_try_timeout
- 타임아웃: route timeout, per_try_timeout, idle_timeout(eks 14)

# 관측
- /stats(/prometheus): upstream_rq_*, rq_time(p99), ejections, cb 상태
- 카디널리티: cluster 수 × stat 수 (메시에서 주의 — stats_matcher)
- 액세스 로그: 요청별 상세 / 트레이싱: x-request-id (컨텍스트 전파는 앱 책임 — 12)

# 이 모든 것이 메시(24·25)의 "코드 수정 없는 복원력·관측"의 실체
```

## 정리

```bash
bash cleanup.sh
```
