# 자가 점검 퀴즈

**Q1.** 파이프라인 7단계를 순서대로 쓰고, Mutating이 Validating보다 앞인 이유를 설명하세요.

**Q2.** 401 / 403 / 409 / 410 / 422 / 429 — 각각 파이프라인의 어느 부분(또는 어떤 메커니즘)의 소리인가요?

**Q3.** 낙관적 동시성 제어가 "낙관적"인 이유와, 비관적(잠금) 방식 대비 장점은?

**Q4.** API 서버의 watch cache가 보호하는 것과 그 방법은?

**Q5.** APF가 옛 단일 인플라이트 한도보다 나은 점을 시나리오로 설명하세요.

**Q6.** "지난주 누가 prod의 db-cred Secret을 읽었나"를 EKS에서 조사하는 방법은?

**Q7.** 제출한 적 없는 `strategy: RollingUpdate`가 내 Deployment에 들어 있는 이유는?

---

## 정답

**A1.** 인증 → 인가 → **Mutating admission** → 스키마/CEL 검증 → **Validating admission** → etcd 저장 → watch 통보. Mutating이 객체를 고치므로, **고쳐진 최종본**을 검증해야 의미가 있습니다(수정 후 검증).

**A2.** 401=인증(①) 실패, 403=인가(②) 거부, 409=etcd 저장 시 resourceVersion 충돌(낙관적 동시성), 410=watch의 rv가 너무 오래됨(compaction — relist 필요), 422=스키마 검증(④) 실패, 429=APF 예산 초과.

**A3.** "충돌은 드물 것"이라 가정하고 잠금 없이 진행, 충돌 시에만 거부+재시도하므로 낙관적. 장점: 잠금 대기/데드락이 없어 **고동시성에서 처리량이 높고**, 죽은 클라이언트가 잠금을 쥐고 있는 문제가 없습니다.

**A4.** **etcd**를 보호합니다. API 서버가 etcd watch를 리소스당 1개만 유지하고, 수천 클라이언트의 watch에는 자기 메모리 캐시에서 부채질(fan-out)합니다 — 클라이언트 수와 etcd 부하를 분리.

**A5.** 단일 한도에서는 폭주 클라이언트(LIST 폭탄)가 한도를 다 차지해 kubelet 하트비트까지 굶습니다 → 노드가 NotReady로 오판되는 연쇄. APF는 분류별(FlowSchema) 전용 예산이라 **시스템 생명선은 폭주와 무관하게 처리**됩니다.

**A6.** EKS control plane audit 로깅 활성화(상시) → CloudWatch Logs `/aws/eks/<cluster>/cluster`의 kube-apiserver-audit 스트림에서 `objectRef.name="db-cred", verb="get"` 필터 → 기록된 IAM ARN으로 주체 식별.

**A7.** Mutating admission 단계의 **기본값 주입** — API 서버가 스키마 기본값과 admission 플러그인으로 미지정 필드를 채워 저장했기 때문.
