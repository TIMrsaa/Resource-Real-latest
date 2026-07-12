# 자가 점검 퀴즈

**Q1.** CRI-O의 설계 철학을 containerd(26)와 대비해 한 문장으로. 25(Linkerd)의 무엇이 반복되나요?

**Q2.** CRI-O의 아키텍처 구성 요소는? conmon의 역할은 26의 무엇에 대응하나요?

**Q3.** CRI-O의 K8s 정렬 버저닝이 주는 이점과 제약은? containerd와 어떻게 다른가?

**Q4.** containers/ 생태계란? CRI-O와 어떤 도구들이 무엇을 공유하나요?

**Q5.** CRI-O의 기본 OCI 런타임은? runc와의 차이와 그 선택 근거는?

**Q6.** containerd와 CRI-O의 공통점 다섯 가지는?

**Q7.** 런타임 서명 검증(policy.json)이 21의 admission 검증과 어떤 관계인가요?

**Q8.** "런타임은 대개 플랫폼이 정한다"의 의미와, 이 모듈의 실무 가치는?

---

## 정답

**A1.** containerd가 범용 컨테이너 데몬(K8s·Docker·nerdctl·다양한 워크로드)이라면 CRI-O는 "쿠버네티스가 필요한 것만 구현하는 K8s 전용 미니멀리스트"다. 25(Linkerd)의 "단순함도 설계 결정"이 반복됩니다 — CRI-O는 K8s 밖 범용성을 포기해 표면적 최소화와 K8s 정렬을 얻었고, 이는 Linkerd가 메시에서 기능을 최소화한 것과 같은 종류의 선택입니다("범위를 좁히는 것도 설계, 안 쓸 기능은 부채").

**A2.** CRI 구현(RunPodSandbox 등 kubelet 요청 처리) + containers/storage(이미지·컨테이너 저장) + containers/image(pull·서명 검증) + conmon(컨테이너 모니터) + crun(기본 OCI 런타임)의 조립. conmon은 26의 shim v2에 대응합니다 — 컨테이너당 하나로 stdio·종료 코드를 지키고 CRI-O 재시작에도 컨테이너가 생존하게 합니다(같은 역할, 다른 구현).

**A3.** CRI-O 1.30은 Kubernetes 1.30과 함께 릴리스·지원됩니다. 이점: K8s 버전에 정확히 맞는 CRI 구현(명세 변화 즉시 반영), "어느 런타임 버전이 우리 K8s와 맞나"라는 질문 자체가 소멸, K8s 업그레이드 시 런타임도 자연히 맞춰짐. 제약: CRI-O를 K8s와 독립적으로 업그레이드 불가, K8s 밖에서 쓸 이유 없음. containerd는 독립 버저닝이라 유연하지만 호환성 매트릭스를 확인해야 합니다 — 두 철학이 정반대입니다.

**A4.** Red Hat 주도의 containers/ 조직이 제공하는 공유 라이브러리·도구 생태계. containers/storage(이미지·컨테이너 저장)는 CRI-O·Podman·Buildah가 공유하고, containers/image(pull·서명 검증)는 CRI-O·Podman·Skopeo가 공유합니다. 형제 도구: Podman(데몬리스 실행 — Docker 대체), Buildah(이미지 빌드), Skopeo(이미지 검사·복사). CRI-O는 이 검증된 라이브러리들을 조립합니다("덜 만들고 더 조립") — containerd의 자체 구현 계보와 다른 생태계입니다.

**A5.** crun(C로 작성). runc(Go)와의 차이: crun이 바이너리가 작고 시작이 빠르며 메모리를 적게 씁니다. 선택 근거: CRI-O가 K8s 전용이라 "가장 효율적인 기본값"을 고를 자유가 있고, 고밀도 노드에서 컨테이너당 오버헤드가 누적되므로 경량 런타임이 유리합니다. 단 격리 스펙트럼(03)은 런타임과 무관하게 적용되어 CRI-O도 RuntimeClass로 runc·gVisor(runsc)·Kata를 고를 수 있습니다.

**A6.** ① 둘 다 CRI 명세를 구현해 kubelet과 같은 방식으로 대화. ② 둘 다 OCI 런타임(runc/crun/kata/runsc)을 호출 — 03의 격리 스펙트럼 동일. ③ 둘 다 OCI 이미지(image-spec)를 사용 — 빌드 도구와 무관(cicd 19). ④ 둘 다 crictl로 CRI 레벨 디버깅 가능. ⑤ 둘 다 CNCF Graduated. 즉 "무엇을 하느냐"(CRI 런타임)는 같고 "어떻게, 얼마나"(범위·구조·버저닝·생태계)가 다릅니다.

**A7.** 다층 방어의 서로 다른 층입니다 — policy.json(containers/image)의 서명 검증은 런타임 레벨(이미지 pull 시점), 21의 admission(Kyverno)은 배포 시점입니다(07의 시간선). 런타임 검증만 있으면 정책 위반 이미지가 배포 시점에 안 걸러져 노드까지 가서 실패하고(늦은 피드백), admission만 있으면 그것을 우회한 경로(수동 crictl pull 등)를 못 막습니다. 대체가 아니라 시간선의 여러 층에 방어를 두는 것이며, OpenShift가 이미지 정책을 통합 제공해도 admission 정책을 불필요하게 만들지는 않습니다.

**A8.** 관리형 K8s가 런타임을 정합니다 — EKS·GKE·AKS·kind는 containerd, OpenShift는 CRI-O로 사실상 고정되어 있어 직접 고르는 경우가 드뭅니다("EKS에서 CRI-O 쓰기"는 지원 밖이거나 큰 부담). 이 모듈의 실무 가치는 선택이 아니라 **인지**입니다: 우리 플랫폼의 런타임이 무엇이고 그 특성(버저닝 정책·저장 경로·진단 도구·생태계)을 아는 것. 런타임 철학을 배우는 것은 "고르기 위해"가 아니라 "이미 쓰는 것을 이해하기 위해"이며, 문제가 생겼을 때 올바른 도구로 올바른 경로를 볼 수 있게 하기 위함입니다(사고 사례).
