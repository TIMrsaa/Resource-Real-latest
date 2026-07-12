# 자가 점검 퀴즈

**Q1.** containerd의 플러그인 아키텍처를 구성하는 주요 서비스는? containerd의 "네임스페이스"란 무엇이고 왜 주의해야 하나요?

**Q2.** kubelet이 Pod를 만들 때 CRI 호출 순서는? pause 컨테이너의 역할은?

**Q3.** 이미지 레이어가 저장되는 두 곳(콘텐츠 저장소·스냅샷터)의 역할 차이는? 디스크 사용의 대부분은 어디인가요?

**Q4.** shim v2가 존재하는 이유와, "containerd 재시작에도 컨테이너가 생존"하는 메커니즘은?

**Q5.** crictl과 ctr의 차이는? 각각 언제 쓰나요?

**Q6.** RuntimeClass가 gVisor/Kata를 고르려면 무엇 셋이 정렬되어야 하나요?

**Q7.** containerd가 "확장 플랫폼"인 근거 네 가지는?

**Q8.** 노드 DiskPressure 진단을 containerd 층부터 하는 절차는? (사고 사례 기반)

---

## 정답

**A1.** CRI 플러그인(kubelet 요청 처리), 콘텐츠/이미지 서비스(blob 저장·메타), 스냅샷 서비스(스냅샷터), 런타임 서비스(task → shim), 그리고 이벤트·GC·메트릭 — 거의 모든 것이 플러그인이라 확장·교체 가능합니다. containerd의 네임스페이스는 논리적 격리 단위로, K8s는 `k8s.io` 네임스페이스를 사용합니다 — `ctr`로 조회할 때 `-n k8s.io`를 주지 않으면 default 네임스페이스를 보게 되어 K8s 컨테이너가 안 보입니다(흔한 혼동).

**A2.** ① RunPodSandbox(pause 컨테이너 + 네트워크 네임스페이스 생성, CNI 호출로 IP 할당) → ② PullImage(콘텐츠 저장소·스냅샷터, 이미지가 없으면) → ③ CreateContainer(OCI 스펙 준비) → ④ StartContainer(shim을 통해 실행). pause 컨테이너의 역할: Pod의 네트워크 네임스페이스를 "잡아두는" 최소 컨테이너 — 앱 컨테이너가 죽고 재시작해도 Pod IP·네임스페이스가 유지됩니다(노드에 Pod마다 pause가 있는 이유).

**A3.** 콘텐츠 저장소: 이미지 레이어 blob을 다이제스트(콘텐츠 주소)로 저장 — 같은 내용은 한 번만(레이어 공유), 무결성 검증. 스냅샷터: 그 레이어들을 순서대로 풀어 overlayfs로 쌓아 컨테이너가 보는 파일시스템(lowerdir + upperdir = merged)을 구성. 디스크 사용의 대부분은 **스냅샷터**(overlayfs 레이어 + 컨테이너 쓰기 레이어)이며, "노드 디스크 참" 진단의 출발점입니다.

**A4.** runc는 컨테이너를 만들고 종료합니다(상주하지 않음 — 03) — 컨테이너의 stdio·종료 코드를 지킬 상주자가 필요하고 그것이 shim입니다. shim v2는 컨테이너/Pod당 하나의 별도 프로세스로 containerd와 독립되어 있으므로, containerd를 재시작·업그레이드해도 shim과 그것이 지키는 컨테이너는 생존합니다(lab-01 Step 7에서 실증). 이것이 containerd 업그레이드가 무중단인 이유입니다.

**A5.** crictl: CRI 레벨 도구로 kubelet과 같은 뷰(자동으로 k8s.io 네임스페이스), Pod·컨테이너·이미지·로그를 다룹니다 — 대부분의 노드 디버깅에 편합니다. ctr: containerd 네이티브 도구로 저수준 작업(콘텐츠 blob, 스냅샷, task)을 다루며 `-n k8s.io`를 명시해야 K8s 리소스가 보입니다. 즉 CRI 레벨 워크로드 진단은 crictl, containerd 내부(콘텐츠·스냅샷) 조사는 ctr.

**A6.** ① RuntimeClass 오브젝트의 `handler` 값, ② containerd config.toml의 런타임 핸들러 정의(`[plugins."...".containerd.runtimes.<handler>]`), ③ 그 핸들러가 가리키는 런타임 바이너리(runsc, kata-runtime)의 노드 설치 — 이 셋의 이름과 존재가 정렬되어야 격리 런타임이 동작합니다. RuntimeClass는 "요청", config.toml 핸들러 + 바이너리가 "구현"이며, 관리형 K8s에서는 노드 이미지가 이를 제공하는지 확인이 필요합니다.

**A7.** ① runwasi: containerd-shim-wasm으로 Wasm 워크로드를 컨테이너처럼 K8s에서 실행(03의 Wasm 노선). ② 대체 스냅샷터: stargz/SOCI/nydus로 지연 로딩(큰 이미지 콜드스타트 단축 — 18). ③ nerdctl: Docker 호환 CLI를 Docker 데몬 없이(rootless 포함). ④ BuildKit 백엔드: cicd 19의 BuildKit이 containerd를 이미지 빌드 백엔드로 사용 가능. 이 확장성이 03에서 "containerd = 범용"이라 한 근거입니다.

**A8.** ① `/var/lib/containerd`의 디스크 사용 확인(콘텐츠 저장소 + 스냅샷터, `du -sh io.containerd.snapshotter.*`·`io.containerd.content.*`). ② `crictl images`로 쌓인 이미지 확인(주의: `ctr`는 `-n k8s.io` 없이는 K8s 이미지가 안 보임 — 사고 사례의 오판). ③ 원인 분류: 큰 이미지(멀티스테이지 미사용 — cicd 04)인가, 미사용 이미지 누적(imageGC가 pull 속도를 못 따라감)인가, 컨테이너 쓰기 레이어 부풀림인가. ④ 응급: `crictl rmi --prune` + imageGC threshold 하향. ⑤ 근본: 작은 이미지(멀티스테이지·distroless), 러너면 ephemeral화(cicd 08). 애플리케이션 층이 아니라 런타임 층부터, 올바른 도구(crictl·올바른 네임스페이스)로 봐야 합니다.
