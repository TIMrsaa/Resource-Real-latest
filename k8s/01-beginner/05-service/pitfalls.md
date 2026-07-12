# 흔한 함정 5선

## 1. "Service에 ping이 안 가요" → 정상입니다

ClusterIP는 NIC 어디에도 없는 가상 번호고, iptables 규칙은 선언된 프로토콜/포트(TCP 80 등)만 처리합니다. 연결 테스트는 ping이 아니라 `curl`/`nc -z`로 해당 포트를 직접 찔러라.

## 2. port / targetPort / nodePort / containerPort 혼동

| 필드 | 위치 | 의미 |
|------|------|------|
| `port` | Service | Service가 받는 포트 (클라이언트가 보는 것) |
| `targetPort` | Service | Pod 컨테이너로 전달할 포트 |
| `nodePort` | Service(NodePort/LB) | 노드에 뚫리는 포트 (30000~32767) |
| `containerPort` | Pod | 문서용 선언 (실제 강제력 없음 — 진짜 기준은 앱이 듣는 포트) |

`containerPort`를 바꾼다고 앱이 그 포트를 듣게 되는 게 아닙니다. **targetPort는 앱이 실제로 listen하는 포트**와 맞춰야 합니다.

## 3. LoadBalancer 남발

서비스 10개 = NLB 10개 = 월 $160+. HTTP 서비스들은 Ingress/Gateway API로 LB 하나를 공유하는 것이 정석 (모듈 06). LoadBalancer 타입은 비HTTP(TCP 게임서버, DB 프록시)나 단일 진입점에만.

## 4. Ready 안 된 Pod에 트래픽이 갑니다? / 안 갑니다?

방향이 둘 다 함정입니다:
- readiness probe **없음** → 시작 직후부터 명단에 등재 → 초기화 안 끝난 앱에 트래픽 (5xx)
- probe **너무 민감** (timeout 1s 등) → 일시 부하에 명단에서 빠졌다 들어왔습니다 → 간헐적 connection refused처럼 보임

## 5. ExternalName과 HTTPS/Host 헤더

ExternalName은 DNS CNAME일 뿐이라, 클라이언트가 보낸 Host 헤더/TLS SNI는 원래 Service 이름 기준이 됩니다 → 대상 서버가 904/인증서 불일치로 거부할 수 있습니다. HTTP(S) 외부 연동은 ExternalName보다 명시적 설정(프록시/메시)이 안전합니다.

## 실무 사고 사례

> 클러스터 철거 시 `eksctl delete cluster`만 실행. LoadBalancer Service가 만든 NLB와 보안그룹은 **K8s 컨트롤러가 지워야 하는데 컨트롤러가 먼저 죽어서** 고아로 잔존 → 3주간 조용히 과금 + VPC 삭제 실패의 원인. 교훈: **클러스터 삭제 전 `kubectl get svc -A | grep LoadBalancer` 확인 후 Service 먼저 삭제.**
