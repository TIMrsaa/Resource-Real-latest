# 학습 가이드 — 런타임 층에서 반복되는 두 철학

## 26과 짝, 그리고 24·25의 반복

25에서 메시의 두 철학(Istio의 기능 최대 vs Linkerd의 운영 최소)을 봤습니다. 런타임 층에서 같은 대비가 있습니다:

```
             containerd (26)                CRI-O (27)
범위         범용 (K8s·Docker·nerdctl·확장)  K8s 전용 (CRI만)
철학         "무엇이든 컨테이너를"            "쿠버네티스가 필요한 것만"
버저닝       독립                            K8s 버전과 정렬 (1.30 ↔ CRI-O 1.30)
구조         플러그인 데몬                    CRI 구현 + containers 라이브러리 조합
생태계       CNCF·Docker 계보                Red Hat·containers/ 계보(Podman과 형제)
자리         대부분의 관리형 K8s              OpenShift
```

이 대비를 배우는 이유는 CRI-O 자체보다 **"범위를 좁히는 것도 설계 결정"**이라는 반복되는 교훈입니다. CRI-O는 "K8s 밖에서 쓸 일이 없으니 K8s만 잘하겠다"를 선택했고, 그 대가로 범용성을 포기했습니다 — 25의 Linkerd가 메시에서 한 것과 같습니다.

## "K8s와 함께 간다"의 의미

CRI-O의 가장 독특한 결정은 버저닝입니다: CRI-O 1.30은 Kubernetes 1.30과 함께 릴리스되고 함께 지원됩니다. 이것이 주는 것:

```
이점: K8s 버전에 정확히 맞는 런타임 (CRI 명세 변화를 즉시 따라감)
      "어느 CRI-O 버전이 우리 K8s와 맞나"를 고민할 필요 없음
제약: CRI-O만 독립적으로 업그레이드할 수 없음 (K8s와 묶임)
      K8s 밖에서 쓸 이유가 없음(애초에 그것이 목표)
```

containerd는 독립 버저닝이라 유연하지만 "이 containerd가 이 K8s와 호환되나"를 확인해야 합니다. CRI-O는 그 질문 자체를 없앴습니다 — 대신 K8s에 묶였습니다.

## containers/ 생태계

CRI-O는 혼자가 아닙니다. Red Hat 주도의 `containers/` 조직에는 공유 라이브러리가 있습니다:

```
containers/storage    이미지·컨테이너 저장 (CRI-O와 Podman이 공유)
containers/image      이미지 pull·검증 (서명 검증 — 21과 연결)
containers/common     공통 설정
→ CRI-O = 이 라이브러리들 + CRI 구현
→ Podman(데몬리스 컨테이너 도구)이 형제 — 같은 저장소를 공유할 수 있습니다
```

이것이 26의 containerd(자체 콘텐츠 저장소·스냅샷터)와 다른 점입니다: CRI-O는 검증된 공유 라이브러리를 조립합니다. "덜 만들고 더 조립한다"의 철학.

## 선택은 대개 플랫폼이 정합니다

현실적으로 containerd vs CRI-O를 직접 고르는 경우는 드뭅니다 — EKS·GKE·kind는 containerd, OpenShift는 CRI-O로 정해져 있습니다. 그래서 이 모듈의 실무 가치는 "어느 것을 고를까"보다 "**우리 플랫폼의 런타임이 무엇이고, 그 특성이 무엇인가**"를 아는 것입니다. OpenShift를 운영한다면 CRI-O의 K8s 정렬 버저닝과 containers/ 생태계를 알아야 하고, EKS를 운영한다면 26의 containerd를 알아야 합니다.
