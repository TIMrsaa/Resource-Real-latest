# Lab 01 — Hubble: 계측 없는 흐름 관측

> Cilium+Hubble을 켜고, 계측이 전혀 없는 앱들의 통신을 흐름 수준(L4)과 HTTP 수준(L7)에서 관측합니다. 그리고 네트워크 정책 드롭이 "관측 이벤트"가 되는 것 — Hubble의 고유 가치 — 를 확인합니다.

## 0. 준비 — Cilium CNI의 kind

```bash
# 기본 CNI를 끄고 생성 (cncf 22와 동일 방식)
cat > /tmp/kind-cilium.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking: { disableDefaultCNI: true }
nodes: [{ role: control-plane }, { role: worker }]
EOF
kind create cluster --name ebpf --config /tmp/kind-cilium.yaml

# Cilium + Hubble 활성화
cilium install --wait
cilium hubble enable --ui
cilium status --wait
```

## 1. 계측 없는 앱 — 아무 준비 없이 배포

```bash
kubectl create namespace shop
# 04·11에서 쓰던 앱들 — 단, ★ 이번엔 계측 어노테이션 없음!
kubectl -n shop create deployment backend --image=hashicorp/http-echo -- \
  /http-echo -listen=:8080 -text='{"stock":42}'
kubectl -n shop expose deployment backend --port=8080
kubectl -n shop create deployment frontend --image=curlimages/curl -- \
  sh -c 'while true; do curl -s http://backend:8080/ >/dev/null; curl -s http://backend:8080/missing >/dev/null; sleep 1; done'
kubectl -n shop rollout status deploy/backend deploy/frontend --timeout=120s
```

## 2. L4 흐름 — 즉시 보이는 통신 지도

```bash
cilium hubble port-forward &
sleep 3

# 흐름 관찰 — 계측 0인데 통신이 전부 보입니다!
hubble observe --namespace shop --last 10
# Jul 11 12:00:01 shop/frontend-xxx -> shop/backend-yyy:8080 (TCP) FORWARDED
# Jul 11 12:00:01 shop/backend-yyy -> shop/frontend-xxx (TCP) FORWARDED
#   ↑ Pod "신원"으로 표시 (IP가 아니라!) — cncf 22의 identity 기반
```

**체감 포인트** — 어떤 앱 수정도, SDK도, 어노테이션도 없습니다. CNI(커널 경로)를 지나는 모든 통신이 신원 기반으로 즉시 보입니다 — "배포 첫날의 기본 지도"라는 eBPF 관측의 약속이 이것입니다.

## 3. L7 가시성 — HTTP를 커널에서 읽습니다

```bash
# L7 가시성 어노테이션 (Cilium이 해당 트래픽을 L7 파싱)
kubectl -n shop annotate deployment backend \
  policy.cilium.io/proxy-visibility="<Ingress/8080/TCP/HTTP>"
sleep 15

hubble observe --namespace shop --protocol http --last 10
# ... http-request GET http://backend:8080/ FORWARDED
# ... http-response 200 ...
# ... http-request GET http://backend:8080/missing
# ... http-response 404 ...        ← ★ HTTP 경로·코드가 계측 없이!
```

```bash
# Hubble 메트릭 → Prometheus 합류 가능 (08 파이프라인)
# cilium hubble enable --ui 시 메트릭 옵션으로 http 등 활성화하면
# hubble_http_requests_total{...} 계열이 노출 — 계측 없는 RED의 재료
```

**한계 동시 확인** — 404가 보이지만 "왜 404인지"(앱 라우팅? 데이터 없음?)는 모릅니다. 그리고 frontend의 두 요청(/, /missing)이 "같은 사용자 흐름"인지 이을 실(trace_id)도 없습니다 — 보이는 것은 구간의 사실, 여정과 이유는 다른 도구의 영토(guide의 한계 ①②).

## 4. 고유 가치 — 정책 드롭이 관측 이벤트로

```bash
# 네트워크 정책으로 frontend→backend 차단 (cncf 22의 정책)
cat <<'EOF' | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: { name: deny-frontend, namespace: shop }
spec:
  endpointSelector: { matchLabels: { app: backend } }
  ingress:
    - fromEndpoints:
        - matchLabels: { app: nothing-matches }   # 아무도 허용 안 됨
EOF
sleep 10

hubble observe --namespace shop --verdict DROPPED --last 5
# shop/frontend-xxx -> shop/backend-yyy:8080 (TCP) DROPPED (Policy denied)
#   ↑ ★ "왜 연결이 안 되지?"의 즉답 — 정책이 막았고, 어느 정책 방향인지까지
```

**동선 가치** — 네트워크 문제 조사의 전통적 지옥("타임아웃인데 앱? DNS? 정책? 방화벽?")에서, verdict=DROPPED는 즉답입니다. cncf 22의 "판정=관찰 지점"이 관측 동선으로: **연결 문제는 hubble observe --verdict DROPPED부터**가 새 반사신경(05 카탈로그에 추가)입니다.

```bash
kubectl -n shop delete ciliumnetworkpolicy deny-frontend   # 원복
```

## 5. DNS 가시성 (cncf 20의 재회)

```bash
hubble observe --namespace shop --protocol dns --last 10
# ... DNS Query backend.shop.svc.cluster.local. A
# ... DNS Query backend.shop.svc.cluster.local.shop.svc.cluster.local. A  ← !
#   ↑ cncf 20의 ndots 증폭이 흐름으로 보입니다 — 이론이 눈앞의 데이터로
```

## 6. 정리

```bash
kill %1 2>/dev/null || true
# 클러스터는 lab-02에서 계속
```

## 정리

- 계측 0으로 전 통신이 신원 기반으로 즉시 — "배포 첫날의 기본 지도"
- L7 가시성으로 HTTP 경로·코드까지(커널 파싱) — 계측 없는 RED의 재료
- **verdict=DROPPED가 고유 가치** — "연결 안 됨" 조사의 즉답 (새 반사신경)
- DNS 흐름에서 ndots 증폭(cncf 20)이 실물로 — eBPF 관측은 이론의 현미경이기도
- **★ 동시에 확인된 한계: 404의 "왜", 요청들의 "여정"은 안 보입니다 — lab-02에서 분담 설계**
