# 24 — Istio 심층: 사이드카에서 ambient까지

> 04의 메시 층, eks 20에서 사용자로 만난 그것. 23에서 Envoy(데이터플레인)를 배웠으니 이제 그 위의 컨트롤플레인을 팝니다 — Istio는 "istiod가 K8s를 xDS로 번역해 Envoy에 밀어넣는 것"(23의 결론)이 전부입니다. 이 모듈은 세 축을 팝니다: istiod의 실제 동작(설정 번역·인증서 발급·사이드카 주입), 트래픽·보안·관측의 3대 기능이 어떻게 Envoy 설정으로 환원되는지, 그리고 메시 역사의 전환점인 **ambient 모드**(사이드카를 없앱니다)가 무엇을 바꾸는지. 25(Linkerd)·48(선택 가이드)의 비교 기준을 만듭니다.

## 학습 목표

1. istiod의 세 역할(xDS 서버·CA·사이드카 주입 webhook)과 데이터플레인과의 관계를 압니다
2. 트래픽 관리(VirtualService/DestinationRule)가 Envoy의 route/cluster로 번역되는 것을 config_dump로 확인합니다
3. mTLS(STRICT/PERMISSIVE)와 AuthorizationPolicy의 실제 집행 지점을 압니다
4. **ambient 모드**(ztunnel L4 + waypoint L7)가 사이드카 모델과 무엇이 다른지 압니다
5. 메시의 비용(사이드카 오버헤드, 복잡도, 장애 표면)과 "정말 필요한가"를 판단합니다

## 선행: 23(Envoy — 필수), eks 20(메시 사용자), 04(지도), 19(cert-manager·mTLS) · 도구: kind, kubectl, istioctl
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-istiod-and-traffic.md](./lab-01-istiod-and-traffic.md) — istiod, 트래픽 관리 → Envoy 번역 확인
3. [lab-02-security-and-ambient.md](./lab-02-security-and-ambient.md) — mTLS·인가, ambient 모드 비교
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 3h
