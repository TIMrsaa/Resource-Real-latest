# 흔한 함정 5선

## 1. `ctr`를 네임스페이스 없이 써서 "아무것도 없다"

`ctr containers list`를 실행하면 K8s 컨테이너가 하나도 안 보입니다 — containerd의 네임스페이스(논리적 격리) 개념 때문입니다. K8s는 `k8s.io` 네임스페이스를 쓰므로 `ctr -n k8s.io containers list`여야 보입니다(lab-01 Step 3). 이걸 모르면 "containerd에 컨테이너가 없는데 Pod는 도는 미스터리"에 빠집니다. 그리고 대부분의 CRI 레벨 디버깅은 `ctr`보다 `crictl`(자동으로 k8s.io, kubelet과 같은 뷰)이 편합니다 — `ctr`는 콘텐츠·스냅샷 같은 저수준 작업에만 씁니다. 도구를 레벨에 맞게 고르는 것이 노드 진단의 기본입니다.

## 2. 디스크 압박의 원인을 엉뚱한 곳에서 찾음

노드가 DiskPressure로 Pod를 evict하는데 애플리케이션 볼륨만 들여다봅니다 — 원인의 상당수는 containerd의 스냅샷터(overlayfs 레이어)와 콘텐츠 저장소(이미지 blob)입니다(theory §3). 큰 이미지를 자주 pull하거나, 미사용 이미지가 GC되지 않거나, 컨테이너 쓰기 레이어(upperdir)가 부풀면 여기가 찹니다. 진단: `du -sh /var/lib/containerd/io.containerd.snapshotter.*`와 `crictl images`. 대응: kubelet의 imageGC threshold 조정, `crictl rmi --prune`, 그리고 근본적으로 작은 이미지(멀티스테이지·distroless — cicd 04). "디스크 참"의 진단은 containerd 층부터입니다.

## 3. containerd 재시작을 워크로드 중단으로 오해

"containerd를 재시작하면 컨테이너가 다 죽는다"고 믿고 노드 유지보수를 과도하게 조심합니다 — 실제로는 shim v2 덕에 containerd 재시작에도 컨테이너가 생존합니다(lab-01 Step 7에서 실증). shim이 컨테이너의 stdio·종료를 지키는 별도 프로세스이기 때문입니다. 이 설계를 이해하면 containerd 업그레이드가 무중단임을 알 수 있습니다(단 CRI 재연결 동안 잠깐 kubelet이 상태를 못 볼 수 있습니다). 반대로 shim까지 죽이면(강제 kill) 컨테이너가 고아가 되므로, "containerd만 재시작"과 "shim까지 정리"는 다른 작업입니다.

## 4. 지연 로딩 스냅샷터를 검증 없이 도입

stargz·SOCI 같은 지연 로딩 스냅샷터는 큰 이미지의 콜드스타트를 극적으로 줄이지만(18의 콜드스타트 문제), 이미지가 그 형식으로 빌드·변환되어야 하고(추가 파이프라인), 런타임에 레지스트리와의 연결이 유지되어야 하며(필요한 부분을 그때그때 받으므로), 일부 워크로드에서는 오히려 첫 접근이 느려질 수 있습니다(lazy의 대가). "콜드스타트가 문제니까 stargz"로 검증 없이 도입하면 새로운 실패 모드(레지스트리 연결 끊김 시 앱이 멈춤)를 만납니다. 대상 워크로드의 접근 패턴을 실측하고, 이미지 변환 파이프라인을 갖춘 뒤 도입하세요.

## 5. RuntimeClass와 containerd 핸들러의 불일치

RuntimeClass의 `handler` 값은 containerd 설정(`config.toml`)의 런타임 핸들러 이름과 정확히 일치해야 합니다 — gVisor를 쓰려고 `runtimeClassName: gvisor`를 지정했는데 containerd에 `runsc` 핸들러가 설정되지 않았거나 이름이 다르면 Pod가 생성에 실패합니다(03의 격리 스펙트럼이 여기서 끊깁니다). 그리고 그 핸들러가 가리키는 바이너리(runsc, kata-runtime)가 노드에 실제 설치되어 있어야 합니다. RuntimeClass는 "요청"이고 containerd 설정 + 바이너리가 "구현"입니다 — 이 셋(RuntimeClass, config.toml 핸들러, 바이너리)이 정렬되어야 격리 런타임이 동작합니다. 관리형 K8s에서는 노드 이미지가 이것을 제공하는지 확인이 필요합니다.

## 실무 사고 사례

> 한 회사의 K8s 노드들이 간헐적으로 DiskPressure taint가 걸리며 Pod를 evict하기 시작했습니다 — 처음엔 애플리케이션의 로그·데이터 볼륨을 의심했지만 그쪽은 멀쩡했습니다. `df -h`로 보니 `/var/lib/containerd`가 노드 디스크의 70%를 먹고 있었습니다. 파고들어 보니 두 가지가 겹쳤습니다. ① CI 파이프라인이 커밋마다 이미지를 빌드해 노드에 pull했고(테스트 러너가 그 노드들이었습니다 — cicd 08), 태그가 매번 달라 이미지가 계속 쌓였습니다. ② 그 이미지들이 단일 스테이지 빌드라 각각 1.2GB였습니다(빌드 도구·의존성이 최종 이미지에 다 들어감 — cicd 04의 멀티스테이지를 안 씀). kubelet의 imageGC가 돌긴 했지만 pull 속도를 못 따라갔습니다. 그리고 결정적으로, 조사 과정에서 팀은 `ctr images list`를 실행해 "이미지가 별로 없다"고 오판했습니다 — 네임스페이스를 안 줘서(k8s.io) K8s 이미지가 안 보였던 것입니다. `crictl images`로 다시 보니 수백 개의 이미지가 쌓여 있었습니다. 해결은 세 겹이었습니다: ① 즉시 `crictl rmi --prune`과 imageGC threshold 하향으로 응급 처치. ② CI 이미지를 멀티스테이지로 전환해 1.2GB → 180MB(cicd 04). ③ 테스트 러너를 ephemeral로 바꿔 노드에 이미지가 누적되지 않게(cicd 08의 ARC). 그리고 노드 디스크 사용을 `/var/lib/containerd` 하위별로 모니터링에 추가했습니다. 회고 문장이 이 모듈의 요지였습니다: "우리는 몇 시간을 **애플리케이션 층**에서 헤맸는데, 문제는 **런타임 층**에 있었습니다 — 그리고 그 층을 볼 때는 올바른 도구(crictl, 올바른 네임스페이스)를 써야 보입니다. kubectl로 안 보이는 문제가 있고, 그 아래에 crictl과 ctr의 세계가 있습니다."
