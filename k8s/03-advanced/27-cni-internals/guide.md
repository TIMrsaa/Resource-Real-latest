# 학습 가이드 — 네트워크는 "그림 한 장 + 명령 셋"이면 뚫립니다

## 겁먹지 않기

K8s 네트워킹은 악명이 높지만, 구성요소는 의외로 적습니다:

```
Pod 안:  eth0 (평범한 인터페이스)
       │  veth 페어 (가상 랜선 — 양 끝이 다른 namespace에)
노드:   enixxxx (veth의 노드 쪽 끝) + 라우팅 테이블
       │
바깥:   (EKS) VPC 라우팅 — Pod IP가 진짜 VPC IP라서 추가 마법 없음
       (오버레이 CNI) VXLAN 터널 — 패킷을 포장해 노드끼리 배송
```

이 그림과 `ip addr / ip route / ip neigh` 세 명령이면 노드 네트워크의 90%가 읽힙니다. lab-01에서 이 셋만 반복합니다.

## 4대 요구사항 — CNI가 풀어야 하는 숙제

K8s가 모든 네트워크 구현에 요구하는 것:
1. 모든 Pod는 고유 IP를 가집니다
2. Pod끼리 **NAT 없이** 통신 가능 (노드가 달라도)
3. 노드 ↔ Pod도 NAT 없이
4. Pod가 보는 자기 IP = 남이 보는 그 Pod IP

"어떻게"는 자유 — 그래서 CNI 플러그인이 수십 개입니다. EKS VPC CNI의 답: "**Pod IP를 아예 VPC IP로**" (가장 단순한 답 — 추가 캡슐화 없음, 대신 IP 소모가 큼 → eks 파트 16의 IP 고갈 주제로 연결).

## 모듈 28과의 경계

이 모듈 = **Pod IP로 가는 길** (CNI). 다음 모듈 = **Service 가상 IP가 Pod IP로 바뀌는 마법** (kube-proxy/iptables). 패킷 입장에서 보면: Service DNAT(28) → 그 다음 실제 배송(27)입니다.
