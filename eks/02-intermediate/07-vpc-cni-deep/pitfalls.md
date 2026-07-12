# 흔한 함정 5선

## 1. 서브넷 CIDR을 "넉넉하겠지"로 시작

/24(251개)로 시작한 클러스터 — warm pool 선점 + 노드당 수십 Pod면 금세 바닥. 게다가 **서브넷은 나중에 못 늘립니다**(보조 CIDR/새 서브넷 추가라는 큰 공사만 가능 — 16). 신규 클러스터의 Pod 서브넷은 /19~/16급으로 — IP는 공짜지만 부족은 비쌉니다.

## 2. 프리픽스만 켜고 maxPods 방치

ENABLE_PREFIX_DELEGATION=true로 끝 — kubelet의 maxPods가 옛 값(17)이면 슬롯이 있어도 kubelet이 거절합니다. 프리픽스 활성화는 **CNI 설정 + maxPods 상향 + 노드 교체** 3종 세트입니다(eksctl은 자동, 수동 구성은 nodeadm — 05).

## 3. kubectl set env로 aws-node 직접 수정

당장은 적용되지만 — 관리형 애드온의 다음 업데이트(11)가 **조용히 원복**시킵니다. "분명 켰는데 어느 날 꺼져 있는" 미스터리의 정체. 진실의 원천은 애드온 configuration-values 한 곳으로 (lab-02 Step 2의 방식).

## 4. 한 ENI 한도를 "보안 분리"로 착각

"Pod별로 SG를 주고 싶어 SG-for-Pod를 전 워크로드에" — branch ENI 소비로 노드 밀도가 급락하고 니트로 한정 제약에 걸립니다. SG-for-Pod는 **VPC 자원(RDS 등) 접근 제어가 필요한 소수 Pod**에만, Pod간 제어는 NetworkPolicy(k8s 15)로 — 도구의 분업.

## 5. IP 메트릭 없이 운영

ipamd 메트릭(total/assigned)과 서브넷 잔량을 아무도 안 봄 — 고갈은 어느 날 "Pod가 안 떠요"로 옵니다(그때는 16의 응급 절차). 이 모듈 lab-01 Step 3의 두 메트릭 + 서브넷 잔량을 대시보드/알림에 — **IP는 관측하는 자원**입니다.

## 실무 사고 사례

> 금요일 마케팅 이벤트로 HPA가 Pod를 4배 증설 — 절반이 Pending. 노드 CPU는 60% 여유라 모두가 의아해하는 사이, 한 엔지니어가 ipamd 로그에서 `no available IP addresses`를 발견. 진상: /24 서브넷 × warm ENI 선점 × 노드 증가가 겹쳐 서브넷이 말라 있었습니다. 응급: WARM_IP_TARGET으로 선점 축소 + 미사용 ENI 정리로 수십 개 회수 → 주말 후 보조 CIDR(100.64/16) + custom networking 이주(16) + prefix delegation 적용. 교훈: ① Pending인데 자원이 남으면 IP부터(이벤트의 `failed to assign an IP`) ② 서브넷 설계는 처음에 크게 ③ IP 잔량은 알림 대상.
