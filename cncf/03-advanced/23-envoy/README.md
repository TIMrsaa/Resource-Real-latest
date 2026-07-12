# 23 — Envoy 심층: 로고 뒤에 숨은 공용 프록시 엔진

> 04의 네트워킹 지도에서 그린 "Envoy 계보도"의 뿌리. Istio의 사이드카도, Contour·Emissary 인그레스도, 수많은 API 게이트웨이도 속은 Envoy입니다 — 그런데 왜? 답은 하나의 설계 결정에 있습니다: **설정을 파일이 아니라 API(xDS)로 실시간 주입받습니다.** 이 모듈은 그 xDS의 실체(누가 Envoy에게 무엇을 언제 알려주나), Envoy의 처리 모델(리스너→필터체인→라우트→클러스터), 그리고 왜 컨트롤플레인들이 이 위에 앉는지를 팝니다. 24(Istio)·25(Linkerd)의 전제 지식입니다.

## 학습 목표

1. Envoy의 구성 요소(listener/filter chain/route/cluster/endpoint)와 요청의 여정을 압니다
2. xDS(LDS/RDS/CDS/EDS)가 동적 설정을 어떻게 전달하는지 — 그리고 왜 이것이 혁명인지 압니다
3. 컨트롤플레인/데이터플레인 분리를 이해하고, Istio·Contour가 왜 "설정 생성기"인지 압니다
4. 관측(통계·액세스 로그·트레이싱)과 복원력(서킷 브레이커·아웃라이어 감지·재시도)을 실습합니다
5. Envoy를 직접 정적 설정으로 돌려보고, xDS로 동적 갱신을 확인합니다

## 선행: 04(네트워킹 지도 — Envoy 계보), eks 14(ALB·L7), 12·13(관측) · 도구: docker, curl, kind
## 비용: 없음 (docker + kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-static-and-xds.md](./lab-01-static-and-xds.md) — 정적 설정, 요청 여정, xDS 동적 갱신
3. [lab-02-resilience-and-observability.md](./lab-02-resilience-and-observability.md) — 서킷 브레이커·아웃라이어·통계
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
