# 이론 — 리포 구조, 빌드 시스템, 검증 사다리

> **🌱 17세 눈높이 비유: 자동차 정비학원의 첫날**
> 지금까지는 운전(사용)과 정비 매뉴얼(이론)을 배웠습니다. 오늘은 **엔진을 내려서 분해 조립**해봅니다.
> 무서워 보여도 순서는 정해져 있습니다: 공장 설계도 받기(clone) → 공구 준비(Go/make) → 부품 하나 가공(kubectl 빌드) → 내가 조립한 엔진으로 시동(kind) — 시동이 걸리는 순간, 자동차는 더 이상 블랙박스가 아닙니다.

---

## 1. kubernetes/kubernetes — 무엇이 들어 있나

```
kubernetes/
├── cmd/                  각 컴포넌트의 main() — 진입점
│   ├── kube-apiserver/  kube-scheduler/  kube-controller-manager/
│   ├── kubelet/  kube-proxy/  kubectl/
├── pkg/                  구현 본체 (스케줄러 플러그인, kubelet 내부 등)
├── staging/src/k8s.io/   ★ 별도 배포되는 라이브러리들의 원본
│   ├── client-go/  api/  apimachinery/  kubectl/ ...
├── test/                 e2e 테스트 (모듈 44)
├── hack/                 개발 스크립트 모음 (코드 생성, 검증, 로컬 클러스터)
├── build/                컨테이너화된 빌드 (make quick-release-images 등)
└── api/                  OpenAPI 스펙
```

### staging의 비밀 (모듈 31의 의문 해소)

`go get k8s.io/client-go`로 받던 그 라이브러리의 **원본이 이 리포의 staging/ 안에** 있습니다 — 별도 리포(kubernetes/client-go)는 여기서 자동 동기화되는 **읽기 전용 미러**입니다. 즉 client-go에 기여하고 싶어도 PR은 kubernetes/kubernetes에 보냅니다. (모노리포 + 미러 발행 구조)

## 2. 빌드 시스템 — make의 주요 표적

| 명령 | 하는 일 | 시간(참고) |
|------|---------|-----------|
| `make all` | 전 컴포넌트 빌드 | 수십 분 (첫 회) |
| `make WHAT=cmd/kubectl` | **kubectl만** | 수 분 ★ 주력 |
| `make WHAT=cmd/kube-scheduler` | 스케줄러만 | 수 분 |
| `make test WHAT=./pkg/... ` | 단위 테스트 (모듈 44) | 대상에 따라 |
| `make verify` | 코드 생성물/포맷 검증 (PR 전 필수) | 수십 분 |
| `make quick-release-images` | 컨테이너 이미지 빌드 (kind용) | 수십 분 |

핵심 습관: **항상 `WHAT=`으로 좁혀 빌드합니다** — 전체 빌드는 처음 한 번의 의식으로 충분합니다. 결과물은 `_output/bin/`에.

### 빌드 환경 요구

- **Go**: 리포의 `.go-version` 파일이 진실 — K8s는 특정 Go 버전에 민감합니다 (gimme/gvm 또는 수동 설치로 맞추기)
- 메모리 8GB+ (전체 빌드는 16GB 권장), 디스크 40GB+
- Docker (이미지 빌드/kind), make, git

## 3. 검증 사다리 — 수정을 어떻게 확인하나

내 수정의 영향 범위에 따라 가장 싼 검증부터:

```
1단 (초): 단위 테스트          go test ./pkg/scheduler/...   — 로직 검증
2단 (분): 바이너리 직접 실행     _output/bin/kubectl version    — CLI류는 이걸로 끝
3단 (분): 로컬 클러스터 통합     hack/local-up-cluster.sh      — 진짜 컴포넌트 조합 (리눅스)
4단 (수십 분): kind + 내 이미지  kind build node-image → 클러스터  — 노드 포함 전체
5단 (CI): e2e                  PR 올리면 prow가 (모듈 44)
```

이 사다리를 아는 것이 기여 속도의 핵심입니다 — kubectl 출력 문구 하나 고치는데 4단까지 갈 필요 없고, kubelet eviction 로직은 2단으로 못 봅니다.

### kind의 재발견

모듈 37에선 kind를 "공식 이미지로 띄우는 도구"로 썼습니다. 진짜 정체: **kind = Kubernetes IN Docker, 기여자를 위한 테스트 도구**입니다. `kind build node-image`가 내 소스 트리로 노드 이미지를 만들어주는 게 본업 — lab-02에서 씁니다.

## 4. 첫 수정의 안전 지대

처음 만지기 좋은 곳 (영향 작고 피드백 빠름):

- **kubectl의 출력/도움말 문구**: `staging/src/k8s.io/kubectl/pkg/cmd/` — 2단 검증으로 즉시 확인
- **이벤트/에러 메시지**: 검색하기 쉽고("그 메시지 어디서 나오지?" → grep) 영향 명확
- 버전 문자열, flag 설명문

lab-01에서 kubectl version 출력에 흔적을 남겨봅니다 — 유치해 보여도 "소스→빌드→실행→확인" 루프의 완주가 목적입니다.

## 5. 소스/도구에서 확인하기

- 개발 가이드(공식): https://github.com/kubernetes/community/tree/master/contributors/devel
- 빌드 가이드: 리포 루트의 `build/README.md`, `hack/` 스크립트들
- kind 기여자 가이드: https://kind.sigs.k8s.io/docs/user/quick-start/#building-images

## 요약 카드

| 질문 | 답 |
|------|----|
| 코드의 큰 지도? | cmd/(진입점) → pkg/(본체), staging/(라이브러리 원본) |
| client-go 기여는 어디에? | kubernetes/kubernetes (staging이 원본, 별도 리포는 미러) |
| 빌드 한 컴포넌트만? | `make WHAT=cmd/kubectl` → `_output/bin/` |
| Go 버전 기준? | 리포의 `.go-version` 파일 |
| 검증 순서? | 단위 테스트 → 바이너리 → local-up/kind → CI(e2e) |
| kind의 본업? | 내 소스로 노드 이미지를 빌드해 클러스터로 — 기여자 테스트 도구 |
