# 자가 점검 퀴즈 (초급 졸업 시험 겸용)

**Q1.** Deployment의 `progressDeadlineSeconds` 필드가 뭔지 모릅니다. 검색 없이 알아내는 명령은?

**Q2.** `--dry-run=client`와 `--dry-run=server`의 차이는?

**Q3.** apply가 "멱등"이라는 말의 의미와, 그것이 CI/CD에 중요한 이유는?

**Q4.** 모든 Pod의 "이름과 노드"를 탭 구분으로 출력하는 jsonpath 명령을 쓰라.

**Q5.** strategic merge patch가 JSON merge patch와 컨테이너 배열을 다르게 다루는 점은?

**Q6.** distroless 이미지 Pod에서 네트워크 문제를 조사해야 합니다. 명령과 동작 원리는?

**Q7.** (종합) 새로 배포한 Pod가 `CrashLoopBackOff`입니다. 순서대로 칠 명령 3개는?

**Q8.** (종합) Service까지는 정상인데 외부 LB에서 503. 확인 순서는? (모듈 05~06 종합)

---

## 정답

**A1.** `kubectl explain deployment.spec.progressDeadlineSeconds`

**A2.** client: kubectl이 **로컬에서 문법만** 검사. server: API 서버에 보내 **검증/admission/기본값 주입까지** 수행하되 저장만 안 함 — 진짜 리허설.

**A3.** 같은 입력으로 몇 번을 실행해도 결과 상태가 같습니다(차이만 반영). 파이프라인 재실행/재시도가 안전해지고, "이미 있으면 에러"(create) 같은 분기 처리가 필요 없습니다.

**A4.** `kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'`

**A5.** strategic merge는 `patchMergeKey`(name)를 알아 배열을 **항목 단위로 병합**하지만, JSON merge는 배열을 **통째로 교체**합니다.

**A6.** `kubectl debug -it <pod> --image=busybox --target=<container>` — ephemeral container를 대상 컨테이너의 **namespace(NET/PID)에 합류**시켜, 도구 있는 이미지로 같은 네트워크 환경을 조사합니다.

**A7.** ① `kubectl describe pod X` (이벤트/Last State/Exit Code) ② `kubectl logs X --previous` (죽기 전 로그) ③ 설정 의심 시 `kubectl get pod X -o yaml`로 env/command 확인 (또는 `debug --copy-to`로 실험).

**A8.** ① `kubectl get endpointslices` (백엔드 명단) ② Pod Ready 여부/probe ③ Service targetPort vs 앱 포트 ④ L7(Ingress/Gateway) 라우팅 규칙과 컨트롤러 로그 ⑤ LB 헬스체크 상태 (AWS 콘솔/CLI).
