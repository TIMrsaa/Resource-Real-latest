# Lab 01 — Envoy를 손으로 돌리고, 요청의 여정을 따라가고, xDS를 봅니다

Envoy를 정적 설정으로 직접 실행해 4계층을 눈으로 보고, 그다음 동적(xDS) 설정이 무엇을 바꾸는지 확인합니다.

전제: docker, curl.

## Step 1. 백엔드 둘 + Envoy 정적 설정

```bash
mkdir -p ~/cncf-lab/envoy && cd ~/cncf-lab/envoy
docker network create envoy-lab 2>/dev/null || true

docker run -d --name backend-a --network envoy-lab hashicorp/http-echo -text="A" -listen=:5678 >/dev/null
docker run -d --name backend-b --network envoy-lab hashicorp/http-echo -text="B" -listen=:5678 >/dev/null

cat > envoy.yaml <<'EOF'
admin:
  address: { socket_address: { address: 0.0.0.0, port_value: 9901 } }
static_resources:
  listeners:                              # ★ 계층 1: 어디서 받는가
    - name: main
      address: { socket_address: { address: 0.0.0.0, port_value: 8080 } }
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress
                access_log:
                  - name: envoy.access_loggers.stdout
                    typed_config: { "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog }
                http_filters:               # ★ 필터 체인 (router가 마지막)
                  - name: envoy.filters.http.router
                    typed_config: { "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router }
                route_config:               # ★ 계층 2: 어디로 보내는가
                  virtual_hosts:
                    - name: all
                      domains: ["*"]
                      routes:
                        - match: { prefix: "/" }
                          route: { cluster: backends }
  clusters:                               # ★ 계층 3: 무엇의 그룹인가
    - name: backends
      connect_timeout: 1s
      type: STRICT_DNS
      lb_policy: ROUND_ROBIN
      load_assignment:
        cluster_name: backends
        endpoints:                         # ★ 계층 4: 실제 인스턴스
          - lb_endpoints:
              - endpoint: { address: { socket_address: { address: backend-a, port_value: 5678 } } }
              - endpoint: { address: { socket_address: { address: backend-b, port_value: 5678 } } }
EOF

docker run -d --name envoy --network envoy-lab -p 8080:8080 -p 9901:9901 \
  -v $(pwd)/envoy.yaml:/etc/envoy/envoy.yaml envoyproxy/envoy:v1.31-latest >/dev/null
sleep 5
```

## Step 2. 요청의 여정 확인 — 로드밸런싱

```bash
echo "=== 10번 요청 (round robin → A/B 교대) ==="
for i in $(seq 1 10); do curl -s localhost:8080; done | sort | uniq -c
```

예상: A 5, B 5. ✅ listener(8080) → route(prefix /) → cluster(backends) → endpoint(A/B 교대)의 4계층 여정(theory §1).

## Step 3. admin 인터페이스 — 프록시의 내부

```bash
echo "=== 클러스터 상태 (엔드포인트 헬스) ==="
curl -s localhost:9901/clusters | grep -E "backends::.*health_flags" | head -4

echo ""
echo "=== 통계: 요청 카운터 ==="
curl -s localhost:9901/stats | grep -E "cluster.backends.upstream_rq_(2xx|total)" | head -3

echo ""
echo "=== config_dump: 현재 설정 (theory §6 — 디버깅 급소) ==="
curl -s localhost:9901/config_dump | python3 -c "
import json,sys
d = json.load(sys.stdin)
for c in d['configs']:
    t = c['@type'].split('.')[-1]
    print(f'  {t}')" | head -6
```

✅ `/config_dump`이 Envoy가 현재 가진 전체 설정 — 나중에 istiod가 무엇을 밀어넣었는지 볼 곳(theory §6).

## Step 4. 정적 vs 동적 — 백엔드를 죽여봅니다

```bash
echo "=== backend-a를 죽인다 ==="
docker stop backend-a >/dev/null
sleep 3

echo "정적 설정에서는? (엔드포인트가 하드코딩됨)"
for i in $(seq 1 6); do curl -s --max-time 2 localhost:8080 2>/dev/null || echo "실패"; done | sort | uniq -c
echo "→ Envoy가 STRICT_DNS로 재해석하지만, 정적 목록은 여전히 A를 시도한다"
echo "  (일부 실패 또는 B로만) — 파일 설정의 한계"

docker start backend-a >/dev/null; sleep 3
```

## Step 5. xDS의 필요성 — K8s에서 무슨 일이 벌어지나

```bash
cat <<'EOF'
정적 설정의 한계 (지금 본 것):
  엔드포인트가 envoy.yaml에 하드코딩 → Pod가 뜨고 죽을 때마다 파일 수정+리로드?
  K8s에서 Pod IP는 초 단위로 바뀝니다 → 불가능

xDS의 답 (theory §2):
  Envoy가 컨트롤플레인에 gRPC 스트림 연결
  clusters를 CDS로, endpoints를 EDS로 받습니다
  → Pod가 뜨면 컨트롤플레인이 EDS 응답을 밀어넣음 → Envoy가 무중단 반영

Istio에서:
  istiod가 K8s의 Endpoints/EndpointSlice를 watch
  → 변화를 EDS로 각 사이드카 Envoy에 push
  → "istiod가 하는 일 = K8s 상태를 xDS로 번역" (24에서 확인)
EOF
```

## Step 6. 동적 설정 흉내 — 설정 교체 관찰

```bash
# 라우트를 바꿔봅니다 (B로만 보내기) — config_dump 전후 비교
curl -s localhost:9901/config_dump | python3 -c "
import json,sys
d = json.load(sys.stdin)
for c in d['configs']:
    if 'Cluster' in c['@type']:
        for cl in c.get('dynamic_active_clusters', []) + c.get('static_clusters', []):
            print('cluster:', cl['cluster']['name'])
" 2>/dev/null | head -3

cat <<'EOF'
실제 xDS 실험(개념):
  go-control-plane 같은 xDS 서버를 띄우고 Envoy를 dynamic_resources로 연결하면
  런타임에 endpoint를 추가/제거해도 Envoy 재시작 없이 반영됩니다
  → lab-02에서 kind + Contour(Envoy 컨트롤플레인)로 실물 확인
EOF
```

## Step 7. 필터 체인 확장 — 헤더 조작 필터 추가

```bash
cat <<'EOF'
필터 체인에 필터를 추가하면 (router 앞에):
  http_filters:
    - name: envoy.filters.http.lua        # ★ 커스텀 로직
      typed_config:
        "@type": ...Lua
        inline_code: |
          function envoy_on_response(handle)
            handle:headers():add("x-served-by", "envoy-lab")
          end
    - name: envoy.filters.http.router     # 항상 마지막

→ 인증(jwt_authn), rate limit, 외부 인가(ext_authz→OPA), WASM 확장이 전부
  이 필터 체인의 항목들입니다 (theory §4)
EOF
```

## Step 8. 산출물

```markdown
# Envoy 4계층 카드
- listener(포트·TLS) → filter chain(HCM + http filters) → route(도메인·경로 → cluster)
  → cluster(LB·복원력) → endpoint(실제 IP)
- xDS: LDS/RDS/CDS/EDS가 4계층에 대응, gRPC 스트림으로 무중단 갱신
- EDS가 가장 자주 변함(Pod 생명주기) → 파일 설정으로 불가능 → xDS의 존재 이유
- 디버깅: admin :9901 → /clusters(헬스), /stats(카운터), /config_dump(현재 설정 전체)
- 필터는 순서, router가 마지막
```

## 정리

lab-02에서 복원력과 통계를 다룹니다. 컨테이너 유지.
