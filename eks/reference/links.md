# 링크 모음 — 1차 자료 우선

> 블로그보다 소스와 공식 문서. 버전이 바뀌면 블로그는 거짓말이 되지만 소스는 그렇지 않습니다.

## 공식 문서 (일상)

- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/) — 모든 것의 출발점
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/) — 보안·안정성·비용·성능 4권. **가장 저평가된 자료**이자 문서 기여의 첫 목적지 (27)
- [EKS 버전 수명주기](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) — 21의 버전 정책 근거
- [Kubernetes 공식 문서](https://kubernetes.io/docs/) / [폐기 API 가이드](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

## 소스 코드 (진실)

| 저장소 | 무엇이 있나 | 모듈 |
|--------|-----------|------|
| [amazon-vpc-cni-k8s](https://github.com/aws/amazon-vpc-cni-k8s) | ipamd(datastore·warm), CNI 플러그인(veth·route), `docs/` 설계문서 | 07·16·18·29 |
| [aws-load-balancer-controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller) | ALB/NLB reconcile, annotation 사전 | 08·14 |
| [kubernetes-sigs/karpenter](https://github.com/kubernetes-sigs/karpenter) | 코어: 스케줄링 시뮬레이터, consolidation | 17·28 |
| [karpenter-provider-aws](https://github.com/aws/karpenter-provider-aws) | 인스턴스 타입·가격, EC2 Fleet, EC2NodeClass | 17·28 |
| [aws-ebs-csi-driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver) / [efs](https://github.com/kubernetes-sigs/aws-efs-csi-driver) | 볼륨 프로비저닝·스냅샷 | 10 |
| [aws-network-policy-agent](https://github.com/aws/aws-network-policy-agent) | NetworkPolicy의 eBPF 집행 | 18 |
| [secrets-store-csi-driver](https://github.com/kubernetes-sigs/secrets-store-csi-driver) | 외부 시크릿 마운트 | 25 |
| [velero](https://github.com/vmware-tanzu/velero) | 백업/복원 파이프라인 | k8s 36 · 24 |
| [opencost](https://github.com/opencost/opencost) | 비용 배분 명세 | 22 |
| [istio](https://github.com/istio/istio) / [envoy](https://github.com/envoyproxy/envoy) | 메시 control/data plane | 20 |

## 기여 통로 (27)

- [aws/containers-roadmap](https://github.com/aws/containers-roadmap) — 코드 없는 저장소, 이슈로 로드맵에 영향
- [AWS Health Dashboard](https://health.aws.amazon.com/) — "AWS 쪽 사건인가" 확인 (26의 ① 계층)
- 서포트 케이스 — "내 클러스터의 문제"(비공개, SLA) ⚖️ 로드맵 이슈 — "제품의 문제"(공개)

## 도구

| 도구 | 용도 | 모듈 |
|------|------|------|
| [eksctl](https://eksctl.io) | 클러스터 선언 | 02 |
| [k6](https://k6.io) / [vegeta](https://github.com/tsenart/vegeta) | closed / **open** 부하 모델 | 13 |
| [netshoot](https://github.com/nicolaka/netshoot) | Pod 안 네트워크 진단 | 18·26 |
| [Pluto](https://github.com/FairwindsOps/pluto) | 폐기 API 정적 스캔 | k8s 35 · 21 |
| [KEDA](https://keda.sh) / [prometheus-adapter](https://github.com/kubernetes-sigs/prometheus-adapter) | 이벤트/커스텀 메트릭 스케일링 | 15 |
| [vCluster](https://www.vcluster.com) | 가상 클러스터 | k8s 34 · 23 |
| [skopeo](https://github.com/containers/skopeo) | multi-arch manifest 검사 | 19 |
| [eks-node-viewer](https://github.com/awslabs/eks-node-viewer) | 노드 사용률·비용 실시간 | 17·22 |

## 읽을 만한 것 (개념)

- Gil Tene, *How NOT to Measure Latency* — coordinated omission의 원전 (13)
- [AWS DR 백서](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/) — 4전략의 출처 (k8s 36 · 24)
- [CNI 명세](https://github.com/containernetworking/cni/blob/main/SPEC.md) — 모든 CNI 플러그인의 계약 (29)
- [kubefed (archived)](https://github.com/kubernetes-retired/kubefed) — 실패에서 배우기 (23)
- Karpenter 워킹그룹 미팅(공개 캘린더) — 설계 논의를 실시간으로 (28)

## 이 커리큘럼의 다음

- **cicd 파트** — Code 시리즈, GitHub Actions, GitOps 파이프라인
- **cncf 파트** — Prometheus/Grafana 본격, 랜드스케이프 실습
- **k8s 41~45** — 업스트림 기여 (빌드·코드투어·KEP·테스트·첫 PR)
