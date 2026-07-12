# 자가 점검 퀴즈

**Q1.** Tekton의 CRD 모델 네 가지를 정의(Task/Pipeline)와 실행(Run)으로 나눠 설명하세요.

**Q2.** TaskRun과 Pod의 관계, step과 컨테이너의 관계는? 이것이 03의 무엇과 동형인가요?

**Q3.** CI가 "완전히 쿠버네티스"라는 것이 주는 구체적 이점 세 가지는? (k8s/eks 파트의 도구로)

**Q4.** Workspace의 역할과, emptyDir vs PVC의 선택 기준은?

**Q5.** Tekton Triggers의 세 리소스와, GitHub Actions의 무엇을 손으로 조립하는 것인가요?

**Q6.** "대부분의 조직은 SaaS CI가 맞다"의 근거와, Tekton이 정당한 맥락 세 가지는?

**Q7.** Tekton을 "직접 쓰기보다 그 위에 얹는다"의 의미와 예는?

**Q8.** CI가 Pod라서 얻는 보안적 강점과, 동시에 놓치기 쉬운 위험은?

---

## 정답

**A1.** 정의: Task(재사용 단위 — steps=컨테이너들), Pipeline(Task들의 조합, 순서·의존). 실행: TaskRun(Task의 실행 인스턴스 → Pod), PipelineRun(Pipeline의 실행 → 여러 Pod). 정의는 클러스터 리소스로 재사용, 실행은 인스턴스로 매번 생성.

**A2.** 하나의 TaskRun = 하나의 Pod, 각 step = 그 Pod의 컨테이너(순차 실행, 볼륨 공유). 03의 **"같은 잡의 스텝은 파일시스템 공유"**(같은 러너)와 동형 — Tekton에선 "같은 Pod의 컨테이너는 볼륨 공유". 잡 간(Task 간)은 Workspace로 전달.

**A3.** ① 리소스/노드 제어: Task 컨테이너에 requests/limits(k8s 06), nodeSelector로 arm 노드에 arm 빌드(eks 19). ② 스케일: Karpenter가 CI 부하로 노드 생성(eks 17). ③ 격리·보안: NetworkPolicy로 CI Pod egress 제한(eks 18), PSA/보안 컨텍스트(eks 25), 시크릿 관리(External Secrets — 14). CI 실행 환경이 K8s라 클러스터 운영 지식이 그대로 적용.

**A4.** Workspace는 Task 간 데이터(소스·아티팩트)를 볼륨으로 공유(03의 잡 간 artifacts 대응). emptyDir: PipelineRun 종료 시 소멸(캐시 안 남음, 단순). PVC: 지속(캐시 재사용 가능, 04의 캐시), 성능·격리 고려. 대용량 캐시가 필요하면 PVC.

**A5.** EventListener(webhook 수신 Pod), TriggerBinding(페이로드에서 값 추출), TriggerTemplate(PipelineRun 생성). GitHub Actions의 **`on: push`(내장 트리거)**를 명시적으로 조립하는 것 — 로우레벨의 대가이자 유연성.

**A6.** 근거: Tekton은 로우레벨 빌딩 블록이라 UI·트리거·시크릿·재사용을 직접 조립해야 하고, 대부분의 조직에는 SaaS의 빠른 시작·개발자 경험이 낫습니다. 정당한 맥락: ① 멀티클라우드/온프레/에어갭(SaaS 못 씀) ② CI 플랫폼을 직접 구축(플랫폼 팀) ③ 클러스터가 이미 인프라 중심이고 CI에 K8s 도구를 깊이 적용해야 할 때.

**A7.** Tekton은 CI 시스템을 조립하는 부품(엔진)이라, 개발자에게 Task YAML을 직접 쓰게 하면 나쁜 경험을 줍니다 — 그 위에 개발자 인터페이스(플랫폼)를 얹어야 합니다. 예: OpenShift Pipelines, Jenkins X, 사내 IDP(내부 개발자 플랫폼)의 실행 엔진으로 Tekton을 쓰고 개발자는 상위 추상을 봅니다.

**A8.** 강점: CI가 Pod라 K8s 보안 전부 적용 가능(최소 권한 SA, NetworkPolicy egress 제한, PSA, kaniko로 dind 회피 — 08·eks 25). 놓치기 쉬운 위험: 그것을 안 하면 08의 self-hosted 러너 위험이 그대로(관리자급 SA, 열린 egress, privileged dind) — 오히려 클러스터 안이라 더 위험. Tekton Hub Task의 공급망 위험(21)도 K8s 네이티브라고 사라지지 않습니다.
