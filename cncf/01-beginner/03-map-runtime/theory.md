# 이론 — 런타임 2층 구조, OCI 명세, 격리 스펙트럼, 전수 지도

> **🌱 17세 눈높이 비유: 음식 배달의 체인**
> - **kubelet** = 주문 접수 앱 — "이 Pod를 실행해줘"라는 주문을 넣습니다
> - **CRI 런타임(containerd/CRI-O)** = 프랜차이즈 본사 주방 시스템 — 주문을 받아 이미지(재료)를 준비하고 조리를 **지시**합니다. 직접 요리하지는 않습니다
> - **shim** = 조리 담당 매니저 — 요리사와 본사 사이의 연락책. 본사가 재시작돼도 요리는 계속되게
> - **OCI 런타임(runc)** = 요리사 — 실제로 불을 켜고(clone/namespace) 요리(프로세스)를 만듭니다. 만들고 나면 떠납니다
> - **OCI 명세** = 표준 레시피 형식 — 어느 본사든 어느 요리사든 같은 형식(config.json)으로 소통 — 그래서 요리사 교체(runc→gVisor)가 가능
> - **격리 스펙트럼** = 주방 분리 수준 — 같은 주방(runc, 커널 공유) < 별도 조리대(gVisor) < 아예 다른 건물(Kata의 마이크로VM)

---

## 1. 2층 구조 — 지도의 뼈대

```
kubelet
  │  CRI (gRPC — K8s가 정한 인터페이스)
  ▼
CRI 런타임: containerd 또는 CRI-O          ← 이미지 관리·컨테이너 수명주기·스토리지/네트워크 연결
  │  (containerd-shim-runc-v2 — 컨테이너마다)
  ▼
OCI 런타임: runc / crun / youki / runsc / kata   ← OCI 번들(config.json)을 받아 실제 프로세스 생성
  │
  ▼
리눅스 커널: namespaces, cgroups, seccomp...      ← k8s 초급에서 배운 그 실체
```

- **CRI 레벨이 "무엇을"** (이 이미지로 이 설정의 컨테이너를), **OCI 레벨이 "어떻게"** (커널 기능으로 실제 격리·생성)
- shim의 존재 이유: OCI 런타임은 프로세스를 만들고 **종료**합니다(상주 안 함) — 컨테이너의 stdio·종료 코드를 지키는 상주자가 shim이고, 덕분에 containerd를 재시작해도 컨테이너는 삽니다
- Docker의 위치: Docker 자체가 내부적으로 containerd→runc를 씁니다. K8s의 dockershim 제거(1.24)는 "Docker 지원 중단"이 아니라 **중간 번역층 제거** — 어차피 containerd가 일하고 있었습니다

## 2. OCI — 교체 가능성의 헌법

| 명세 | 내용 | 커리큘럼 접점 |
|---|---|---|
| runtime-spec | config.json — 컨테이너의 실행 정의(프로세스·마운트·namespace·cgroup) | lab-02에서 실물 |
| image-spec | 이미지 레이어·manifest·index 형식 | cicd 04·19의 다이제스트·manifest list가 이것 |
| distribution-spec | 레지스트리 API (push/pull) | cicd 19 "어떤 도구든 같은 것을 만든다"의 근거 |

OCI가 있어서 성립하는 것들: 빌드 도구의 경쟁(BuildKit/ko/buildpacks — cicd 19), OCI 런타임 교체(runc↔gVisor↔Kata — RuntimeClass), 레지스트리의 호환. **표준이 좁고 명확하면 그 위의 경쟁이 건강해집니다** — 02의 "확장 지점" 논리의 명세판.

## 3. 전수 지도 — 기준 시점 2026-06 (성숙도는 lab-01로 재확인)

### CRI 레벨

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **containerd** | Graduated | 사실상 기본값 — Docker에서 분리 기증. 범용(K8s 외 Docker·nerdctl도 사용). EKS·kind의 런타임 |
| **CRI-O** | Graduated | **K8s 전용** 미니멀리즘 — CRI만 구현, K8s 릴리스에 보조를 맞춤. OpenShift의 선택 |

선택 실질: 대부분 플랫폼이 정해줍니다(EKS=containerd, OpenShift=CRI-O). 직접 고른다면 — 범용성·생태계(containerd) vs K8s 밀착·표면적 최소(CRI-O).

### OCI 레벨 — 표준 격리 (커널 공유)

| 프로젝트 | 소속 | 한 줄 |
|---|---|---|
| **runc** | OCI(LF) | 기준 구현 — Go. namespaces·cgroups의 정석 |
| **crun** | 외부(Red Hat 주도) | C 구현 — 더 빠르고 가벼움(메모리 민감·고밀도에서). Podman 기본 |
| youki | Sandbox급* | Rust 구현 — 메모리 안전성 관점의 재작성 |

### OCI 레벨 — 강화 격리 (격리 스펙트럼의 오른쪽)

| 프로젝트 | 성숙도 | 격리 방식 | 대가 |
|---|---|---|---|
| **gVisor (runsc)** | (Google 오픈소스) | 유저스페이스 커널 Sentry가 시스템콜을 가로채 대신 처리 — 호스트 커널 노출 최소화 | 시스템콜 오버헤드, 일부 호환성 |
| **Kata Containers** | (OpenInfra 재단) | Pod마다 **마이크로VM**(경량 커널) — 하드웨어 가상화 경계 | 기동 시간·메모리, 중첩 가상화 요구 |
| Firecracker | (AWS 오픈소스) | microVM 모니터 — Lambda/Fargate의 기반. Kata의 백엔드로도 | VM 관리 층 필요 |

```
격리 스펙트럼:   runc ──────── gVisor ──────── Kata/Firecracker
                커널 공유      유저스페이스 커널   하드웨어 가상화
오버헤드:        최소           중간               큼
판정 질문: "신뢰할 수 없는 코드(멀티테넌트·사용자 제출 코드)를 실행하는가요?"
  Yes → 스펙트럼 오른쪽으로. RuntimeClass로 Pod 단위 혼용 (전부 바꿀 필요 없음!)
```

```yaml
# RuntimeClass — 같은 클러스터에서 Pod별 런타임 선택
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: gvisor }
handler: runsc          # containerd 설정의 핸들러 이름
# Pod: spec.runtimeClassName: gvisor  ← 신뢰 경계 밖 워크로드만
```

### 다음 세대 — Wasm

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **WasmEdge** | Sandbox급* | 서버사이드 Wasm 런타임 — ms 단위 콜드스타트, 샌드박스 기본 |
| wasmCloud / SpinKube 계열 | Sandbox~Incubating* | Wasm 워크로드의 오케스트레이션·플랫폼 층 |

Wasm이 겨냥하는 컨테이너의 한계: 이미지 크기(수백 MB vs 수 MB), 콜드스타트(초 vs ms), 샌드박스(기본 거부 vs 기본 허용). containerd의 runwasi shim으로 K8s에 얹는 경로가 표준화 중 — "컨테이너를 대체"가 아니라 **함수형·엣지·플러그인 워크로드**의 자리부터.

## 4. 계보와 사건들 — 지도의 역사 층위

```
2013 Docker 등장 → 2015 OCI 설립 + runc 기증 (표준화 — 사유화 우려의 해소, 01의 논리)
2017 containerd를 CNCF에 기증 / CRI-O 등장 (K8s 전용 노선)
2020 dockershim 제거 발표 — "Docker로 빌드한 이미지 계속 됩니다" 해프닝 (OCI 덕분에 당연)
2019~ microVM 부상 (Firecracker→Lambda, Kata 성숙) / 2021~ Wasm 노선 개척
rkt (CoreOS): CNCF 최초 아카이브 사례 중 하나 — 01의 "정직한 신호"의 원조
```

## 5. 소스/도구에서 확인하기

- OCI 명세: https://github.com/opencontainers/runtime-spec (config.json 정의 — lab-02의 실물)
- containerd 아키텍처: https://containerd.io/docs/ — shim v2 문서
- gVisor: https://gvisor.dev/docs/architecture_guide/ / Kata: https://katacontainers.io
- runwasi (Wasm shim): https://github.com/containerd/runwasi
- RuntimeClass: https://kubernetes.io/docs/concepts/containers/runtime-class/

## 요약 카드

| 질문 | 답 |
|------|----|
| 지도의 뼈대? | 2층 — CRI 레벨(containerd/CRI-O)과 OCI 레벨(runc/crun/...) — 층이 다르면 경쟁자가 아닙니다 |
| shim의 존재 이유? | OCI 런타임은 만들고 떠납니다 — stdio·종료를 지키는 상주자, containerd 재시작에도 컨테이너 생존 |
| dockershim 제거의 진실? | 번역층 제거 — 이미지는 OCI 표준이라 아무 영향 없음 |
| 격리 스펙트럼? | runc(커널 공유) → gVisor(유저스페이스 커널) → Kata(마이크로VM) — 판정 질문은 "신뢰 못 할 코드인가" |
| RuntimeClass? | Pod 단위 런타임 혼용 — 전부 바꾸지 않고 위험한 것만 오른쪽으로 |
| Wasm의 자리? | 콜드스타트·크기·샌드박스가 본질인 워크로드부터 — runwasi로 K8s에 합류 중 |
