# 자가 점검 퀴즈

**Q1.** "Helm의 발명품은 템플릿이 아니라 릴리스다"를 설명하세요. 릴리스는 어디에 무엇으로 저장되나요?

**Q2.** `helm upgrade`의 3-way 병합에서 세 상태는 무엇이고, 패치 계산 규칙은?

**Q3.** kubectl로 바꾼 replicas가 어떤 때는 살아남고 어떤 때는 덮이는 이유를 3-way 병합으로 설명하세요.

**Q4.** HPA가 있는 차트에서 replicas를 어떻게 다뤄야 하나요? 이것이 cicd 14의 어떤 문제와 같은가요?

**Q5.** 템플릿 엔진의 3대 함정과 각각의 방어(함수·도구)는?

**Q6.** 훅의 두 가지 위험과 각각의 대응은? 훅이 보장하는 것과 보장하지 않는 것은?

**Q7.** `crds/` 디렉터리의 특별 취급 세 가지와 그 이유는?

**Q8.** Helm과 GitOps의 긴장을 푸는 세 가지 방식과, 어느 쪽이든 지켜야 할 규율은?

---

## 정답

**A1.** K8s에는 "애플리케이션"이라는 개념이 없습니다 — Deployment·Service·ConfigMap이 흩어져 있을 뿐입니다. Helm의 릴리스는 "이 이름으로 설치된 오브젝트 목록 + values + 렌더링된 매니페스트 전문 + 상태"를 하나의 단위로 묶어, 업그레이드·롤백·삭제를 단일 명령으로 만듭니다. 저장 위치: 릴리스 네임스페이스의 Secret(`sh.helm.release.v1.<name>.v<revision>`), 내용은 base64(gzip(JSON)) — revision마다 하나씩 쌓입니다(기본 최대 10).

**A2.** old(이전 릴리스에 저장된 매니페스트 = Helm이 마지막으로 준 것), live(클러스터의 현재 오브젝트), new(방금 렌더링한 매니페스트). 규칙: old에 있고 new에 없으면 삭제 대상, old와 new가 다르면 new 값으로, **old에 없고 live에만 있는 것은 그대로 둡니다**(Helm이 모르는 것은 안 건드립니다).

**A3.** kubectl로 replicas를 2→5로 바꾼 뒤 values를 안 건드리고 upgrade하면 old(2)==new(2)이므로 Helm은 그 필드를 "변경 없음"으로 보고 live(5)를 유지합니다. 반면 values를 2→3으로 바꾸면 old(2)≠new(3)이 되어 Helm이 그 필드를 관리 대상으로 판단하고 3으로 덮어씁니다(lab-01 Step 5·6에서 실증). 같은 필드인데 결과가 다른 것은 병합이 "내가 마지막에 준 값이 바뀌었는가"를 기준으로 삼기 때문입니다.

**A4.** 차트에서 replicas를 아예 선언하지 않거나(`{{- if not .Values.autoscaling.enabled }}`로 조건부) HPA에 소유권을 넘겨야 합니다 — 그러지 않으면 HPA가 올린 값을 Helm이 되돌리고 HPA가 다시 올리는 진동이 생깁니다. cicd 14의 **필드 소유권 다툼**(Git에도 replicas가 있고 HPA도 replicas를 바꾸는 OutOfSync 루프)과 정확히 같은 문제입니다. 도구를 바꾸는 것이 아니라 "누가 이 필드의 주인인가"를 설계로 정하는 것이 답.

**A5.** ① 들여쓰기: 중첩 구조를 그대로 삽입하면 YAML이 깨집니다 → `toYaml | nindent 4`(개행+들여쓰기) 또는 `indent`. ② 타입: `"true"`·`"123"`이 bool·int로 해석되어 스키마 검증 실패 → `| quote`, `| int`. ③ 값 부재: nil이 렌더링되어 이상한 YAML → `| default`. 방어 도구: `helm lint`(정적), `helm template --debug`(클러스터 없이 렌더 확인), `helm install --dry-run`(API 서버 검증 포함), `values.schema.json`(입력 사전 차단), 렌더 결과에 conftest(cicd 24).

**A6.** 위험 ①: 훅 리소스는 릴리스 매니페스트에 포함되지 않아 uninstall 후에도 남고 다음 실행과 충돌합니다 → `hook-delete-policy` 명시(before-hook-creation / hook-succeeded / hook-failed). 위험 ②: 훅이 실패하면 업그레이드는 중단되지만 **이미 발생한 부작용(ALTER TABLE 등)은 롤백되지 않습니다** → 마이그레이션을 멱등·전진 호환(expand-contract, cicd 11)으로 설계. 훅이 보장하는 것은 **순서**뿐이고, 멱등성과 안전한 재시도는 우리 몫입니다.

**A7.** ① 템플릿 렌더링을 하지 않습니다(`{{ }}` 미지원 — 순수 YAML). ② 설치(install) 시에만 생성합니다. ③ upgrade·uninstall에서 건드리지 않습니다. 이유: CRD 삭제는 그 CRD의 모든 커스텀 리소스 데이터를 함께 삭제하므로 극도로 위험하고, CRD 업그레이드는 스키마 호환성 검토가 필요한 별도 절차이기 때문입니다(의도된 안전장치). 결과적으로 "차트 업그레이드했는데 CRD 새 필드가 없다"가 자주 발생하며, CRD 버전 관리는 수동 apply·별도 차트·오퍼레이터로 계획해야 합니다.

**A8.** ① ArgoCD 방식: `helm template`으로 렌더링만 하고 릴리스를 만들지 않습니다 — Git이 유일한 진실, 롤백은 Git revert. ② Flux 방식: HelmRelease CR을 Git에 두고 helm-controller가 실제 릴리스를 관리 — Helm의 상태 기계(history·rollback)를 유지하면서 선언은 Git에. ③ CI 렌더: CI가 `helm template` 결과를 Git에 커밋 — PR diff가 정직해 감사에 강함. 공통 규율: **helm CLI와 GitOps 컨트롤러가 같은 릴리스를 동시에 관리하지 않습니다**(사람이 프로덕션에 helm 명령을 직접 실행하지 않으며, 예외는 break-glass 절차로 기록·복원).
