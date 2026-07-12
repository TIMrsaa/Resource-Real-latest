# 학습 가이드 — 노드는 블랙박스가 아닙니다

## 이 모듈이 메우는 구멍

지금까지의 그림에서 kubelet은 "노드의 관리소장"이라는 비유로만 존재했습니다. 실제 장애의 절반은 노드에서 납니다:

- ContainerCreating에서 멈춤 (CNI? 볼륨? 이미지?)
- 노드가 NotReady (kubelet? 런타임? 디스크?)
- Pod가 영문 모를 Evicted (누가? 왜?)

이 모듈 후에는 노드에 들어가 `crictl`과 kubelet 로그로 **API 서버가 말해주지 않는 진실**을 직접 캐낼 수 있습니다.

## 미리 잡는 구도: kubelet은 "노드 위의 미니 컨트롤 플레인"

```
kubelet의 입력:  ① API 서버 watch (내 노드의 Pod들)
                ② static Pod 디렉터리 (파일!)
                ③ probe 결과, cgroup 상태, 디스크 압박...
kubelet의 출력: CRI 호출 (containerd) + status 보고 + 이벤트 + eviction
```

kubelet도 결국 조정 루프입니다 — "내 노드에 떠 있어야 할 것"과 "실제 떠 있는 것"의 차이를 CRI 호출로 메꿉니다. 모듈 02의 패턴이 노드 안에서 반복됩니다.

## crictl 예고

`docker ps`의 CRI판입니다. **kubelet이 쓰는 것과 동일한 gRPC 소켓**으로 containerd에 말을 걸기 때문에, kubelet이 보는 세상을 그대로 봅니다 — 노드 디버깅의 1급 도구. (단, crictl로 만든 컨테이너는 kubelet이 모르는 "유령"이 되므로 조회 위주로 쓰는 것이 원칙)
