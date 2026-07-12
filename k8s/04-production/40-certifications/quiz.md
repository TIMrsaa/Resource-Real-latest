# 자가 점검 퀴즈 (실무 트랙 졸업 시험 겸용)

**Q1.** CKA/CKAD/CKS의 관점 차이와 권장 응시 순서, CKS의 전제 조건은?

**Q2.** 세 시험의 공통 형식 3가지(채점 방식 포함)는?

**Q3.** CKA 최대 비중 도메인과 그것을 담당하는 우리 모듈은?

**Q4.** EKS 기반 학습자의 CKA 상대적 약점 영역과 보완 방법은?

**Q5.** `--dry-run=client -o yaml`이 시험/실무에서 갖는 가치는?

**Q6.** "만들었는데 0점"이 나는 대표적 두 가지 원인은?

**Q7.** RBAC 문제(SA+Role+Binding+검증)를 YAML 없이 푸는 명령 4줄의 골격은?

**Q8.** 이 모듈에서 측정 결과가 낮게 나왔을 때의 올바른 다음 행동은?

---

## 정답

**A1.** CKA=클러스터 관리자(구성/수리), CKAD=앱 개발자(워크로드 설계/배포), CKS=보안 전문가(하드닝/공급망/런타임). 권장: CKA 먼저 → 직군 따라 CKS/CKAD. CKS는 **유효한 CKA 보유**가 응시 전제.

**A2.** ① 실기 — 실제 클러스터를 터미널로 조작 ② 공식 문서 열람 허용(암기 시험 아님) ③ **결과 상태로 채점**(과정이 아니라 만들어진 리소스의 상태 + 부분 점수).

**A3.** 트러블슈팅(30%) — 모듈 38(+14 probe, 26 노드/kubelet). 모듈 38의 진단 루틴(describe→events→logs --previous→endpoints)이 그대로 시험 기술입니다.

**A4.** kubeadm 기반 조작 — EKS는 control plane이 관리형이라 etcd 백업/복원(`etcdctl snapshot save/restore`), kubeadm 업그레이드를 실물로 안 해봤습니다. 보완: 모듈 22(로컬 etcd 실습)가 절반, 모듈 41(kind/소스 빌드)이 나머지 + kubeadm 공식 문서 경로 숙지.

**A5.** YAML을 백지에서 안 칩니다 — 생성기로 뼈대를 만들어 파일로 받고 필요 필드만 수정. 오타·들여쓰기 사고 차단 + 문제당 수 분 절약. 실무에서도 새 매니페스트의 출발점.

**A6.** ① 컨텍스트/ns 전환 누락(엉뚱한 곳에 정답 생성) ② 검증 생략(Running/endpoints/can-i 확인 안 함 — 미완성 상태로 제출).

**A7.** `k create sa <sa> -n <ns>` → `k create role <r> -n <ns> --verb=... --resource=...` → `k create rolebinding <rb> -n <ns> --role=<r> --serviceaccount=<ns>:<sa>` → `k auth can-i <verb> <res> -n <ns> --as=system:serviceaccount:<ns>:<sa>`.

**A8.** 막힌 문제 → 모듈 매핑으로 약점을 식별하고, 풀이 명령을 손에 붙인 뒤(3회 반복) 해당 모듈을 복습하고 재도전. 통과(11+/14)했다면 — 이 커리큘럼의 진짜 목적지인 **05-contributor 트랙**으로 갑니다.
