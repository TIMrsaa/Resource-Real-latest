# 자가 점검 퀴즈

**Q1.** Helm과 Kustomize의 원본 YAML에 대한 철학 차이를 한 문장씩으로.

**Q2.** 오버레이가 base를 "수정"하는가요? 환경 차이는 어디에 존재하는가요?

**Q3.** configMapGenerator가 만든 ConfigMap 이름의 특징과, 그것이 유발하는 배포 동작의 사슬을 쓰라.

**Q4.** strategic merge 패치와 JSON6902 패치의 선택 기준은?

**Q5.** "외부 Helm 차트에 회사 표준 라벨을 강제"하는 조합 패턴의 명령 흐름은?

**Q6.** nameSuffix를 붙였더니 앱이 Service를 못 찾습니다. 원인 후보는?

**Q7.** `kubectl apply -k`와 독립 kustomize CLI의 차이 중 주의점은?

---

## 정답

**A1.** Helm: 원본은 **템플릿**(그 자체로는 invalid YAML)이고 값 치환으로 완성. Kustomize: 원본은 **항상 유효한 완전한 YAML**이고 패치를 겹쳐 변형.

**A2.** 수정하지 않습니다 — 빌드 시점에 겹쳐질 뿐. 환경 차이는 **오버레이 디렉터리의 패치 파일**에만 존재합니다 (그래서 diff가 곧 환경 차이 문서).

**A3.** 내용 **해시 접미사**(app-config-7f9h...)가 붙고, 이를 참조하는 워크로드의 참조 이름도 자동 갱신. 사슬: 내용 변경 → 새 이름 CM → Pod template 변경 → 새 ReplicaSet → **자동 롤링 업데이트** (+옛 CM 보존으로 롤백 가능).

**A4.** 컨테이너 등 **이름 키가 있는 리스트/필드 변경**은 strategic merge(인덱스 불요, 안전). **삭제(remove)나 strategic이 지원 못 하는 정밀 연산**은 6902 — 단 배열 인덱스 취약성 감수.

**A5.** `helm template <release> <chart> > rendered.yaml` → kustomization.yaml의 resources에 포함 → labels/patches로 회사 정책 주입 → `kubectl apply -k .` (GitOps 도구는 이 조합을 내장 지원).

**A6.** Kustomize는 참조 필드는 이름 변경을 추적하지만 **문자열 속 참조**(env 값의 URL 등)는 못 바꿉니다 — 앱 설정에 하드코딩된 옛 Service 이름이 남았을 가능성. (또는 suffix가 안 붙는 외부 리소스와의 불일치)

**A7.** kubectl 내장 kustomize는 **버전이 뒤처져** 최신 필드가 동작하지 않을 수 있습니다 — 팀/CI의 kustomize 버전을 통일하고, 빌드 결과 diff를 CI에서 검증.
