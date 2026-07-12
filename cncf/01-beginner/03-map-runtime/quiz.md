# 자가 점검 퀴즈

**Q1.** 런타임 2층 구조에서 각 층의 책임과, "containerd vs runc"가 성립하지 않는 질문인 이유는?

**Q2.** shim의 존재 이유 두 가지와, ps에서 runc가 안 보이는 이유는?

**Q3.** OCI 3대 명세와 각각이 가능하게 하는 "교체·경쟁"을 커리큘럼의 다른 모듈과 연결해 설명하세요.

**Q4.** dockershim 제거의 실제 의미와, 당시의 오해가 틀린 구조적 이유는?

**Q5.** 격리 스펙트럼 세 지점의 격리 방식·대가와, 배치를 결정하는 판정 질문은?

**Q6.** RuntimeClass가 연결하는 것들(API → 설정 → 바이너리)을 lab-02에서 본 실물로 설명하세요.

**Q7.** containerd와 CRI-O의 설계 철학 차이와, 실무에서 선택이 대개 어떻게 정해지나요?

**Q8.** Wasm 런타임이 겨냥하는 컨테이너의 세 한계와, "대체 서사"가 왜 오독인가요?

---

## 정답

**A1.** CRI 레벨(containerd/CRI-O): kubelet과 gRPC(CRI)로 대화 — 이미지 pull·컨테이너 수명주기·스토리지/네트워크 연결 등 "무엇을"의 관리. OCI 레벨(runc/crun 등): OCI 번들(config.json)을 받아 커널 기능(namespace·cgroup)으로 실제 프로세스를 생성 — "어떻게"의 실행. containerd가 runc를 호출하는 상하 관계이므로 비교 대상이 아닙니다 — 경쟁은 같은 층 안에서만(containerd↔CRI-O, runc↔crun↔gVisor).

**A2.** ① OCI 런타임은 프로세스를 만들고 종료합니다(상주 안 함) — 컨테이너의 stdio 파이프와 종료 코드를 지킬 상주자가 필요하고 그것이 shim(컨테이너당 하나). ② shim이 containerd와 컨테이너 사이를 분리해 — containerd를 재시작·업그레이드해도 실행 중 컨테이너가 죽지 않습니다. runc가 ps에 없는 이유: 생성 작업만 하고 이미 종료했기 때문 — 트리에는 shim과 그 자식(컨테이너 프로세스)만 남습니다(lab-02 Step 2).

**A3.** runtime-spec(config.json — 실행 정의): OCI 런타임의 교체 가능(runc↔runsc↔kata — RuntimeClass). image-spec(레이어·manifest·index): 빌드 도구의 경쟁(BuildKit/ko/buildpacks — cicd 19 "어떤 도구든 같은 것을 만든다")과 다이제스트·manifest list(cicd 04·19). distribution-spec(레지스트리 API): 레지스트리 호환(ECR/ghcr/Harbor 어디든 같은 push/pull). 좁고 명확한 표준이 그 위의 건강한 경쟁을 만듭니다 — 02의 확장 지점 논리의 명세판.

**A4.** kubelet이 Docker 데몬과 대화하기 위한 번역층(dockershim)을 제거하고 CRI 런타임(containerd 등)과 직접 대화하게 한 것 — 어차피 Docker 내부도 containerd→runc였으므로 중간층 제거일 뿐. "Docker로 빌드한 이미지가 안 돈다"가 틀린 이유: 이미지 형식은 OCI image-spec이고 런타임 인터페이스(CRI)와 독립 — 무엇으로 빌드했든 OCI 이미지는 어느 CRI 런타임에서나 돕니다.

**A5.** runc: 커널 공유 — 오버헤드 최소, 커널 취약점이 곧 이웃 노출. gVisor(runsc): 유저스페이스 커널(Sentry)이 시스템콜을 가로채 대신 처리 — 호스트 커널 표면 축소, 대가는 시스템콜 오버헤드·일부 호환성. Kata/Firecracker: Pod/워크로드마다 마이크로VM — 하드웨어 가상화 경계, 대가는 기동·메모리·중첩 가상화 요구. 판정 질문: "이 워크로드의 코드를 신뢰하는가요?" — No인 것만 RuntimeClass로 오른쪽에 배치(전면 전환 아님).

**A6.** Pod의 `runtimeClassName: gvisor` → RuntimeClass 오브젝트의 `handler: runsc` → containerd의 config.toml `[plugins...runtimes.runsc]` 항목 → 그 항목이 가리키는 OCI 런타임 바이너리(runsc). lab-02 Step 3에서 config.toml의 runtimes.runc 블록을 확인했습니다 — 격리 교체가 "설정 한 블록 + 노드에 바이너리"임을 실물로 본 것.

**A7.** containerd: 범용 — K8s 외에도 Docker·nerdctl 등이 쓰는 일반 컨테이너 데몬, 생태계·플러그인 폭이 넓습니다. CRI-O: K8s 전용 미니멀리즘 — CRI만 구현하고 K8s 릴리스 주기에 밀착, 표면적 최소화 철학(OpenShift의 선택). 실무 선택은 대개 플랫폼이 정합니다 — EKS·kind·대부분 매니지드는 containerd, OpenShift는 CRI-O — 직접 고르는 경우가 드물고, 고른다면 범용성 vs K8s 밀착의 축입니다.

**A8.** 세 한계: ① 콜드스타트(초 단위 vs Wasm ms 단위) ② 배포물 크기(수백 MB 이미지 vs 수 MB 모듈) ③ 샌드박스 기본값(컨테이너는 기본 허용+제한 추가, Wasm은 기본 거부+명시 허용). 대체 서사가 오독인 이유: 실행 모델 자체가 다릅니다 — 리눅스 프로세스가 아니라 WASI로 제한된 샌드박스라 기존 앱은 재컴파일·재설계 없이 못 옮기고 옮길 이유도 없습니다. 올바른 독법은 자리 서사 — 함수·엣지·플러그인처럼 세 한계가 본질인 워크로드부터, runwasi shim으로 K8s 안에 공존.
