# 흔한 함정 5선

## 1. Ingress마다 ALB 하나 (기본값의 청구서)

group.name 없이 마이크로서비스마다 Ingress → ALB가 서비스 수만큼 — 월말 청구서의 ELB 항목이 노드 비용에 육박합니다. 도메인/팀 단위 group.name이 기본기. 단 그룹은 설정 공유 운명체 — 그룹 분리 기준(외부/내부, 팀)을 정해두라.

## 2. instance 타겟 + externalTrafficPolicy 미스매치

instance 모드로 두면 NodePort 경유(k8s 05/28의 그 경로) — 추가 홉, SNAT로 클라이언트 IP 소실, 헬스체크가 노드 단위라 readiness와 어긋남. EKS에선 **ip 타겟이 기본기** — instance를 쓸 특별한 이유(보안그룹 구조 등)가 없다면.

## 3. 컨트롤러 권한 부족의 "조용한" Ingress

설치는 됐는데 IAM 정책이 빠지면 — Ingress가 ADDRESS 없이 영원히 대기, 에러는 **컨트롤러 로그에만**. "Ingress 만들었는데 안 생겨요"의 1번 진단: `kubectl logs -n kube-system deploy/aws-load-balancer-controller` → AccessDenied 검색. (09에서 권한 체계 자체를 해부)

## 4. kubectl delete ingress = 서비스 다운

Ingress를 지우면 ALB도 지워집니다(reconcile) — "잠깐 정리"가 곧 장애. 운영 Ingress엔 보호를: GitOps prune 보호(k8s 39), 삭제 권한 제한(RBAC), 그리고 group 사용 시엔 그룹 전체 영향 인지. 거꾸로 **컨트롤러 삭제/장애 시엔 LB가 잔존**해 과금되는 비대칭도 기억(cleanup은 Ingress 먼저, 컨트롤러 나중).

## 5. 헬스체크 경로 방치

healthcheck-path 미설정으로 기본 `/`가 301이나 404를 반환 → 타겟이 unhealthy → "Pod는 Ready인데 ALB가 502". ALB 헬스체크와 readiness(k8s 14)를 **같은 경로**로 정렬하는 것이 정석 — 두 시스템이 같은 기준으로 "받을 수 있음"을 판단하게.

## 실무 사고 사례

> 배포 후 간헐 502가 신고됐습니다. Pod는 전부 Ready, Service도 정상 — k8s 38 루틴으로는 막다른 길. ALB 대상그룹을 보니: 롤링 업데이트 때 **종료 중인 Pod이 타겟에서 빠지기 전에 SIGTERM을 받아** 연결을 끊고 있었습니다(드레이닝 시차). 처방: ① preStop sleep(k8s 14의 그 기법 — 등록 해제가 전파될 시간) ② deregistration delay 조정 ③ readiness 경로와 헬스체크 정렬. 교훈: LB가 끼면 "받을 수 있음"의 판단자가 둘(K8s readiness + ALB 헬스체크)이 됩니다 — 둘의 시차가 5xx의 단골 원인이고, 진단엔 대상그룹 상태(draining)가 결정적 단서입니다.
