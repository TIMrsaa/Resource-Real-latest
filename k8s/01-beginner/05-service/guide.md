# 학습 가이드 — Service는 "물건"이 아니라 "규칙"입니다

## 가장 흔한 오개념 깨기

초심자는 Service를 "트래픽이 지나가는 프록시 서버"로 상상합니다. **틀렸습니다.** Service는 어디에도 "떠 있지" 않습니다:

- ClusterIP는 어떤 NIC에도 할당되지 않은 **가상 번호**입니다 (ping도 안 됩니다!)
- 실체는 각 노드의 **iptables/IPVS 규칙**: "이 가상 IP로 가는 패킷은 Pod IP 중 하나로 바꿔치기하라"
- 그 규칙을 깔아주는 설치공이 kube-proxy입니다

이 멘탈모델이 잡히면 "Service가 느려요"(→ Service는 홉이 아니므로 다른 원인), "Service에 ping이 안 가요"(→ 정상) 같은 질문이 스스로 풀립니다.

## 연결 사슬 — 디버깅의 지도

```
Service (selector: app=web)
   │  selector가 맞는 Pod를 찾아서
   ▼
EndpointSlice (실제 Pod IP 목록: 10.0.1.5:80, 10.0.2.7:80)   ← Ready인 Pod만!
   │  kube-proxy가 이 목록을 보고
   ▼
iptables/IPVS 규칙 (각 노드)
```

"연결이 안 될 때"는 이 사슬을 위에서부터 검사합니다: ① selector 오타? ② EndpointSlice가 비었나요? ③ Pod가 Ready인가요? — lab-01에서 세 가지를 전부 일부러 깨뜨려봅니다.

## 4종의 포함 관계 (외우지 말고 구조로)

```
LoadBalancer ⊃ NodePort ⊃ ClusterIP
(외부 LB 추가)  (노드 포트 추가)  (클러스터 내부 가상 IP)
```

LoadBalancer를 만들면 NodePort와 ClusterIP가 **자동으로 같이** 생깁니다. 상위 타입 = 하위 타입 + 노출 방법 추가.

## 이 모듈의 한계선

- DNS(`web.default.svc.cluster.local`)는 여기서 맛만 보고 모듈 16(CoreDNS)에서 해부
- HTTP 경로 라우팅은 Service의 일이 아닙니다 — 모듈 06(Ingress/Gateway API)
- iptables 규칙의 실제 내용은 고급 모듈 28에서 패킷 단위로 추적
