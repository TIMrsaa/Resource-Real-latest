# 학습 가이드 — "규칙"과 "규칙을 실행할 몸"의 분리

## 이 모듈의 핵심 구조

Ingress/Gateway 둘 다 같은 분업 구조입니다:

```
규칙 선언 (YAML 리소스)        실행체 (직접 설치해야 함!)
Ingress / HTTPRoute     ─→    Ingress Controller / Gateway 구현체
"shop.example.com/cart는      (nginx, envoy 등 실제 프록시가
 cart 서비스로 보내라"          그 규칙대로 트래픽을 처리)
```

**K8s는 규칙 문법만 표준화했고, 실행체는 동봉하지 않았습니다.** "Ingress 만들었는데 아무 일도 안 일어나요"의 원인 1위가 "컨트롤러 미설치"다.

## 왜 두 세대를 다 배우나

- **Ingress**: 유지보수 모드지만 기존 클러스터의 대다수가 아직 사용 — 읽을 줄 알아야 합니다. annotation 지옥(구현체마다 다른 비표준 확장)이 어떤 문제였는지도 직접 봐야 Gateway API의 설계가 이해됩니다.
- **Gateway API**: 신규 표준. 역할 분리(인프라팀=Gateway, 개발팀=HTTPRoute), 표현력(헤더 매칭/가중치/미러링이 **표준 필드**), HTTP 외 프로토콜까지. 신규 설계는 무조건 이쪽.

## 학습 전략

1. lab-01에서 Ingress의 annotation이 늘어나는 불편을 **일부러 체험**하고
2. lab-02에서 같은 요구사항이 Gateway API 표준 필드로 깔끔히 풀리는 것을 비교하세요
3. 가중치 라우팅(90:10 카나리)은 cicd 파트의 progressive delivery로 이어지는 복선입니다

## EKS 맥락

이 모듈은 이식성 있는 오픈소스 구현체(NGINX)로 학습합니다. EKS 전용 구현(AWS Load Balancer Controller의 ALB Ingress, VPC Lattice 기반 Gateway)은 eks 파트 08에서 — 거기서 "여기서 배운 문법이 그대로"임을 확인하게 됩니다.
