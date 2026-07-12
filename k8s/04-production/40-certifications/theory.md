# 이론 — 시험 구조, 도메인-모듈 매핑, 속도 기술

> **🌱 17세 눈높이 비유: 운전면허 기능시험**
> 필기(개념)는 이미 끝났습니다 — 기능시험은 **정해진 코스를 제한 시간 안에, 검정원이 보는 앞에서** 수행하는 것입니다. 평소 운전 잘하는 사람도 코스 연습 없이 가면 떨어집니다: T자 코스(자주 나오는 문제 유형)와 시간 배분을 몸에 붙이는 게 남은 전부입니다.

---

## 1. 공통 시험 구조 (3종 모두)

- **실기**: 원격 감독 하에 제공된 클러스터들을 터미널로 조작, 결과 상태로 채점
- 2시간, 15~20문제, 문제마다 배점 다름 (부분 점수 있음)
- **공식 문서 열람 가능** (kubernetes.io/docs 등 허용 탭) — 암기 시험이 아닙니다
- 문제마다 **컨텍스트 전환 명령이 제시**됩니다 (`kubectl config use-context k8s-xxx`) — 안 바꾸고 풀면 0점
- 합격선 ~66-67%, 불합격 시 재응시 1회 포함(구매 기준) — 세부는 응시 시점 공식 확인

## 2. CKA 도메인 ↔ 모듈 매핑

| CKA 도메인 (비중) | 다루는 것 | 우리 모듈 |
|---|---|---|
| 클러스터 아키텍처/설치/구성 (25%) | RBAC, kubeadm, etcd 백업, Helm/Kustomize | 02, 11, 17, 18, 22, 41 |
| 워크로드/스케줄링 (15%) | Deployment 롤링/롤백, ConfigMap/Secret, 스케줄링, HPA | 04, 07, 12, 13 |
| 서비스/네트워킹 (20%) | Service, Ingress/**Gateway API**, NetworkPolicy, CoreDNS | 05, 06, 15, 16 |
| 스토리지 (10%) | PV/PVC/StorageClass, 동적 프로비저닝 | 08 |
| 트러블슈팅 (30%) ★ | 노드/Pod/Service 장애, 로그, 모니터링 | **38 (+14, 26)** |

→ 트러블슈팅이 30%로 최대 — 모듈 38을 잘 통과했다면 이미 최대 도메인이 준비됐습니다. 상대적 구멍: **kubeadm 기반 조작**(EKS에선 안 해봄 — etcd 백업/복원, 클러스터 업그레이드의 kubeadm 명령). 모듈 22(로컬 etcd)와 41(kind/소스 빌드)이 보완하고, 시험 전 kubeadm 문서 경로를 익혀두라.

## 3. CKAD 도메인 ↔ 모듈 매핑

| CKAD 도메인 | 우리 모듈 |
|---|---|
| 앱 설계/빌드 (컨테이너, Job, 멀티컨테이너) | 01, 03, 20 |
| 배포 (롤링, Blue/Green, Helm/Kustomize) | 04, 17, 18 |
| 관측/유지 (probe, 로그, 디버깅) | 14, 38 |
| 환경/구성/보안 (CM/Secret, SA, securityContext, quota) | 07, 09, 11, 32 |
| 서비스/네트워킹 | 05, 06, 15 |

→ 초·중급 트랙으로 사실상 전부 커버. CKA와 겹침이 커서 "CKA 합격자라면 추가 공부 거의 없이" 응시 가능한 수준.

## 4. CKS 도메인 ↔ 모듈 매핑

| CKS 도메인 | 우리 모듈 | 보완 필요 |
|---|---|---|
| 클러스터 셋업/하드닝 (CIS, 네트워크 정책) | 33, 15 | kube-bench 손익숙 |
| 시스템 하드닝 (커널, 최소화) | 26, 32 | AppArmor 직접 |
| 마이크로서비스 취약점 최소화 (PSA, secret, 샌드박스) | 32, 07 | gVisor/런타임 클래스 |
| 공급망 보안 (이미지 스캔/서명, SBOM) | 33 | 정책 연동 실습 |
| 모니터링/런타임 보안 (Falco, 감사 로그) | 21 | **Falco** (cncf 파트에서) |

→ CKS만 "커리큘럼 밖" 항목이 좀 있습니다(Falco, gVisor, AppArmor) — cncf 파트 이후 응시가 자연스럽습니다.

## 5. 속도 기술 — 시험의 절반

### 시작하자마자 (시험 환경 셋업 30초)

```bash
alias k=kubectl                          # 보통 이미 설정돼 있음
export do='--dry-run=client -o yaml'     # k run x --image=y $do > p.yaml
export now='--grace-period=0 --force'    # 삭제 대기 없이
# vim: set ts=2 sw=2 et  (~/.vimrc — YAML 들여쓰기)
```

### YAML을 손으로 치지 않습니다 — 생성기 + 수정

```bash
k run web --image=nginx $do > pod.yaml                       # Pod 뼈대
k create deploy app --image=nginx --replicas=3 $do           # Deployment
k expose deploy app --port=80 --target-port=8080 $do         # Service
k create job j --image=busybox $do -- sh -c 'echo hi'        # Job
k create cronjob c --image=busybox --schedule='*/5 * * * *' $do -- date
k create cm conf --from-literal=k=v $do
k create role r --verb=get,list --resource=pods $do          # RBAC도 생성기로!
k create rolebinding rb --role=r --serviceaccount=ns:sa $do
```

### 모르는 필드는 explain (문서 탭보다 빠릅니다)

```bash
k explain pod.spec.affinity --recursive | less
k explain deploy.spec.strategy
```

### 검증 한 방 모음 (채점자는 상태만 봅니다)

```bash
k get pod x -o wide                       # 떠 있나, 어디에
k auth can-i get pods --as=system:serviceaccount:ns:sa   # RBAC 됐나
k run t --rm -it --image=busybox --restart=Never -- wget -qO- svc   # 연결 되나
```

## 6. 시간 배분 전략

```
120분 / ~16문제 = 평균 7분. 실제 운용:
- 1회독: 쉬운 것부터 (2~4분짜리 먼저 쓸어담기) — 어려운 건 flag
- 2회독: flag 문제 (배점 높은 것 우선)
- 마지막 10분: 검증 못 한 문제 재확인 (컨텍스트 틀림이 없는지!)
철칙: 한 문제 10분 초과 금지. 부분 점수가 있습니다 — 절반이라도 만들고 넘어가라.
```

## 요약 카드

| 질문 | 답 |
|------|----|
| 시험 성격? | 실기 — 문서 열람 가능, 결과 상태로 채점 |
| 권장 순서? | CKA → (직군 따라) CKS / CKAD |
| CKA 최대 도메인? | 트러블슈팅 30% (모듈 38) |
| 우리의 상대적 구멍? | kubeadm 조작(CKA), Falco/gVisor(CKS) |
| 속도의 핵심? | 생성기+$do로 YAML 안 치기, explain, 문제당 7분 |
| 0점 지름길? | 컨텍스트 전환 누락 |
