# 자가 점검 퀴즈

**Q1.** 차트와 릴리스의 차이, 그리고 릴리스 이력이 저장되는 곳은?

**Q2.** values의 우선순위(values.yaml / -f / --set)는?

**Q3.** `{{- toYaml .Values.resources | nindent 2 }}` 에서 `-`와 `nindent` 각각의 역할은?

**Q4.** HPA를 쓰는 차트에서 Deployment 템플릿이 해야 하는 조건 처리는? (이유 포함)

**Q5.** `--atomic`이 운영 표준 플래그인 이유를 실패 시나리오로 설명하세요.

**Q6.** DB 마이그레이션을 배포와 원자적으로 묶는 Helm 메커니즘과 핵심 annotation 2개는?

**Q7.** 차트의 crds/ 디렉터리에 둔 CRD가 upgrade에서 갱신되지 않는 이유와 대처는?

---

## 정답

**A1.** 차트=패키지(틀), 릴리스=특정 values로 설치된 인스턴스. 이력은 클러스터 내 **Secret**(`sh.helm.release.v1.<name>.v<rev>`)에 revision별로 저장.

**A2.** values.yaml(기본) < `-f` 파일들(나중 파일 우선) < `--set`(최우선).

**A3.** `-`: 템플릿 액션 앞의 공백/개행 제거(들여쓰기 제어). `nindent 2`: 결과 블록 전체를 개행 후 2칸 들여쓰기 — 구조체를 YAML 트리의 올바른 위치에 꽂는 표준 콤보.

**A4.** `{{- if not .Values.autoscaling.enabled }} replicas: ... {{- end }}` — HPA가 관리하는 replicas를 매 upgrade가 덮어쓰면 스케일된 Pod가 순간 정리되는 사고(모듈 13 pitfall)가 나기 때문.

**A5.** 새 이미지가 안 뜨는 등 upgrade 실패 시, atomic이 없으면 릴리스가 어중간한 상태(일부 리소스만 갱신)로 남습니다. atomic은 실패 감지 시 **자동으로 직전 revision으로 롤백**해 "성공 아니면 원상복구"를 보장합니다.

**A6.** **hook Job** — `"helm.sh/hook": pre-upgrade`(업그레이드 전 실행, 실패 시 업그레이드 중단)와 `"helm.sh/hook-delete-policy"`(완료된 Job 정리). atomic과 결합하면 마이그레이션 실패 = 배포 자동 롤백.

**A7.** CRD 삭제/변경이 기존 커스텀 리소스 데이터를 파괴할 수 있어 Helm이 의도적으로 손대지 않습니다(설치 시 1회만). 대처: CRD 변경은 릴리스와 별도로 `kubectl apply --server-side`로 명시적 적용 (차트 업그레이드 절차 문서에 포함).
