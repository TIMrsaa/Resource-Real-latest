# 자가 점검 퀴즈

**Q1.** 추상 사다리 5단을 나열하고 각 단의 질문과 대표 프로젝트를 말하세요.

**Q2.** "Helm vs ArgoCD"가 성립하지 않는 이유를 lab-02에서 확인한 사실로 설명하세요.

**Q3.** Helm과 Kustomize의 설계 철학 차이와, 각각이 빛나는 자리는? 실무의 표준 조합은?

**Q4.** 렌더링 시점 논쟁(CI 렌더 vs CD 렌더)의 트레이드오프와, cicd 14의 어떤 문제와 연결되나요?

**Q5.** 오퍼레이터 패턴이 "사다리를 관통한다"는 말의 의미와, 이 커리큘럼에서 만난 오퍼레이터 넷을 들어라.

**Q6.** 5단의 네 주민(Knative/Dapr/Crossplane/Backstage)이 각각 "무엇 위의 추상"인가요?

**Q7.** 추상 누수란 무엇이고, 5단 도입의 전제 질문은?

**Q8.** Operator Capability Level이 채택 판단에 왜 중요한가? L3 미만이면 무엇이 우리 몫인가요?

---

## 정답

**A1.** 1단 매니페스트("무엇을 원하는가" — Deployment YAML), 2단 패키징("재사용·환경별 변형은?" — Helm·Kustomize), 3단 배달("누가 클러스터에 반영·수렴?" — ArgoCD·Flux), 4단 점진 전환("어떻게 안전하게 바꾸나요?" — Argo Rollouts·Flagger), 5단 상위 추상("K8s를 덜 알고도 되게?" — Knative·Dapr·Crossplane·Backstage·KubeVirt). 비교는 같은 단끼리만 성립합니다.

**A2.** 다른 단(2단 vs 3단)이고 소비 관계입니다 — ArgoCD의 repo-server는 source path에 Chart.yaml이 있으면 `helm template`을, kustomization.yaml이 있으면 `kustomize build`를 실행해 매니페스트를 렌더링한 뒤, application-controller가 그것을 클러스터와 비교합니다(lab-02 Step 5에서 repo-server 이미지에 helm·kustomize 바이너리가 내장된 것을 확인). 즉 Helm은 ArgoCD의 입력 형식이지 경쟁자가 아닙니다.

**A3.** Helm: Go 템플릿 + values — YAML을 문자열로 다루며 렌더링 후에야 유효한 YAML이 됩니다. 버저닝·차트 저장소·Release 상태 추적이 강점 → **남에게 배포할 소프트웨어**. Kustomize: 베이스 + 오버레이 패치 — 템플릿 문법 없이 항상 유효한 YAML, 병합만 합니다 → **우리 조직의 환경별 변형**. 표준 조합: 외부 컴포넌트는 Helm 차트로 설치, 우리 앱은 Kustomize 오버레이, 그리고 ArgoCD/Flux가 둘 다 렌더링해 배달.

**A4.** CD 렌더(Git에 차트+values): 저장소가 단순하고 업스트림 차트 갱신이 쉽지만, PR diff가 values 한 줄이라 실제 매니페스트 변화(사이드카 추가 등)가 리뷰에 안 보입니다. CI 렌더(rendered manifests): CI가 완성 YAML을 커밋 — diff가 정직해 감사·리뷰에 강하지만 저장소가 커지고 파이프라인이 한 겹 늡니다. 연결: cicd 14의 "Git이 진실"의 **정밀도** 문제 — Git이 진실이라도 그 진실의 해상도가 낮으면 무엇이 배포될지 사람이 모릅니다.

**A5.** CRD(새 리소스 타입) + 컨트롤러(reconcile 루프) = 운영 지식의 코드화라는 패턴이, 사다리의 특정 단에 속하지 않고 모든 단에서 확장 문법으로 쓰인다는 뜻. 이 커리큘럼의 오퍼레이터들: Rook(05 — Ceph 운영), cert-manager(07 — 인증서), ArgoCD 자신(cicd 14 — 앱 배달), Karpenter(eks 17 — 노드), Crossplane(클라우드 리소스), Strimzi(Kafka). 02에서 "K8s가 이긴 이유 = 확장 지점"이라 했던 것의 열매.

**A6.** Knative: 워크로드(서빙·이벤트) 위 — 스케일 투 제로, 리비전·트래픽 분할. Dapr: 앱 코드(런타임) 위 — 사이드카 API로 상태·pub/sub·시크릿·서비스 호출을 언어 중립으로. Crossplane: 클라우드 인프라 위 — RDS·S3·VPC를 K8s 리소스로(오퍼레이터의 극단). Backstage: 조직·개발자 경험 위 — 서비스 카탈로그·스캐폴딩 템플릿·문서 포털. 네 개 모두 "K8s 위"지만 덮는 대상이 워크로드/코드/인프라/조직으로 다릅니다.

**A7.** 추상 누수: 상위 추상이 "아래를 몰라도 된다"고 약속하지만, 장애가 나면 아래 단의 개념·에러를 반드시 봐야 하는 현상(Knative Ready 실패의 원인이 Pod 이미지 pull 에러, Crossplane 정지의 원인이 IAM 권한). 5단 도입의 전제 질문: 기능 비교가 아니라 "**덮이는 아래 단을 팀이 아는가**" — 모르면 정상 경로는 편하고 장애 경로는 마비됩니다. (그래서 이 커리큘럼이 k8s를 먼저 45개 모듈로 다뤘습니다.)

**A8.** Capability Level(L1 설치 → L2 무중단 업그레이드 → L3 백업·복구·페일오버 → L4 인사이트 → L5 오토파일럿)은 "이 오퍼레이터에 운영을 어디까지 맡길 수 있나"의 채점표입니다. helm install로 쉽게 뜨는 것과 운영을 맡길 수 있는 것은 다릅니다. **L3 미만이면 백업·복구·페일오버는 우리 몫**이고, 그 절차는 문서로 존재하는 것을 넘어 Game Day(k8s 36)로 리허설돼야 합니다 — 05의 사고 사례가 이 확인을 건너뛴 대가였습니다.
