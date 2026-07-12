# 학습 가이드 — "체인의 한 고리"를 열어보기

## 03에서 본 것, 여기서 여는 것

03의 lab에서 kind 노드에 들어가 이런 트리를 봤습니다:

```
kubelet ──CRI──▶ containerd ──▶ containerd-shim-runc-v2 ──▶ [runc] ──▶ 프로세스
```

그때는 "containerd가 CRI 런타임"이라는 사실만 확인했습니다. 이 모듈은 그 containerd 상자를 엽니다:

```
containerd 안에는:
  CRI 플러그인      kubelet의 gRPC 요청을 처리 (Pod·컨테이너 수명주기)
  이미지 서비스     pull·저장 (콘텐츠 저장소 + 스냅샷터)
  런타임 서비스     shim을 통해 컨테이너 실행
  스냅샷터          레이어를 파일시스템으로 (overlayfs)
  콘텐츠 저장소     이미지 blob (콘텐츠 주소 — 다이제스트)
  → 전부 플러그인으로 조립된 데몬
```

## 왜 containerd를 깊게 아나

대부분의 개발자는 containerd를 만질 일이 없습니다 — kubelet이 알아서 씁니다. 그런데 노드 수준 장애의 상당수가 여기서 옵니다:

```
"이미지 pull이 느리다/실패한다"     → 콘텐츠 저장소, 레지스트리 인증, 스냅샷터
"디스크가 찬다"                     → 스냅샷터의 레이어, 미사용 이미지 GC
"컨테이너가 이상하게 안 뜬다"        → CRI 흐름의 어느 단계, shim 로그
"containerd 재시작 후 상태"          → shim v2의 역할
```

kubectl로는 안 보이는 이 층의 진단은 `crictl`(CRI 레벨)과 `ctr`(containerd 네이티브)로 합니다 — 20에서 예고한 노드 진단 도구 체인의 완성입니다.

## shim v2 — 우아한 설계

containerd의 가장 영리한 부분이 shim입니다. runc는 컨테이너를 만들고 종료합니다(상주하지 않습니다 — 03에서 확인). 그럼 컨테이너의 stdio·종료 코드는 누가 지키나요? shim입니다. 그리고 shim이 별도 프로세스이므로:

```
containerd를 재시작해도 → shim은 살아 있고 → 컨테이너도 살아 있습니다
containerd 업그레이드가 워크로드를 안 죽이는 이유가 이것
```

이 설계를 이해하면 "containerd를 재시작했는데 Pod가 왜 안 죽지?"의 답이 나옵니다. lab-01에서 직접 확인합니다.

## 확장 플랫폼으로서의 containerd

containerd가 단순한 런타임을 넘어선 이유는 확장성입니다:

```
runwasi:        Wasm 워크로드를 containerd로 (03의 Wasm 노선이 K8s에 합류하는 경로)
대체 스냅샷터:  stargz(지연 로딩), 이미지 볼륨 등
nerdctl:        Docker 호환 CLI (Docker 없이 Docker처럼)
runtime handler: RuntimeClass(03)가 gVisor·Kata를 고르는 지점
```

이것이 03에서 "containerd = 범용, CRI-O = K8s 전용"이라 한 것의 근거입니다 — containerd는 K8s 밖에서도, 다양한 워크로드 타입으로도 확장됩니다.
