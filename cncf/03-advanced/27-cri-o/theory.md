# 이론 — CRI-O 아키텍처, 버저닝, containers 생태계, crun, 선택

> **🌱 17세 눈높이 비유: 종합 마트 vs 전문점**
> - **containerd(26)** = 대형 종합 마트 — 식료품(K8s)도 팔고 공구(Docker)도 팔고 뭐든 팝니다
> - **CRI-O** = K8s 전용 전문점 — 쿠버네티스가 주문하는 것만 취급. 대신 그것만큼은 딱 맞게
> - **K8s 정렬 버저닝** = 전문점이 본사(K8s)와 같은 날 신제품을 냅니다 — "이 버전이 맞나" 고민 불필요
> - **containers/ 라이브러리** = 여러 전문점(CRI-O·Podman)이 공유하는 물류 시스템 — 각자 창고를 안 짓고 공용을 씁니다
> - **crun** = 빠른 배송 기사(C로 작성) — Go 기사(runc)보다 가볍고 빠릅니다
> - **철학** = "안 파는 것도 전략" — K8s 밖 기능을 포기해 단순함을 얻습니다 (25의 반복)

---

## 1. 아키텍처 — CRI 구현 + 라이브러리 조합

```
kubelet ──(CRI gRPC)──▶ CRI-O
                          ├── CRI 구현 (RunPodSandbox, CreateContainer... — 26과 같은 CRI)
                          ├── containers/storage    ← 이미지·컨테이너 저장 (공유 라이브러리)
                          ├── containers/image      ← pull·서명 검증 (21)
                          ├── conmon                ← 컨테이너 모니터 (26의 shim 역할)
                          └── OCI 런타임: crun(기본) / runc / kata / runsc
                                  │
                                  ▼ 실제 컨테이너

containerd(26)와의 구조 차이:
  containerd: 자체 콘텐츠 저장소·스냅샷터·shim v2 (플러그인으로 다 자체 구현)
  CRI-O:      containers/ 공유 라이브러리 조립 + conmon(shim 역할)
  → "덜 만들고 더 조립한다"
```

**conmon** (container monitor): CRI-O의 shim 대응물 — 컨테이너당 하나, stdio·종료 코드를 지키고 CRI-O 재시작에도 컨테이너 생존(26의 shim v2와 같은 역할, 다른 구현).

## 2. K8s 정렬 버저닝 — 가장 독특한 결정

```
CRI-O 1.30 ↔ Kubernetes 1.30 (함께 릴리스, 함께 지원)
CRI-O 1.31 ↔ Kubernetes 1.31
...

이점:
  - K8s 버전에 정확히 맞는 CRI 구현 (명세 변화 즉시 반영)
  - "어느 런타임 버전이 우리 K8s와 맞나"라는 질문 소멸
  - K8s 업그레이드 시 런타임도 자연히 맞춰짐

제약:
  - CRI-O를 K8s와 독립적으로 업그레이드 불가
  - K8s 밖에서 쓸 이유 없음 (애초에 목표가 K8s 전용)

containerd(26)와 대비:
  containerd: 독립 버저닝 → 유연하지만 호환성 매트릭스 확인 필요
  CRI-O:      K8s 묶음 → 확인 불필요하지만 유연성 없음
```

## 3. containers/ 생태계 — 공유 라이브러리

| 라이브러리 | 역할 | 공유하는 도구 |
|---|---|---|
| **containers/storage** | 이미지 레이어·컨테이너 저장(overlay 등) | CRI-O, Podman, Buildah |
| **containers/image** | 이미지 pull·push·**서명 검증(21)** | CRI-O, Podman, Skopeo |
| **containers/common** | 공통 설정·정책 | 전부 |
| conmon | 컨테이너 모니터 | CRI-O, Podman |

```
형제 도구들 (Red Hat containers/ 생태계):
  Podman:  데몬리스 컨테이너 실행 (Docker 대체, rootless)
  Buildah: 이미지 빌드 (cicd 19의 빌드 도구 — Dockerfile 없이도)
  Skopeo:  이미지 검사·복사 (레지스트리 간)
  → CRI-O와 같은 저장소(containers/storage)를 공유할 수 있습니다
  → "K8s는 CRI-O가, CLI는 Podman이, 빌드는 Buildah가" 한 생태계
```

이것이 26의 containerd(Docker 계보, nerdctl)와 다른 생태계입니다 — Red Hat 계보의 데몬리스 철학.

## 4. crun — 기본 OCI 런타임

```
CRI-O의 기본 OCI 런타임은 crun (03의 그것):
  runc: Go 작성, 기준 구현
  crun: C 작성, 더 빠르고 가볍습니다 (메모리·시작 시간)
       → 고밀도·저사양 환경에서 유리 (03의 격리 스펙트럼 왼쪽 끝의 최적화)

CRI-O도 RuntimeClass로 다른 런타임 지원:
  crun(기본) / runc / kata / runsc(gVisor) / kata-remote 등
  → 03의 격리 스펙트럼은 런타임과 무관하게 적용
```

## 5. 이미지 서명 검증 — 21과의 접점

```
containers/image가 서명 검증을 지원 (21의 공급망):
  policy.json으로 "어느 레지스트리의 이미지를 신뢰하나" 정책
  sigstore(cosign) 서명 검증을 런타임 레벨에서

  {
    "default": [{"type": "reject"}],
    "transports": {
      "docker": {
        "registry.example.com": [{"type": "sigstoreSigned", "keyPath": "..."}]
      }
    }
  }

→ 21에서 admission(Kyverno)으로 검증한 것을 런타임 레벨에서도 (다층 방어)
  OpenShift는 이 이미지 정책을 기본 통합
```

## 6. 선택 — containerd vs CRI-O

```
현실: 대부분 플랫폼이 정합니다
  EKS/GKE/AKS/kind → containerd
  OpenShift        → CRI-O

직접 고른다면 축:
  범용성 필요(Docker 호환, 다양한 워크로드, 넓은 생태계) → containerd
  K8s 전용 + 표면적 최소 + K8s 정렬 버저닝 + Red Hat 생태계 → CRI-O
  성능: 둘 다 우수, 특정 워크로드에서 미세 차이 (실측 필요)

★ "어느 게 낫나"가 아니라 "우리 플랫폼이 무엇이고 그 특성이 무엇인가"
  25의 교훈 반복: 범위를 좁히는 것도 설계, 안 쓸 기능은 부채
```

## 7. 소스/도구에서 확인하기

- CRI-O: https://cri-o.io — architecture, versioning
- containers/ 생태계: https://github.com/containers (storage, image, podman, buildah, skopeo)
- crun: https://github.com/containers/crun
- 이미지 서명 정책: containers-policy.json(5)
- 26(containerd)·03(런타임 지도)·21(서명) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| CRI-O의 철학? | K8s 전용 미니멀리즘 — CRI만 구현, 그 이상 안 함 |
| 구조? | CRI 구현 + containers/ 공유 라이브러리 + conmon (조립) |
| 버저닝? | K8s 버전과 정렬(1.30↔1.30) — 호환성 고민 소멸, 유연성 포기 |
| conmon? | CRI-O의 컨테이너 모니터 — 26의 shim v2와 같은 역할 |
| containers/ 생태계? | storage·image 공유 — Podman·Buildah·Skopeo 형제 (Red Hat 계보) |
| 기본 런타임? | crun (C, runc보다 경량·고속) |
| 21과의 접점? | containers/image의 서명 검증 정책 (런타임 레벨 다층 방어) |
| 선택? | 대개 플랫폼이 정함 (EKS=containerd, OpenShift=CRI-O) |
