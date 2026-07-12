# 28 — tektoncd에 기여하기: k8s의 문법으로 움직이는 CI 커뮤니티

> 16에서 Tekton을 "CI를 CRD로 짓는" 방식으로 배웠습니다 — 이제 그 컨트롤러를 빌드하고 커뮤니티에 들어갑니다. tektoncd는 이 트랙의 세 번째 거버넌스 유형입니다: CNCF가 아니라 **CDF(Continuous Delivery Foundation)** 소속이지만, 프로세스는 Kubernetes의 것을 그대로 가져왔습니다 — OWNERS 파일, /lgtm·/approve, Prow 봇, 그리고 TEP(Tekton Enhancement Proposal). k8s 41~45를 지난 사람에게는 고향 같은 동네입니다. 보너스: Tekton은 19에서 배운 **ko로 빌드**됩니다 — 커리큘럼의 두 갈래(빌드 도구·기여)가 여기서 합류합니다.

## 학습 목표

1. tektoncd 저장소 지도(pipeline/triggers/cli/dashboard/catalog/community)와 각 문의 난이도를 압니다
2. ko(19)로 pipeline 컨트롤러를 빌드해 kind에 배포하고 — 수정→ko apply→확인 루프를 확보합니다
3. TaskRun reconcile(16의 "Task가 Pod가 되는" 경로)을 소스와 로그로 추적합니다
4. k8s식 프로세스(OWNERS·/lgtm·Prow)와 TEP 절차를 실전 문법으로 익힙니다
5. 가장 낮은 문(catalog의 Task 기여)부터 컨트롤러 기여까지 경로를 설계합니다

## 선행: 16(Tekton 사용 — 필수), 19(ko), k8s 41~45(기여 문법 — 특히 43의 OWNERS/Prow) · 도구: Go 1.23+, ko, kind, kubectl, gh
## 비용: 없음 (로컬 kind + ko는 로컬 레지스트리/kind 직접 로드)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-ko-build-and-trace.md](./lab-01-ko-build-and-trace.md) — ko 빌드·배포, TaskRun reconcile 추적
3. [lab-02-tep-and-catalog.md](./lab-02-tep-and-catalog.md) — TEP 읽기, catalog 기여, 첫 PR 경로
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
