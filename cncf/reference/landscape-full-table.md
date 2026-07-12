# CNCF 랜드스케이프 전수 표

> 축(01~10의 지도)별로 정리한 CNCF 프로젝트 표. **성숙도·목록은 계속 바뀝니다** — 최종 확인은 landscape.cncf.io (45의 항해술: 새 프로젝트는 축→연결→존재이유→성숙도로 위치시켜라).
> 표기: 🎓 Graduated / 🌱 Incubating / 🧪 Sandbox (작성 시점 기준, 재확인 필수) / **굵게** = 커리큘럼 심층 모듈 있음

## 1. 오케스트레이션·스케줄링 (02)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Kubernetes** | 🎓 | 컨테이너 오케스트레이션의 사실상 표준 | Part 1 전체 |
| Volcano | 🌱 | 배치·AI/ML·HPC 특화 스케줄러(gang scheduling) | 45 |
| Karmada | 🌱 | 멀티클러스터 워크로드 분배 | 45 |
| Open Cluster Management | 🧪→🌱 | 멀티클러스터 관리(허브-스포크) | 45 |
| kube-rs / 클라이언트들 | 🌱 | 언어별 K8s 클라이언트 | — |

## 2. 런타임 (03·25)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **containerd** | 🎓 | 범용 컨테이너 런타임(CRI), 사실상 디폴트 | 26 |
| **CRI-O** | 🎓 | K8s 전용 미니멀 런타임 | 27 |
| runc/crun (OCI) | 표준 | OCI 런타임(실제 컨테이너 생성) | 03 |
| gVisor / Kata | 외부·연계 | 강한 격리(유저스페이스 커널 / 경량 VM) | 03 |
| **KubeVirt** | 🎓 | VM을 Pod처럼(virt-launcher가 QEMU) | 28 |
| WasmEdge | 🧪 | WebAssembly 런타임(컨테이너 대안 격리) | 45 |
| Krustlet(보관) | 🧪 | Wasm kubelet(아카이브 — 45의 교훈) | — |

## 3. 네트워킹 (04·26·27)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Cilium** | 🎓 | eBPF 기반 CNI·보안·관측(Hubble) | 22 |
| **CoreDNS** | 🎓 | K8s DNS(플러그인 체인) | 20 |
| **Envoy** | 🎓 | L7 프록시(xDS) — 메시·게이트웨이의 기반 | 23 |
| CNI(스펙) | 🌱 | 컨테이너 네트워크 인터페이스 표준 | 04 |
| Antrea | 🧪→🌱 | OVS 기반 CNI | 45 |
| Kube-OVN | 🧪 | OVN 기반 CNI(풍부한 기능) | 45 |
| Submariner | 🧪 | 클러스터 간 Pod 네트워크 연결 | 45 |
| Network Service Mesh | 🧪 | L2/L3 네트워크 서비스 체이닝 | — |

## 4. 서비스 메시 (24·25)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Istio** | 🎓 | 기능 최대 메시(istiod·ambient) | 24 |
| **Linkerd** | 🎓 | 운영 최소 메시(Rust 전용 프록시) | 25 |
| Open Service Mesh(보관) | 보관 | MS의 메시(아카이브) | — |
| SMI(보관) | 보관 | 메시 표준 시도(Gateway API로 흡수 흐름) | — |

## 5. 스토리지·데이터 (05·36~40)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Rook** | 🎓 | Ceph 오퍼레이터("Rook은 스토리지가 아니다") | 39 |
| **etcd** | 🎓 | K8s의 두뇌(Raft·MVCC·watch) | 21 |
| **Vitess** | 🎓 | MySQL 수평 샤딩(VTGate/VTTablet) | 36 |
| **TiKV** | 🎓 | 분산 KV(Region·multi-Raft·PD) | 37 |
| **CubeFS** | 🎓 | 분산 파일시스템 | 05 |
| Longhorn | 🌱 | 경량 분산 블록 스토리지 | 05·39 |
| OpenEBS | 🧪 | 컨테이너 어태치드 스토리지 | 45 |
| **NATS** | 🌱 | 경량 메시징(core pub/sub + JetStream) | 38 |
| **Strimzi** | 🌱 | Kafka 오퍼레이터 | 40 |
| **CloudEvents** | 🎓 | 이벤트 봉투 형식 표준 | 40 |
| Pravega / Kafka(외부) | 🧪/외부 | 스트림 저장 / (Kafka는 ASF) | 09 |

## 6. 관측 가능성 (06·11~14)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Prometheus** | 🎓 | 메트릭 사실상 표준(pull·TSDB·PromQL) | 11 |
| **OpenTelemetry** | 🌱(사실상 표준) | 텔레메트리 수집·전파 표준(신호 3종) | 12 |
| **Jaeger** | 🎓 | 분산 추적 백엔드 | 13 |
| **Fluentd** | 🎓 | 로그 수집·라우팅 | 14 |
| Fluent Bit | (Fluentd 산하) | 경량 로그 수집기 | 14 |
| Thanos | 🌱 | Prometheus 장기 저장·글로벌 쿼리 | 45 |
| Cortex | 🌱 | 멀티테넌트 Prometheus | 45 |
| OpenMetrics | 🌱→통합 | 메트릭 노출 형식(Prometheus에 통합 흐름) | 11 |
| Pixie | 🧪 | eBPF 자동 관측 | 45 |
| OpenCost | 🌱 | 비용 관측(FinOps) | 45 |
| Loki / Grafana / Mimir | 외부(GrafanaLabs) | 로그의 Prometheus식 / 대시보드 / 대규모 메트릭 | 45 |

## 7. 보안·신원·정책 (07·19·28·30~34)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Falco** | 🎓 | 런타임 위협 탐지(syscall·eBPF) | 30 |
| **OPA** | 🎓 | 범용 정책 엔진(rego·PDP) | 31 |
| **Kyverno** | 🌱→🎓 트랙 | K8s 네이티브 정책(YAML) | 32 |
| **SPIFFE/SPIRE** | 🎓 | 워크로드 신원(어테스테이션) | 33 |
| **cert-manager** | 🎓 | 인증서 자동화(ACME·내부 CA) | 19 |
| **Harbor** | 🎓 | 레지스트리(스캔·서명·프록시 캐시) | 34 |
| **TUF** | 🎓 | 업데이트 신뢰 프레임워크 | cicd 21 |
| Notary | 🌱 | 아티팩트 서명 | 45 |
| in-toto | 🌱→🎓 트랙 | 공급망 단계 증명(SLSA 기반) | 45·cicd 21 |
| Keylime | 🧪→🌱 | 원격 증명(TPM) | 45 |
| Kubescape | 🧪→🌱 | K8s 설정·컴플라이언스 스캔 | 45 |
| external-secrets / Vault(외부) | 🧪/외부 | 시크릿 동기화 / 시크릿 관리 | cicd 23 |
| sigstore/cosign(외부·LF) | 외부 | 서명 생태계 | cicd 21 |

## 8. 앱 정의·배포·GitOps (08·13·15~18·43)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Helm** | 🎓 | 패키지 매니저(릴리스·3-way 병합) | 15 |
| **Argo** (CD·Workflows·Rollouts·Events) | 🎓 | GitOps·워크플로 스위트 | 16 |
| **Flux** | 🎓 | GitOps 툴킷(컨트롤러 조합) | 17 |
| **KEDA** | 🎓 | 이벤트 기반 오토스케일(HPA 생성) | 18 |
| **Knative** | 🌱→🎓 트랙 | K8s 서버리스(Serving·Eventing) | 43 |
| **Dapr** | 🎓 | 분산 앱 런타임(빌딩블록) | 29 |
| **KubeEdge** | 🌱 | 엣지 컴퓨팅 확장 | 10 |
| Kustomize(K8s 산하) | — | 오버레이 구성 관리 | 08 |
| Operator Framework | 🌱 | 오퍼레이터 개발 프레임워크 | 08 |
| Keptn | 🌱 | 이벤트 기반 배포·SLO 오케스트레이션 | 45 |
| Score | 🧪 | 워크로드 명세 추상(플랫폼 이식) | 45 |
| Devfile | 🧪→🌱 | 개발 환경 정의 표준 | 45 |

## 9. 플랫폼·인프라·도구 (10·41·42·44)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| **Crossplane** | 🌱→🎓 트랙 | K8s API로 인프라 조정(Composition) | 41 |
| **Backstage** | 🌱 | 개발자 포털(Catalog·Templates·TechDocs) | 42 |
| **Karpenter** | (K8s 산하) | JIT 노드 프로비저닝·통합 | 44 |
| Cluster API | (K8s SIG) | 클러스터 자체를 선언형으로 | 10 |
| **Dragonfly** | 🎓 | P2P 이미지·파일 배포 | 35 |
| Buildpacks | 🌱 | Dockerfile 없는 이미지 빌드 | cicd |
| Telepresence | 🧪→🌱 | 로컬↔클러스터 개발 연결 | — |
| Meshery | 🧪→🌱 | 메시 관리 도구 | — |
| Headlamp | 🧪 | K8s UI | — |

## 10. CI/CD (cicd 파트 연계)

| 프로젝트 | 성숙도 | 한 줄 | 커리큘럼 |
|---|---|---|---|
| Tekton(외부·CDF) | CDF | K8s 네이티브 파이프라인 | cicd |
| Jenkins/Spinnaker(외부·CDF) | CDF | 전통 CI / 배포 | cicd |
| GitHub Actions(상용) | — | 사실상 표준 CI 플랫폼 | cicd |
| BuildKit(외부) | — | 빌드 엔진(LLB) | cicd 19 |

## 사용법 (45의 항해술)

```
새 프로젝트를 만나면:
  1. 이 표의 어느 축(1~10 섹션)인가요?
  2. 표의 어느 이웃과 경쟁·보완인가요?
  3. 무엇을 좁혀 푸나요?
  4. 성숙도·채택은? (landscape.cncf.io 재확인)
  5. 우리 문제에 맞나요? (48의 3층)
→ 표는 낡습니다 — 항해술은 낡지 않습니다
```
