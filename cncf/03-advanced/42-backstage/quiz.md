# 자가 점검 퀴즈

**Q1.** Backstage가 푸는 문제는? 24의 규모 문제 중 무엇인가(통신이 아니라)?

**Q2.** Backstage의 세 기둥과 각 역할은?

**Q3.** Software Catalog의 주요 Entity kind와 관계(edge)는?

**Q4.** catalog-info.yaml이 위키와 달리 "낡지 않는" 이유는?

**Q5.** Software Template이 하는 일과, 41(Crossplane)과 만나는 지점은?

**Q6.** IDP의 네 층(Backstage·Crossplane·GitOps·K8s)과 각 역할은?

**Q7.** "Backstage는 도구가 아니라 문화"의 의미는? 무엇이 없으면 실패하나요?

**Q8.** 언제 Backstage가 과한가? 관리형을 고려하는 이유는?

---

## 정답

**A1.** 마이크로서비스 규모가 만든 **발견성(discoverability)과 인지 부하** 문제입니다. 24는 서비스가 수백 개로 늘 때의 통신(메시 등)을 다뤘지만, 규모는 다른 문제도 만듭니다 — "무엇이 있고 누구 것이며 어디에 문서·배포가 있나"를 모르는 것(지식이 사람 머리·흩어진 도구에 분산). Backstage는 이 흩어진 것을 하나의 포털("single pane of glass")로 모아 발견 가능하게 합니다.

**A2.** ① Software Catalog — 모든 서비스·API·리소스의 목록+메타데이터+관계(무엇이 있고 누구 것인가). ② Software Templates(Scaffolder) — 새 프로젝트를 황금 경로로 스캐폴딩(레포·CI·문서·카탈로그·인프라를 한 번에). ③ TechDocs — docs-as-code, Markdown 문서가 레포에 살고 포털에서 렌더(문서가 코드와 함께). 여기에 플러그인(Kubernetes·CI·Grafana·보안)이 각 서비스 페이지에 통합됩니다.

**A3.** kind: Component(서비스·라이브러리 등 소프트웨어 단위), API(제공/소비되는 인터페이스), System(Component 묶음, 도메인 경계), Domain(System 상위), Resource(인프라 DB·버킷, 41과 연결), Group/User(조직·소유권). 관계: ownedBy(→Group, 누가 소유), partOf(→System, 어디 속함), providesApi/consumesApi(↔API, 제공·소비), dependsOn(→Resource, 무엇에 의존). 이 관계들이 24의 서비스 의존 그래프를 코드에서 자동으로 그립니다.

**A4.** catalog-info.yaml이 각 레포에 **코드 옆에 살기** 때문입니다 — 의존·소유가 바뀌면 코드 변경과 같은 PR에서 함께 수정되고(14의 코드 리뷰), 코드와 함께 버전 관리됩니다. 위키는 별도로 관리돼 코드가 바뀌어도 그대로 남아 시간이 지나면 거짓말이 되지만, catalog-info.yaml은 자동 수집되고 코드와 동기화돼 진실을 유지합니다(14 GitOps의 "코드가 진실의 원천"을 조직 지식에 적용).

**A5.** Software Template은 새 프로젝트를 황금 경로로 스캐폴딩합니다 — 파라미터 입력 → 스켈레톤 코드 → 레포 생성 → CI 설정 → 카탈로그 등록을 한 번에. 41과 만나는 지점: 템플릿 스텝이 Crossplane Claim(예: AppDatabase)을 생성해 인프라를 프로비저닝합니다. 즉 Backstage(UI)가 Crossplane(API)을 호출하는 곳 — 개발자가 "DB 필요" 체크박스를 켜면 뒤에서 41 lab-02의 Claim이 만들어져 실제 인프라가 조정됩니다. UI와 인프라 API의 결합점입니다.

**A6.** UI 층 — Backstage(42): 개발자 접점, 카탈로그·템플릿·문서. 인프라 API 층 — Crossplane(41): 셀프서비스 인프라 프로비저닝. 조정 층 — ArgoCD/Flux(14·15): GitOps로 앱·인프라 배포 조정. 런타임 층 — Kubernetes: Pod 실행. 흐름: 개발자가 Backstage에서 클릭 → 템플릿이 레포+Crossplane Claim+Argo App 생성 → GitOps·Crossplane이 조정 → K8s가 실행 → 런타임 현황이 다시 Backstage 플러그인으로 표시(피드백 루프).

**A7.** Backstage는 빈 프레임워크라 그것이 살아나려면 조직의 지속 참여가 필요하다는 뜻입니다 — 카탈로그는 팀들이 catalog-info.yaml을 관리해야 채워지고, 템플릿은 플랫폼 팀이 좋은 황금 경로를 만들어야 있고, 정확성은 각 팀이 자기 Entity를 소유해야 유지됩니다. 이것(팀 참여·플랫폼 팀·제품 사고)이 없으면 텅 비고 낡은 포털이 되어 아무도 안 씁니다("깔면 된다"의 착각). 성패는 90% 문화, 10% 도구 — 47의 "제품으로서의 플랫폼" 사고가 전제입니다.

**A8.** 과한 경우: 서비스가 10개 미만이면 README·슬랙으로 충분하고, 운영할 플랫폼 팀이 없으면 깔고 방치돼 낡은 포털이 됩니다. 관리형(Roadie·Spotify Portal)을 고려하는 이유: Backstage는 Node/React 앱+PostgreSQL+인증+플러그인으로 운영·업그레이드·플러그인 호환성 유지가 상당한 부담이라(39·40·41의 "설치의 쉬움 ≠ 운영의 쉬움"), 전담 인력이 없으면 관리형으로 운영 부담을 덜고 황금 경로·문화에 집중하는 것이 낫습니다(관리형 우선 판단).
