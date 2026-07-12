# CNCF 파트 용어집

> Part 4에서 등장한 핵심 용어. (모듈 번호)는 심층 설명 위치.

## 재단·거버넌스 (01·49)

| 용어 | 뜻 |
|---|---|
| CNCF | Cloud Native Computing Foundation — 클라우드 네이티브 오픈소스의 중립 재단(Linux Foundation 산하) |
| GB (Governing Board) | 기업 회원으로 구성, 예산·전략 담당(돈) — 기술엔 관여 불가 |
| TOC | Technical Oversight Committee — 선출 11인, 프로젝트 승인·졸업 심사(기술) |
| TAG | Technical Advisory Group — 도메인별 기술 자문(Security·Observability 등), 참여 장벽 낮음 |
| Sandbox / Incubating / Graduated | 성숙도 3단계 — 실험 / 성장 증명 / 엄격 심사 졸업 |
| Due Diligence | 승격·졸업 시 TOC의 실사(기여자 다양성·보안 감사·채택) |
| SIG | Special Interest Group — K8s의 영역별 분권 조직(Node·Network·Docs...) |
| KEP | Kubernetes Enhancement Proposal — 기능 제안 문서(SIG 승인 필요) |
| OWNERS / CODEOWNERS | 디렉터리별 reviewers·approvers 지정 파일 |
| DCO | Developer Certificate of Origin — `git commit -s` 서명(기여 권리 증명) |
| contributor ladder | Contributor→Member→Reviewer→Approver→Maintainer 성장 사다리 |
| LFX Mentorship | CNCF 공식 멘토링 프로그램(기수제) |
| CLOTributor | CNCF 기여 기회 검색 도구 |

## 관측 (06·11~14)

| 용어 | 뜻 |
|---|---|
| 골든 시그널 | 지연·트래픽·에러·포화 — 서비스 건강의 4대 신호 |
| 카디널리티 | 라벨 조합의 수 — 폭발하면 Prometheus 메모리·성능 붕괴(11) |
| TSDB | 시계열 DB — head(메모리)·WAL·블록 구조(11) |
| PromQL | Prometheus 쿼리 언어 |
| 컨텍스트 전파 | trace context(W3C traceparent)를 요청 경로로 전달(12) |
| 시맨틱 컨벤션 | OTel의 표준 속성 명명(12) |
| head/tail 샘플링 | 추적 샘플링 — 시작 시 결정 vs 완료 후 결정(12) |
| Collector | OTel의 수집 파이프라인(receive→process→export) — "관측의 CSI"(06·12) |
| 백프레셔 | 하류가 밀리면 상류를 조절 — 로그 버퍼·유실의 물리(14) |

## GitOps·배포 (15~18·43)

| 용어 | 뜻 |
|---|---|
| 릴리스(Helm) | 차트 설치의 상태 단위 — Helm의 진짜 발명품(15) |
| 3-way 병합 | 이전 매니페스트·현재 상태·새 매니페스트의 병합(15) |
| app-of-apps | 루트 Application이 다른 Application들을 배포(16·46) |
| sync-wave | ArgoCD 동기화 순서 제어(16·46) |
| ApplicationSet | 여러 클러스터·환경에 Application 생성 자동화(16) |
| 툴킷(Flux) | 단일 앱이 아닌 컨트롤러 조합 철학(17) |
| ScaledObject/ScaledJob | KEDA의 스케일 대상 선언(18) |
| activation vs scaling | KEDA의 0↔1(activation)과 1↔N(scaling) 구분(18) |
| scale-to-zero | 요청·이벤트 없으면 Pod 0 — Activator가 가능케 함(43) |
| Activator / KPA | Knative의 요청 붙잡기 / 요청 기반 오토스케일러(43) |
| Revision | Knative의 불변 배포 스냅샷 — 트래픽 %분배(43) |
| 콜드 스타트 | 0→1에서 첫 요청이 기다리는 지연(43) |

## 네트워크·메시 (20·22~25)

| 용어 | 뜻 |
|---|---|
| 플러그인 체인 | CoreDNS의 요청 처리 구조(20) |
| ndots:5 | K8s DNS 검색 도메인 증폭의 주범(20) |
| conntrack 경합 | UDP DNS 5초 지연의 진범(20) |
| eBPF | 커널 내 안전한 프로그램 실행(검증기·맵)(22) |
| identity 기반 정책 | IP가 아닌 워크로드 신원으로 정책(Cilium)(22) |
| xDS | Envoy의 동적 설정 스트림 API(23) |
| listener/route/cluster/endpoint | Envoy 설정 4계층(23) |
| mTLS | 상호 TLS — 양방향 신원 검증(24·33) |
| ambient | Istio의 사이드카 제거 모드(ztunnel·waypoint)(24) |
| 사이드카 | Pod에 주입되는 프록시 컨테이너 — 메시의 비용 구조(24) |

## 런타임·보안 (26~34)

| 용어 | 뜻 |
|---|---|
| shim v2 | containerd와 런타임 사이 — 데몬 재시작에도 컨테이너 생존(26) |
| 스냅샷터 | containerd의 레이어 관리(26) |
| 어테스테이션 | 신원의 "주장이 아닌 증명"(SPIRE)(33) |
| SVID | SPIFFE Verifiable Identity Document(33) |
| 부트스트랩 신뢰 | 첫 신뢰를 어떻게 세우나(33) |
| PDP/PEP | 정책 결정점/집행점 분리(OPA)(31) |
| rego | OPA의 선언적 정책 언어(31) |
| validate/mutate/generate/verifyImages | Kyverno 규칙 4종(32) |
| 탐지 vs 예방 | Falco(탐지) ↔ 정책·seccomp(예방)(30) |
| OCI 아티팩트 | 이미지 외 산출물(차트·SBOM)을 레지스트리에(34) |
| P2P 배포 | Dragonfly — 대규모 이미지 풀 병목 해소(35) |

## 데이터 (36~40)

| 용어 | 뜻 |
|---|---|
| 샤딩 | 데이터 수평 분할(Vitess)(36) |
| VTGate/VTTablet | Vitess 라우터/샤드 관리자(36) |
| Region / multi-Raft | TiKV 데이터 조각 / 조각별 Raft 그룹(37) |
| PD | TiKV의 위치·스케줄 관리(중앙 조회 — CRUSH와 대비)(37) |
| 핫스팟 | 특정 Region 집중 — 자동화가 못 없애는 물리(37) |
| core vs JetStream | NATS 경량 pub/sub vs 영속 스트림(Raft)(38) |
| OSD/MON/MGR/MDS | Ceph 컴포넌트(39) |
| CRUSH | Ceph 위치 계산 알고리즘(조회 없는 계산)(39) |
| RADOS/RBD/CephFS/RGW | Ceph 기반/블록/파일/오브젝트(39) |
| ISR / min.insync.replicas | Kafka 동기 복제본 관리(40) |
| CloudEvents | 이벤트 봉투 표준(specversion·type·source·id)(40) |
| structured/binary 바인딩 | CloudEvents 전송 두 방식(40) |
| 복제 ≠ 백업 | 복제는 하드웨어 장애용, 논리 손상엔 무력(21·36·39·40) |

## 플랫폼 (41~48)

| 용어 | 뜻 |
|---|---|
| Managed Resource | 클라우드 리소스와 1:1인 Crossplane CR(41) |
| XRD / Composition / Claim | 추상 API 정의 / 조합 정의 / 개발자 요청(41) |
| 지속 조정 | apply 일회성(Terraform)과 대비되는 상시 드리프트 교정(41) |
| deletionPolicy: Orphan | CR 삭제해도 실제 리소스 보존(41) |
| Entity / catalog-info.yaml | Backstage 카탈로그 항목 / 코드 옆 메타데이터(42) |
| Software Template | Backstage 스캐폴딩(황금 경로)(42) |
| TechDocs | docs-as-code(42) |
| NodePool / NodeClass | Karpenter 중립 제약 / 클라우드별 세부(44) |
| 통합(consolidation) | 비효율 노드 재편 — 비용↓ churn↑(44) |
| 빈패킹 | Pod를 최소 노드에 최적 배치(44) |
| IDP | 내부 개발자 플랫폼(41+42+46)(47) |
| 황금 경로 | 모범 내장 표준 경로 — pave not fence(47) |
| 인지 부하 재배치 | 복잡성을 개발자→플랫폼 팀으로(47) |
| Team Topologies | 스트림·플랫폼·활성화·난해한 하위시스템 팀 구조론(47) |
| X-as-a-Service | 플랫폼 팀의 셀프서비스 제공 모드(47) |
| 산출물 vs 결과 | output(만든 것) vs outcome(흐름이 빨라짐)(47) |
| 3층 비교 | 기능→철학→조직 적합(48) |
| PoC | 개념 검증 — 어려운 케이스+운영 시나리오로(48) |
| ADR | 결정 기록(맥락·대안·재평가 조건)(48) |

## 관통 원리 (여러 모듈)

| 원리 | 등장 |
|---|---|
| 표준이 이식성을 만듭니다 | 03(OCI)·06·12(OTel)·40(CloudEvents) |
| 시스템 vs 오케스트레이터 | 05·39(Rook≠스토리지)·40(Strimzi) |
| 설치의 쉬움 ≠ 운영의 쉬움 | 05·39·40·41·42 |
| 자동화는 물리를 숨기지만 없애지 않습니다 | 37·39·41·43·44 |
| 범위를 좁히는 것도 설계 | 27(CRI-O)·38·45 |
| 관리형 우선 | 09·36~40·42·47 |
| 힘에는 규율이 따릅니다 | 41(orphan)·42(문화)·44(PDB) |
| 복제 ≠ 백업 | 21·36·39·40·46 |
