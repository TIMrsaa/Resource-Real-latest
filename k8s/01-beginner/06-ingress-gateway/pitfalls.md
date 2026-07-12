# 흔한 함정 5선

## 1. 컨트롤러/구현체 없이 리소스만 생성

lab-01 Step 2의 그 상황. Ingress/Gateway 리소스는 **규칙 선언**일 뿐, 실행체(컨트롤러)를 설치해야 동작합니다. 확인: `kubectl get ingressclass` / `kubectl get gatewayclass` 에 ACCEPTED된 클래스가 있는가.

## 2. pathType 혼동 (Ingress)

- `Prefix`: `/cart` 는 `/cart`, `/cart/items` 매칭 — 단, **경로 세그먼트 단위**라 `/cartoon`은 비매칭
- `Exact`: `/cart` 만
- `ImplementationSpecific`: 구현체 마음대로 (이식성 포기)

"왜 /cartoon이 cart로 안 가요/가요" 류 혼란의 근원. Gateway API도 PathPrefix 의미는 동일(세그먼트 단위).

## 3. 502/503을 전부 Gateway 탓하기

Gateway/Ingress는 결국 백엔드 Service→EndpointSlice로 보냅니다. 503의 대부분은 **백엔드 명단이 빈 것**(모듈 05의 디버깅 공식: selector/Ready/포트)입니다. L7 계층을 의심하기 전에 `kubectl get endpointslices`부터.

## 4. TLS 인증서를 수동 관리

Gateway listener의 TLS는 Secret을 참조합니다. 인증서를 손으로 발급/갱신하다 만료 장애 — 표준 해법은 cert-manager(자동 발급/갱신, cncf 파트 19)입니다. "인증서 만료"는 변명이 안 통하는 사고 유형 1위.

## 5. 구현체별 기능 차이를 표준으로 착각

Gateway API에도 등급이 있습니다: Core(모든 구현체 필수) / Extended(선택) / Implementation-specific. `weight`는 Core지만 일부 고급 필터는 Extended입니다. 구현체 conformance 보고서를 확인하고 쓰라 — "로컬 nginx에선 됐는데 EKS ALB에선 안 돼요"의 원인.

## 실무 사고 사례

> ingress-nginx 단일 컨트롤러에 회사 전 서비스 라우팅을 몰아넣은 팀. 특정 서비스의 잘못된 annotation(정규식 경로) 하나가 nginx 설정 reload 실패를 유발 → **전사 라우팅 갱신 중단** (기존 트래픽은 흘렀지만 신규 배포 라우팅이 전부 멈춤). Gateway API의 역할 분리 + Route 단위 검증은 정확히 이 폭발 반경(blast radius)을 줄이는 설계입니다.
