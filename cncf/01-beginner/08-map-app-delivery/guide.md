# 학습 가이드 — 로고 늪을 사다리로 바꾸기

## 이 칸이 가장 혼란스러운 이유

App Definition & Development는 landscape에서 프로젝트가 가장 많이 몰린 칸입니다 — Helm, Kustomize, ArgoCD, Flux, Operator Framework, Crossplane, Backstage, Knative, Dapr, KubeVirt, Keptn... 공통점을 찾기 어려운 이 목록의 정체는 사실 하나입니다: **모두 "앱을 클러스터에 어떻게 존재하게 할 것인가"의 서로 다른 추상 높이**에 있습니다.

```
5단  상위 추상    Knative(서빙 추상) · Dapr(앱 런타임 추상) · Crossplane(인프라 추상) · Backstage(조직 추상)
4단  점진 전환    Argo Rollouts · Flagger              (cicd 17)
3단  배달        ArgoCD · Flux                        (cicd 14·15)
2단  패키징      Helm · Kustomize                     (k8s)
1단  매니페스트   YAML (Deployment, Service...)        (k8s 초급)
```

사다리를 그리면 "Helm vs ArgoCD"(다른 단), "Crossplane vs Helm"(다른 단), "Knative vs Dapr"(같은 단, 다른 대상)이 각각 왜 성립하거나 성립하지 않는지 즉시 판정됩니다. 03의 층, 04의 계보, 05의 역할, 06의 격자 — 그리고 여기서는 사다리. 지도 모듈의 반복 기술입니다.

## 이미 오른 세 칸

cicd 파트에서 3·4단을 깊게 밟았습니다(ArgoCD의 reconcile, Flux의 컨트롤러 조합, Rollouts의 AnalysisTemplate). k8s 파트에서 1·2단을 밟았습니다. 그래서 이 지도가 실제로 **새로 소개하는 것은 5단**입니다 — 그리고 5단이야말로 이 칸의 미래이자 함정입니다: 상위 추상은 강력한 만큼 "그 추상이 새는 순간"(k8s를 몰라도 된다더니 결국 k8s 에러를 봐야 하는 순간)의 대가가 큽니다.

## 5단을 구분하는 질문: "무엇 위의 추상인가요?"

```
Knative     → 워크로드(서빙) 위의 추상: 스케일-투-제로, 트래픽 분할, 이벤트
Dapr        → 앱 코드(런타임) 위의 추상: 상태·pub/sub·시크릿을 사이드카 API로
Crossplane  → 클라우드 인프라 위의 추상: RDS·S3를 K8s 리소스로(오퍼레이터의 극단)
Backstage   → 조직·개발자 경험 위의 추상: 서비스 카탈로그·템플릿·문서 포털
KubeVirt    → VM 위의 추상: 가상머신을 Pod처럼
```

네 개 다 "K8s 위에 무언가를 얹는다"지만 대상이 워크로드/코드/인프라/조직으로 전혀 다릅니다 — 이 구분이 47(플랫폼 엔지니어링)에서 IDP를 조립할 때의 부품 목록이 됩니다.

## 오퍼레이터라는 관통 개념

이 사다리를 관통하는 것이 오퍼레이터 패턴입니다 — Crossplane도, cert-manager(07)도, Rook(05)도, ArgoCD 자체도 오퍼레이터입니다. k8s 파트에서 "CRD + 컨트롤러 = 도메인 지식의 코드화"를 배웠다면, 이 지도는 그 패턴이 **생태계 전체의 확장 문법**임을 확인하는 자리입니다(02의 "K8s가 이긴 이유"가 여기서 열매를 맺습니다).
