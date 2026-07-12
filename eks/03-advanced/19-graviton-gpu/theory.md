# 이론 — 아키텍처는 언어입니다, 장비는 자원입니다

> **🌱 17세 눈높이 비유: 번역본과 미술 작업실**
> - **CPU 아키텍처** = 언어: amd64는 영어, arm64는 한국어. 소스 코드(원고)는 같아도 **컨테이너 이미지(책)는 언어별 판본**이 따로 필요합니다 — 영어책을 한국어 독자(arm 노드)에게 주면 첫 줄부터 못 읽습니다(`exec format error`)
> - **multi-arch manifest** = 표지는 한 권인데, 사서가 독자의 언어를 보고 **맞는 판본을 꺼내주는** 도서관 시스템
> - **GPU** = 미술 전문 작업실: 수천 개의 붓(코어)이 같은 그림을 병렬로. 임대료가 비싸니 빈 작업실은 죄악입니다
> - **device plugin** = 작업실 관리인: "3층에 이젤 4개 있어요"라고 **예약 시스템(스케줄러)에 등록** — 등록이 없으면 예약 불가(있어도 없는 방)
> - **taint** = "미술 수업만 입장" 팻말 — 일반 수업이 비싼 작업실을 점거하지 못하게

---

## 1. Graviton 경제학 — 쌉니다, 단 번역이 끝났다면

- 단가: 동급 amd64 대비 대체로 20~40% 저렴 (세대·리전별 상이 — 가격표로 확인)
- 성능: 워크로드 의존 — **주장하지 말고 측정하세요**(13). Go/Java/Python/Node처럼 재컴파일·재배포가 쉬운 스택이 잘 맞고, SIMD(AVX) 최적화나 x86 전용 네이티브 바이너리에 기대는 워크로드는 검증 필수
- 전제: 이미지·사이드카·에이전트(모니터링, 메시 프록시…)까지 **전 계층이 arm64 판본을 가져야** 합니다 — 앱만 번역하고 사이드카를 빠뜨리는 게 단골 사고

## 2. multi-arch 이미지 — 도서관 사서의 구조

```
"nginx:1.27" (manifest list = 표지)
 ├─ linux/amd64 → 이미지 다이제스트 A
 └─ linux/arm64 → 이미지 다이제스트 B
노드의 containerd가 자기 arch에 맞는 쪽을 pull — 태그는 하나, 실물은 여럿
```

- 만들기: `docker buildx build --platform linux/amd64,linux/arm64 --push` (CI에서 — cicd 파트의 소재)
- 검사: `docker manifest inspect` / skopeo — **배포 전에 판본 존재를 확인**하는 습관이 exec format error의 백신
- 함정: `:latest`가 multi-arch여도 팀 내부 이미지가 단일 arch면, 혼합 클러스터에서 그 Pod만 노드 복불복이 됩니다

## 3. 마이그레이션 절차 (안전한 순서)

```
① 이미지 전수 조사: 우리 이미지 + 사이드카/에이전트의 arm64 판본 여부
② multi-arch 빌드 전환 (CI)
③ arm 노드 소수 투입 (별도 노드그룹, 또는 17 Karpenter requirements에 arm64 추가)
④ 카나리아: 일부 워크로드에 arch selector로 arm 지정 → 13의 방법으로 측정
   (같은 부하, amd vs arm — goodput/p99/오류율 + 시간당 비용)
⑤ 숫자가 좋으면 확대, selector 제거(혼합 허용) 또는 arm 우선
```

Karpenter와의 결합이 우아한 지점: requirements에 `arch: [amd64, arm64]`를 **둘 다 열면** 가격 계산이 알아서 Graviton을 선호합니다 — 단 ①②가 끝난 클러스터에서만 열 것.

## 4. GPU — 장비가 자원이 되는 메커니즘

```
GPU 인스턴스 (g6: NVIDIA 추론/그래픽, p5: 학습, inf2/trn1: AWS Neuron)
 + GPU AMI (NVIDIA 드라이버 내장 — AL2023_x86_64_NVIDIA)
 + nvidia device plugin (DaemonSet)
     └→ kubelet에 신고: "nvidia.com/gpu: 1"  ← extended resource 등록
 + taint (nvidia.com/gpu=present:NoSchedule 관례)

Pod 쪽:
  resources: { limits: { nvidia.com/gpu: 1 } }   # 정수만! 0.5장 불가(기본)
  tolerations: [gpu taint]
```

extended resource의 규칙: **정수 단위, 오버커밋 불가**(requests=limits) — CPU처럼 나눠 쓰는 자원이 아니라 통째로 점유하는 "장비"라서입니다. GPU 1장 Pod가 두 개면 두 번째는 Pending — 이 엄격함이 곧 다음 절의 존재 이유입니다.

## 5. GPU 공유 — 빈 붓을 놀리지 않는 법

| 방식 | 원리 | 격리 | 자리 |
|------|------|------|------|
| **time-slicing** | device plugin 설정으로 1장을 논리 N개로 신고 | **없음** (메모리 공유 — 한 Pod의 OOM이 이웃을 뭅니다) | 가벼운 추론 다수, 개발 환경 |
| **MIG** | A100/H100급의 하드웨어 분할 (최대 7조각) | 하드웨어 수준 | 프로덕션 멀티테넌트 추론 |
| 노드 공유 안 함 | 1 Pod = 1 GPU (기본) | 완전 | 학습, 지연 민감 추론 |

## 6. Neuron — AWS 자체 칩의 거래 조건

- inf2(추론)/trn1(학습): NVIDIA 대비 낮은 단가를 약속 — 대신 **Neuron SDK로 모델 컴파일**이 필요 (PyTorch/TF 연동은 있으나 "그냥 도는" 게 아님)
- k8s 통합은 GPU와 동형: neuron device plugin이 `aws.amazon.com/neuron`을 등록, taint/toleration 문법 동일
- 판단 틀: 모델이 컴파일 호환 + 물량이 커서 단가 차이가 이식 비용을 넘을 때 — 아니면 GPU가 무난

## 7. 운영 결합 — 앞 모듈들과의 접점

- **17 Karpenter**: 가속기별 NodePool(좁은 requirements + taint + limits) / 학습 Job엔 `do-not-disrupt`(consolidation이 4시간짜리 학습을 죽이지 않게)
- **15 KEDA**: GPU 추론의 큐 기반 scale-to-zero — "빈 작업실 임대료"의 해법
- **13 측정**: Graviton 전환·GPU time-slicing 결정 전부 — 측정 보고서가 근거

## 8. 소스/도구에서 확인하기

- nvidia device plugin: https://github.com/NVIDIA/k8s-device-plugin — time-slicing 설정 예제 포함
- device plugin 프레임워크(extended resource의 원리): kubernetes.io "Device Plugins"
- Neuron: https://awsdocs-neuron.readthedocs-hosted.com
- buildx multi-arch: https://docs.docker.com/build/building/multi-platform/

## 요약 카드

| 질문 | 답 |
|------|----|
| arch 불일치의 증상? | `exec format error` — CrashLoop, 첫 줄부터 못 읽는 번역본 |
| multi-arch의 구조? | manifest list(표지) → arch별 다이제스트 — containerd가 골라 pull |
| Graviton 전환 순서? | 이미지 전수조사 → multi-arch CI → 소수 투입 → **측정**(13) → 확대 |
| 장비가 자원이 되는 법? | device plugin이 kubelet에 extended resource로 신고 |
| GPU 자원의 규칙? | 정수 단위, 오버커밋 불가 — 공유는 time-slicing(무격리)/MIG(하드웨어) |
| GPU 비용의 제1계명? | idle은 죄악 — taint로 점유 방지 + 큐 기반 scale-to-zero(15) |
