# 흔한 함정 5선

## 1. "API 서버가 컨테이너를 만든다"는 오해

API 서버는 **저장과 알림**만 합니다. 컨테이너를 만드는 것은 그 노드의 kubelet+containerd. 그래서 "API 서버는 멀쩡한데 특정 노드만 Pod가 안 뜬다"는 상황이 가능합니다 — 그 노드의 kubelet/런타임 문제.

## 2. control plane이 죽으면 서비스도 죽는다는 오해

control plane 전체가 다운돼도 **이미 돌던 Pod와 Service 트래픽은 유지**됩니다 (kubelet/kube-proxy는 마지막 상태를 유지). 죽는 것은 "변화" — 새 배포, 장애 복구, 스케일링. 그래서 etcd 장애는 "즉사"가 아니라 "뇌사"다.

## 3. kubectl 버전 아무거나

kubectl은 서버와 **±1 마이너 버전** 이내여야 합니다 (1.36 서버 ↔ 1.35~1.37 kubectl). 너무 오래된 kubectl은 새 필드를 잘라먹는 식의 미묘한 버그를 만듭니다.

## 4. EKS 클러스터 생성 직후 `Unauthorized`

eksctl이 만든 kubeconfig는 IAM 자격증명으로 토큰을 만듭니다. 다른 IAM 사용자/역할로 전환했거나 SSO 세션이 만료되면 인증 실패. 해결: `aws eks update-kubeconfig --name k8s-study --region ap-northeast-2` + 현재 자격증명 확인(`aws sts get-caller-identity`).

## 5. 이벤트를 안 보고 디버깅 시작

`kubectl get events --sort-by=.lastTimestamp` 가 디버깅의 90%를 해결합니다. 이벤트에는 스케줄러/kubelet이 "왜 안 되는지"를 이미 적어놨습니다. 로그를 뒤지기 전에 이벤트부터 — lab-02에서 체득한 그 순서입니다. 단, 이벤트는 기본 1시간만 보관되므로 "방금" 일어난 일에만 유효합니다.

## 실무 사고 사례

> 야간에 etcd 디스크가 가득 차 control plane이 멈췄습니다. 모니터링은 "서비스 정상"(트래픽은 흐르니까)이라 아무도 몰랐고, 아침에 배포가 안 되면서 발견. 함정 2의 정확한 실사례 — **"서비스 정상 ≠ 클러스터 정상". control plane 헬스는 별도로 모니터링해야 합니다.** (EKS는 이걸 AWS가 해주는 것이 가치입니다.)
