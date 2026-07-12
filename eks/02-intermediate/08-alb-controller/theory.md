# 이론 — LB Controller의 reconcile, 타겟 타입, 통합 전략

> **🌱 17세 눈높이 비유: 공연장 매표·안내 시스템 외주**
> Ingress 규칙(k8s 06)은 "어느 표는 어느 공연장으로"라는 **안내 방침 문서**입니다. AWS LB Controller는 그 문서를 읽고 실제 **안내 데스크(ALB)를 건물 입구에 설치**해주는 외주업체.
> - **instance 타겟** = 안내 데스크가 일단 아무 건물 출입구(노드)로 보내고, 건물 내 안내판(kube-proxy)이 다시 객석(Pod)으로 — 한 단계 더
> - **ip 타겟** = 데스크가 객석 번호(Pod IP)로 **직통 안내** — 객석 번호가 시 전체에서 유효한 진짜 주소(07)라서 가능
> - **group.name** = 공연 5개가 데스크를 하나로 합쳐 쓰기 — 데스크 임대료(ALB 요금)가 1/5

---

## 1. 컨트롤러 동작 — 세 가지 입력

| K8s 객체 | 만들어지는 실물 | 비고 |
|----------|----------------|------|
| Ingress (ingressClassName: alb) | **ALB** + 리스너 + 규칙 + 대상그룹 | L7 (host/path 라우팅, k8s 06) |
| Service (type: LoadBalancer + 어노테이션) | **NLB** + 대상그룹 | L4 (TCP/UDP, 고성능 — 14) |
| TargetGroupBinding (CRD) | 기존 대상그룹 ↔ Pod 연결만 | LB는 내가/타 도구가 만든 경우 |

reconcile의 함의 (k8s 30과 동일):
- 콘솔에서 ALB 규칙을 직접 수정 → 컨트롤러가 **되돌립니다** (진실은 K8s 객체)
- 컨트롤러가 죽어도 기존 LB는 동작 (새 반영만 멈춤) — 가용성 분리
- Ingress 삭제 = ALB 삭제 — **무심한 kubectl delete가 곧 서비스 다운** (k8s 39의 prune 주의와 동급)

### 권한 — 컨트롤러가 AWS API를 부르려면

ALB를 만들려면 AWS 권한이 필요합니다 → 컨트롤러 SA에 IAM 역할(IRSA/Pod Identity — **09의 주제**)을 붙입니다. lab에선 Pod Identity로 빠르게 — 원리는 09에서 해부.

## 2. 타겟 타입 — 경로의 해부 (k8s 28 연결)

```
[instance 모드]
Client → ALB → 노드:NodePort → KUBE-SVC 체인(확률 분배) → (다른 노드의) Pod
  문제: ① 홉 +1 ② 노드 간 재분배로 source 왜곡/conntrack 부담
       ③ externalTrafficPolicy 딜레마(k8s 05)

[ip 모드 — EKS 정석]
Client → ALB → Pod IP:port (대상그룹에 Pod IP가 직접 등록!)
  이점: 홉 최소, ALB 헬스체크가 Pod에 직접(readiness와 정합 — k8s 14),
       Fargate 호환, externalTrafficPolicy 무관
  전제: Pod IP가 VPC에서 라우팅 가능 (= VPC CNI, 07)
```

ip 모드에서 컨트롤러는 **EndpointSlice(k8s 05)를 watch**해 Pod IP를 대상그룹에 등록/제거합니다 — readiness가 빠지면 대상그룹에서도 빠집니다(드레이닝). "Service의 두 번째 소비자"인 셈 (첫째는 kube-proxy).

## 3. 자주 쓰는 어노테이션 (Ingress)

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing      # 외부 노출 (기본 internal)
    alb.ingress.kubernetes.io/target-type: ip              # ★ 정석
    alb.ingress.kubernetes.io/healthcheck-path: /healthz   # k8s 14의 그 경로
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...   # TLS는 ACM에서
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/group.name: shared-web       # ★ 통합 (아래)
    alb.ingress.kubernetes.io/group.order: '10'            # 그룹 내 규칙 순서
```

## 4. group.name — ALB 통합의 경제학

기본: Ingress 1개 = ALB 1개 (시간당 ~$0.0225 + LCU). 마이크로서비스 20개 = ALB 20개 = **월 $300+가 그냥 증발.**

`group.name`이 같은 Ingress들은 **하나의 ALB에 규칙으로 합쳐집니다**:

```
shared-web ALB
 ├ rule(order 10): api.shop.com  → api 대상그룹
 ├ rule(order 20): web.shop.com  → web 대상그룹
 └ rule(order 30): /admin        → admin 대상그룹
```

주의: 같은 그룹 = 같은 ALB 설정 공유(scheme/SG 등 충돌 시 에러), 그룹의 누군가가 잘못된 어노테이션을 넣으면 **그룹 전체에 영향** — 팀 간 공유 시 거버넌스(어노테이션을 admission으로 제한 — k8s 23) 고려.

## 5. NLB (Service type: LoadBalancer)

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```

ALB와의 선택(14에서 심층): L7 기능(경로/호스트/리다이렉트) 필요 → ALB / 순수 TCP·초고성능·고정 IP·비HTTP → NLB. (참고: 컨트롤러 없는 구식 in-tree CLB는 쓰지 않습니다)

## 6. TargetGroupBinding — 거꾸로 연결

LB/대상그룹을 Terraform 등 다른 체계가 소유할 때, **연결만** K8s가:

```yaml
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
spec:
  serviceRef: { name: web, port: 80 }
  targetGroupARN: arn:aws:elasticloadbalancing:...:targetgroup/...
```

→ 컨트롤러가 그 대상그룹에 Pod IP 등록/해제만 수행. 인프라팀(LB 소유)과 앱팀(K8s 소유)의 경계 인터페이스로 실무 빈출.

## 7. 소스/도구에서 확인하기

- 컨트롤러 리포: https://github.com/kubernetes-sigs/aws-load-balancer-controller (kubebuilder 구조! — k8s 30 독해 연습감)
- 어노테이션 전체 목록: 리포 docs/guide/ingress/annotations.md
- ALB 요금(LCU): https://aws.amazon.com/elasticloadbalancing/pricing/

## 요약 카드

| 질문 | 답 |
|------|----|
| 컨트롤러의 정체? | Ingress/Service를 보고 AWS API를 부르는 reconcile 루프 |
| 타겟 타입 정석? | ip (Pod 직행 — VPC CNI의 보너스) |
| ip 모드의 등록 원천? | EndpointSlice watch (readiness 연동) |
| 비용 폭증 방지? | group.name으로 Ingress N개 → ALB 1개 |
| 콘솔에서 ALB 수정하면? | reconcile이 원복 — 진실은 K8s 객체 |
| 기존 LB에 Pod만 연결? | TargetGroupBinding |
