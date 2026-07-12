# 이론 — containerd 아키텍처, CRI 흐름, 스냅샷터·콘텐츠, shim v2, 확장

> **🌱 17세 눈높이 비유: 대형 물류 창고**
> - **containerd** = 물류 창고 운영 시스템 — 물건(이미지)을 받아 보관하고, 주문(kubelet)이 오면 배송(컨테이너 실행)합니다
> - **CRI 플러그인** = 주문 접수 창구 — K8s의 주문서(gRPC)를 받아 창고 작업으로 번역
> - **콘텐츠 저장소** = 물건 창고 — 바코드(다이제스트)로 관리, 같은 물건은 하나만
> - **스냅샷터** = 포장 담당 — 여러 겹의 포장(레이어)을 겹쳐 최종 상자를 만듭니다(overlayfs)
> - **shim** = 배송 기사 — 물건을 실제로 배달하고, 배달 완료까지 곁을 지킵니다. **창고가 문을 닫아도(containerd 재시작) 배달은 계속됩니다**
> - **runwasi** = 새로운 배송 방식(Wasm) — 같은 창고 시스템에 다른 배송 트럭을 붙이기

---

## 1. 아키텍처 — 플러그인으로 조립된 데몬

```
클라이언트:
  kubelet ──(CRI gRPC)──▶ containerd  ← K8s
  crictl  ──(CRI gRPC)──▶            ← CRI 레벨 디버깅
  ctr     ──(native gRPC)─▶          ← containerd 네이티브 (저수준)
  nerdctl ──(native)─────▶            ← Docker 호환 UX

containerd 데몬 (플러그인 아키텍처):
  ├── CRI 플러그인 (io.containerd.grpc.v1.cri)   ← kubelet의 요청 처리
  ├── 이미지/콘텐츠 서비스 (콘텐츠 저장소, 이미지 메타)
  ├── 스냅샷 서비스 (스냅샷터: overlayfs, native, stargz...)
  ├── 런타임 서비스 (task) ──▶ shim v2 ──▶ runc/kata/runsc
  ├── 네임스페이스 (k8s.io, moby, default — 논리 격리)
  └── 이벤트, GC, 메트릭 ...

★ 거의 모든 것이 플러그인 → 확장·교체 가능 (guide의 확장성)
★ 네임스페이스: containerd의 논리적 격리 — K8s는 "k8s.io" 네임스페이스 사용
   (ctr로 볼 때 -n k8s.io를 안 주면 K8s 컨테이너가 안 보입니다 — 흔한 혼동)
```

## 2. CRI 흐름 — kubelet의 요청

```
Pod 생성 시 kubelet → containerd CRI:
  1. RunPodSandbox     ← Pod의 "sandbox"(pause 컨테이너 + 네트워크 네임스페이스) 생성
                          CNI 호출(04)로 IP 할당, 네트워크 네임스페이스 구성
  2. PullImage         ← 이미지 pull (콘텐츠 저장소 + 스냅샷터) — 없으면
  3. CreateContainer   ← 컨테이너 생성 (OCI 스펙 준비 — 03의 config.json)
  4. StartContainer    ← shim을 통해 실행
  (반복: 컨테이너 여러 개)

pause 컨테이너의 역할:
  Pod의 네트워크 네임스페이스를 "잡아두는" 최소 컨테이너
  → 앱 컨테이너가 재시작해도 Pod IP·네임스페이스 유지
  → "왜 노드에 pause 컨테이너가 Pod마다 있나"의 답
```

## 3. 이미지 — 콘텐츠 저장소와 스냅샷터

```
이미지 pull 시:
  1. 레지스트리에서 manifest 조회 (03의 OCI image-spec)
  2. 각 레이어 blob을 콘텐츠 저장소에 저장 (다이제스트 키 — 콘텐츠 주소)
     /var/lib/containerd/io.containerd.content.v1.content/blobs/sha256/<digest>
  3. 스냅샷터가 레이어를 순서대로 풀어 스냅샷 체인 구성
     overlayfs: lowerdir(하위 레이어들) + upperdir(쓰기 레이어) = merged

콘텐츠 주소의 이점 (cicd 04·19와 연결):
  같은 다이제스트 = 같은 내용 → 중복 저장 안 함 (레이어 공유)
  다이제스트로 무결성 검증 (변조 감지)

스냅샷터 종류:
  overlayfs (기본): 유니온 파일시스템
  native: 복사 (느림, 호환성)
  stargz/nydus: 지연 로딩 (이미지 전체 안 받고 필요한 부분만 — 큰 이미지 빠른 시작)
  ★ 디스크 사용의 대부분이 스냅샷터 — "디스크 참" 진단의 출발점
```

## 4. shim v2 — 컨테이너의 수호자

```
containerd ──(shim API)──▶ containerd-shim-runc-v2 (컨테이너/Pod당) ──▶ runc
                                    │
                                    ├ 컨테이너의 stdio 파이프 유지
                                    ├ 종료 코드 수집·보고
                                    └ containerd와 분리된 프로세스

왜 분리?
  runc는 만들고 종료(상주 안 함 — 03) → 누군가 컨테이너를 지켜야
  shim이 그 역할 + containerd와 독립
  → containerd 재시작/업그레이드에도 컨테이너 생존 (guide)

shim v2 API:
  런타임별 shim (runc, kata, runsc/gVisor, wasm) — RuntimeClass(03)가 고릅니다
  /etc/containerd/config.toml의 [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
  → 03 lab에서 본 그 설정
```

## 5. 확장 — 런타임 플랫폼

```
runwasi (Wasm):
  containerd-shim-wasm 계열 → Wasm 모듈을 컨테이너처럼 (03의 Wasm 노선)
  RuntimeClass: handler를 wasm shim으로 → Wasm 워크로드가 K8s에

대체 스냅샷터:
  stargz-snapshotter: 지연 로딩(큰 ML 이미지 빠른 콜드스타트 — 18과 연결)
  SOCI(AWS): seekable OCI — 유사 목적

nerdctl:
  Docker 호환 CLI (docker build/run/compose를 containerd로)
  Docker 데몬 없이 Docker UX (rootless도)

BuildKit(cicd 19):
  containerd를 백엔드로 쓸 수 있습니다 (이미지 빌드)
```

## 6. 진단 — ctr vs crictl vs kubectl

| 도구 | 레벨 | 용도 | 네임스페이스 주의 |
|---|---|---|---|
| kubectl | K8s API | 워크로드 | — |
| **crictl** | CRI | Pod·컨테이너·이미지 (kubelet과 같은 뷰) | 자동 k8s.io |
| **ctr** | containerd 네이티브 | 저수준(콘텐츠·스냅샷·task) | **-n k8s.io 필요!** |

```bash
crictl ps                    # 실행 중 컨테이너 (kubelet 뷰)
crictl images                # 이미지
crictl logs <id>             # 컨테이너 로그
ctr -n k8s.io containers list   # ★ 네임스페이스 없으면 안 보입니다
ctr -n k8s.io snapshots list    # 스냅샷 (디스크)
ctr -n k8s.io content list      # 콘텐츠 blob
```

## 7. 소스/도구에서 확인하기

- containerd: https://containerd.io/docs — architecture, plugins, snapshotters
- CRI: https://github.com/containerd/containerd/blob/main/docs/cri/
- shim: https://github.com/containerd/containerd/blob/main/runtime/v2/README.md
- runwasi: https://github.com/containerd/runwasi
- 03(런타임 지도)·20(노드 진단) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| 아키텍처? | 플러그인 데몬 — CRI/콘텐츠/스냅샷/런타임(shim) 서비스 조립 |
| CRI 흐름? | RunPodSandbox(pause+CNI) → PullImage → CreateContainer → StartContainer |
| pause 컨테이너? | Pod 네트워크 네임스페이스 유지 — 앱 재시작에도 IP 보존 |
| 이미지 저장? | 콘텐츠 저장소(다이제스트 blob) + 스냅샷터(overlayfs 레이어) |
| 디스크 진단? | 스냅샷터가 디스크의 대부분 — ctr -n k8s.io snapshots |
| shim v2? | 컨테이너 stdio·종료 수호 + containerd 독립 → 재시작에도 생존 |
| 확장? | runwasi(Wasm), stargz(지연로딩), nerdctl(Docker UX), RuntimeClass |
| 진단 도구? | crictl(CRI·자동 k8s.io) / ctr(네이티브·**-n k8s.io 필요**) |
