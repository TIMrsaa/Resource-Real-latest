# Part 4 — CNCF 랜드스케이프 전체 ✅ (50개 모듈 + reference 완료)

> **목표**: CNCF 랜드스케이프 200+ 프로젝트를 카테고리별로 **전수 파악**하고, Graduated 전 프로젝트(~35개)를 핸즈온으로 심층 학습하며, 최종적으로 원하는 프로젝트에 기여자로 합류하는 것.
> **선행**: k8s / eks / cicd 파트
> **주의**: Graduated/Incubating 목록은 작성 시점에 landscape.cncf.io 에서 재확인 (최신 합류: Dragonfly, 2026-01)

---

## 구성 방식

1. **랜드스케이프 전수 지도** (`01-beginner/`) — 카테고리별로 200+ 프로젝트 전부를 한 줄 이상 소개. "이 동네에 뭐가 있는지" 지도를 먼저 그립니다.
2. **Graduated 심층 모듈** (`02-intermediate/` ~ `03-advanced/`) — 프로젝트당 1모듈: theory + 핸즈온(EKS 위 설치/운영) + 내부 구조
3. **실무 조합 패턴** (`04-production/`) — 프로젝트들을 조합한 레퍼런스 아키텍처
4. **기여 트랙** (`05-contributor/`) — CNCF 거버넌스 이해 + 실제 기여

## 진도 체크리스트 (작성 예정 목차)

### 01-beginner — 랜드스케이프 전수 지도 ✅ (작성 완료)
- [x] **01-cncf-overview** — 재단 구조(GB↔TOC 분리), 성숙도 3단계, landscape를 데이터로, 심사관의 눈 5종
- [x] **02-map-orchestration** — K8s가 이긴 구조적 이유, 배치(갱 스케줄링 재현)·멀티클러스터·엣지·Nomad의 BSL
- [x] **03-map-runtime** — **층**: CRI(containerd/CRI-O) vs OCI(runc/crun), 격리 스펙트럼(gVisor·Kata), 체인 해부
- [x] **04-map-networking** — **층·계보**: CNI/DNS/프록시/메시, Envoy 계보도, eBPF 지각 변동, Cilium 시식
- [x] **05-map-storage** — **역할**: 시스템 vs 오케스트레이터(Rook은 스토리지가 아닙니다), CSI 사이드카 해부, 데이터 중력
- [x] **06-map-observability** — **격자**(신호×단계), OTel의 경계(수집·전송까지), Collector = "관측의 CSI"
- [x] **07-map-security** — **시간선**: 빌드전/배포시점/런타임 + 신원, Kyverno(예방) vs Falco(탐지) 시식
- [x] **08-map-app-delivery** — **사다리** 5단, Helm vs Kustomize 철학, 오퍼레이터 관통, 추상 누수
- [x] **09-map-data-streaming** — etcd의 필연(watch·lease 실습), 큐 vs 스트림, **스테이트풀 판단 프레임**
- [x] **10-map-platform-misc** — 나머지 다섯 갈래, 플랫폼 엔지니어링, **종합 지도·판단 순서도**(졸업 과제)

### 02-intermediate — Graduated 심층 1차 ✅ (작성 완료)
- [x] **11-prometheus** — pull의 철학, TSDB(head/WAL/블록), **카디널리티의 물리학**(폭발 재현), PromQL 함정
- [x] **12-opentelemetry** — 컨텍스트 전파(W3C traceparent), 시맨틱 컨벤션, Collector 파이프라인, head vs tail 샘플링
- [x] **13-jaeger** — 트레이스 저장의 난제, 백엔드 축("trace_id를 어디서 얻는가"), v2의 OTel 이사, **조사 동선**
- [x] **14-fluentd-fluentbit** — 로그의 경로, 버퍼·백프레셔(유실의 물리학), 구조화 로깅으로 **동선 완성**
- [x] **15-helm-internals** — 발명품은 템플릿이 아니라 **릴리스**, 3-way 병합, 훅의 위험, GitOps와의 긴장
- [x] **16-argocd** — 규모(부하 해부·샤딩·감춰진 watch 부하), 멀티클러스터 3형태, ApplicationSet의 삭제 위험, 거버넌스 2층
- [x] **17-flux** — 툴킷 철학(컨트롤러 조합), HelmRelease가 릴리스를 살립니다, 이미지 자동화, SA 임퍼소네이션 테넌시
- [x] **18-keda** — HPA를 **생성**하는 통역사, activation vs scaling, ScaledJob, 콜드스타트, 진단 4층
- [x] **19-cert-manager** — 리소스 체인, ACME 챌린지·rate limit, 내부 CA, **전파의 마지막 홉**(subPath·env 함정)
- [x] **20-coredns-deep** — 플러그인 체인, **ndots:5 증폭**, 5초 지연의 진범(conntrack), NodeLocal DNSCache
- [x] **21-etcd-as-project** — Raft·쿼럼, MVCC·컴팩션/디프래그(space exceeded 복구), **fsync가 클러스터를 정합니다**, 백업·복구

### 03-advanced — Graduated 심층 2차 (네트워크/런타임/보안/데이터/플랫폼) ✅ (작성 완료)
- [x] **22-cilium** — eBPF 실행 모델(검증기·맵), **identity 기반 정책**, kube-proxy 대체, Hubble(판정=관찰 지점)
- [x] **23-envoy** — 4계층(listener/route/cluster/endpoint), **xDS**(설정을 스트림으로), 계보의 정체, 복원력·config_dump
- [x] **24-istio** — istiod=번역기, CRD→Envoy, mTLS 마이그레이션, **ambient**(사이드카 제거), "메시는 비용 구조"
- [x] **25-linkerd** — 단순함이라는 설계, Rust 전용 프록시, 자동 mTLS, **기능 최대(Istio) vs 운영 최소(Linkerd)**
- [x] **26-containerd** — 플러그인 데몬·CRI 흐름·shim v2(재시작에도 생존), 스냅샷터·확장(runwasi), crictl/ctr 진단
- [x] **27-cri-o** — K8s 전용 미니멀리즘, K8s 정렬 버저닝, containers/ 생태계, "범위를 좁히는 것도 설계"
- [x] **28-kubevirt** — VM in Pod(virt-launcher가 QEMU를), K8s(무상태) vs VM(상태) 긴장, 드레인=라이브 마이그레이션
- [x] **29-dapr** — 앱 코드 위의 추상, 빌딩블록·컴포넌트 이식성, 메시와의 차이(앱 관심사 vs 네트워크), 새 신뢰 지점
- [x] **30-falco** — 07 시간선의 런타임 탐지, 시스템콜(eBPF), 규칙 언어, 탐지≠예방, Tetragon·seccomp 비교
- [x] **31-opa** — 결정 분리(PDP), **rego 선언적 사고**, Gatekeeper, 하나의 엔진 다영역(admission·CI·앱)
- [x] **32-kyverno** — 정책을 K8s YAML로, 네 규칙(validate/mutate/generate/verifyImages), OPA vs Kyverno 최종
- [x] **33-spiffe-spire** — 워크로드 신원, 어테스테이션(주장 아닌 증명), **부트스트랩 신뢰**, 07 신원 축 통일
- [x] **34-harbor** — 레지스트리=공급망 관문, 스캔·서명·정책 통합(21), OCI 아티팩트, 프록시 캐시(25), 신뢰 경계
- [x] **35-dragonfly** — 대규모 이미지 배포 병목, **P2P**(BitTorrent 원리), 지연로딩 결합, AI 워크로드, 규모의 임계
- [x] **36-vitess** — MySQL 수평 샤딩, VTGate/VTTablet, **복제≠백업**, 09의 스테이트풀 판단 극단
- [x] **37-tikv** — Region/multi-Raft(21), PD의 위치 조회, **핫스팟의 물리**(자동화가 물리를 숨기지만 없애지 않음)
- [x] **38-nats** — core(경량 pub/sub) vs JetStream(영속·Raft), 큐 vs 스트림(09), 엣지·실시간
- [x] **39-rook** — Rook은 스토리지가 아닙니다(오퍼레이터), Ceph(OSD/MON/CRUSH), **시스템 vs 오케스트레이터**(05)
- [x] **40-strimzi-cloudevents** — Strimzi=Kafka 오퍼레이터(39와 동형), **CloudEvents**(이벤트 표준, 06·03 계열), 이벤트 아키텍처
- [x] **41-crossplane** — K8s API=범용 컨트롤 플레인(08 확장), 4층(Provider/MR/Composition/Claim), Terraform 대비
- [x] **42-backstage** — 개발자 포털(IDP), Catalog/Templates/TechDocs, **도구가 아니라 문화**, 41과 짝(UI↔API)
- [x] **43-knative** — 서버리스(scale-to-zero·Activator/KPA), 리비전·트래픽, Eventing(40), **콜드스타트의 대가**
- [x] **44-karpenter-cncf** — 노드 오토스케일(Pod층↔노드층), CA vs Karpenter(JIT·빈패킹·통합), 중단내성(PDB)
- [x] **45-incubating-roundup** — 범주별 라운드업(Thanos·Karmada·Volcano…), **항해술**(지도에 놓는 5단계, 05 완성)

### 04-production — 실무 조합 ✅ (작성 완료)
- [x] **46-reference-platform** — 플랫폼의 **층·의존·순서**(cert-manager·관측 먼저), app-of-apps+sync-wave 조립, 점진 도입(빅뱅 금지)
- [x] **47-platform-engineering** — **인지 부하 재배치**, Team Topologies, IDP(41+42+46), 황금 경로(pave not fence), **제품으로서의 플랫폼**(측정: 채택률·DORA)
- [x] **48-comparison-guides** — **3층 비교**(기능→철학→조직 적합), 대결 종합(GitOps·메시·정책·메시징·IaC·노드), PoC 설계·ADR(재평가 조건)

### 05-contributor — 기여 트랙 ✅ (작성 완료)
- [x] **49-cncf-governance** — GB↔TOC 분리(벤더 중립), TAG(진입로), 졸업 심사(공개 실사), K8s SIG·KEP, **거버넌스 문서 정찰**(GOVERNANCE·OWNERS·ladder)
- [x] **50-contributing-path** — 대상 선정(관심×역량×거버넌스), 코드 밖 기여(문서·트리아지·재현), 이슈·PR의 기술과 예절, LFX·KubeCon, **ladder 오르기**(졸업장 = 기여 이력)

### reference ✅ (작성 완료)
- [x] landscape-full-table.md (축별 전수 표 + 항해술) / glossary.md (용어·관통 원리) / links.md

---

## 학습 순서 요약

1. **01~10 (지형)**: 랜드스케이프 전체를 축(orchestration~platform)으로 지도화 — MY-MAP.md가 졸업 과제
2. **11~21 (심층 1차)**: 관측(11~14)·배포(15~18)·인프라 코어(19~21)
3. **22~45 (심층 2차)**: 네트워크·메시(22~25)·런타임(26~29)·보안(30~35)·데이터(36~40)·플랫폼(41~44)·라운드업(45)
4. **46~48 (production)**: 층으로 조립(46) → 제품으로 운영(47) → 조직에 맞게 선택(48)
5. **49~50 (contributor)**: 거버넌스 지도(49) → 실제 기여(50) — **커리큘럼의 목적지**

> 이 파트의 졸업장은 자격증이 아니라 **기여 이력**입니다 — 50 lab-01의 체크리스트(첫 이슈·첫 재현·첫 PR)를 실제로 수행하는 것이 최종 과제.
