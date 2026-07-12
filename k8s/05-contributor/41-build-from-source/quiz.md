# 자가 점검 퀴즈

**Q1.** cmd/ / pkg/ / staging/ 각각의 역할과, "kubectl 본체"가 있는 곳은?

**Q2.** client-go의 버그를 고치려면 어느 리포에 PR을 보내는가요? 그 이유는?

**Q3.** 스케줄러 코드만 다시 빌드하는 명령과 결과물 위치는?

**Q4.** 검증 사다리 5단을 싼 것부터 쓰고, "kubectl 출력 문구 수정"과 "kubelet eviction 로직 수정"의 적정 단은?

**Q5.** kind의 "본업"과 그것을 쓰는 명령은?

**Q6.** `zz_generated.*.go` 파일에 고칠 게 보일 때의 올바른 절차는?

**Q7.** "이 에러 메시지를 내는 코드가 어딘지" 찾는 기여자의 기본기는?

**Q8.** 빌드 환경에서 Go 버전의 기준은 무엇이며 왜 시스템 최신을 그냥 쓰면 안 되는가요?

---

## 정답

**A1.** cmd/ = 각 컴포넌트의 main()(진입점, 얇음), pkg/ = 구현 본체, staging/src/k8s.io/ = 별도 배포되는 라이브러리들의 **원본**. kubectl 본체는 `staging/src/k8s.io/kubectl/`.

**A2.** **kubernetes/kubernetes** — kubernetes/client-go 리포는 staging에서 자동 동기화되는 읽기 전용 미러라 직접 PR을 받지 않습니다.

**A3.** `make WHAT=cmd/kube-scheduler` → `_output/bin/kube-scheduler`.

**A4.** ① 단위 테스트(초) ② 빌드한 바이너리 직접 실행(분) ③ hack/local-up-cluster.sh(분) ④ kind build node-image + 클러스터(수십 분) ⑤ CI의 e2e(prow). kubectl 문구 = 2단으로 끝. kubelet eviction = 단위 테스트로 로직 고정 후 3단(또는 4단)에서 통합 확인.

**A5.** 본업은 기여자 테스트 도구 — **내 소스 트리로 노드 이미지를 빌드**해 클러스터로 띄우는 것: `kind build node-image [소스경로]` → `kind create cluster --image <빌드한 이미지>`.

**A6.** 생성 파일은 직접 수정 금지. 원본(타입 정의/마커 주석)을 고친 뒤 생성 스크립트(`make generated_files` 등 hack/의 해당 도구)로 재생성 — 직접 고치면 빌드는 돼도 PR에서 반려.

**A7.** **메시지 문자열로 grep** — `grep -rn "에러 문구" pkg/ staging/`. 로그/이벤트/에러 문구는 코드로 가는 가장 빠른 입구입니다 (lab-01/02 둘 다 이 방법으로 수정 지점을 찾았습니다).

**A8.** 리포의 `.go-version` 파일. K8s는 특정 Go 버전에 맞춰 CI/툴체인이 고정돼 있어, 다른 버전은 빌드 거부나 미묘한 차이를 만듭니다 — "리포가 말하는 버전"이 항상 우선.
