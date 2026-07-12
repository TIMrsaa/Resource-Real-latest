# 흔한 함정 5선

## 1. "자원이 남는데 Pod가 안 떠요" — IP 고갈

CPU/메모리 잔량만 보고 용량 계획을 하면 VPC CNI 환경에서 IP/ENI 한도에 먼저 부딪힙니다 (`Too many pods`, ipamd의 `no available IP addresses`). 노드 타입 선택 = Pod 밀도 선택이고, 서브넷 CIDR 크기 = 클러스터 확장 한도입니다. 신규 클러스터 설계 시 /16급 전용 서브넷 또는 prefix delegation을 처음부터.

## 2. ContainerCreating 고착의 CNI 단서를 놓침

`failed to assign an IP address to container` / `add cmd: failed` — kubelet 이벤트와 노드의 ipamd 로그(`/var/log/aws-routed-eni/`)에 명시됩니다. CNI 문제의 디버깅 위치는 ① describe pod 이벤트 ② 노드 kubelet 로그 ③ **aws-node(ipamd) 로그** 순.

## 3. aws-node DaemonSet을 함부로 재배포/수정

VPC CNI 설정(환경변수)을 바꾸려 DaemonSet을 직접 edit — 애드온 관리와 충돌하고, 잘못된 값(WARM_IP_TARGET 등)은 **ENI 폭증으로 서브넷을 순식간에 고갈**시킬 수 있습니다. 변경은 EKS 애드온 configuration으로, 효과(IP 소모량)를 계산한 뒤에.

## 4. hostPort가 안 되는 이유를 CNI에서 안 찾음

hostPort는 메인 플러그인이 아니라 체인의 **portmap 보조 플러그인**이 구현합니다 — 커스텀 CNI 구성에서 portmap이 빠지면 hostPort가 조용히 무시됩니다. (애초에 hostPort 자체가 노드 결합을 만드는 비권장 패턴이기도 합니다)

## 5. 멀티 CNI 설정 파일의 우선순위 함정

`/etc/cni/net.d/`에 설정 파일이 여러 개면 **사전순 첫 파일만** 사용됩니다. CNI를 교체/실험하다 옛 파일이 남으면 "설치한 새 CNI가 안 먹는" 미스터리. 파일명 접두 숫자(10-aws.conflist)가 우선순위 장치입니다.

## 실무 사고 사례

> 마이크로서비스 확장으로 Pod가 급증하던 팀 — 어느 날부터 배포가 간헐 Pending. 노드 CPU는 40%대라 원인을 못 찾다가, ipamd 로그에서 서브넷 IP 고갈을 발견. 응급으로 노드를 큰 타입으로 교체했지만 **서브넷 자체가 /24(251개)** 라 곧 다시 한계. 결국 secondary CIDR 추가 + custom networking 재구성에 2주. 교훈: **VPC CNI 클러스터의 첫 설계 질문은 "Pod가 최대 몇 개까지 갈 것인가 × IP"다.** 서브넷은 나중에 키우기 가장 어려운 자원입니다.
