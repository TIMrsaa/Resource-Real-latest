# 이론 — Events 해부, audit 로그, 신호 지도, 질문 카탈로그

> **🌱 17세 눈높이 비유: 학교의 다섯 가지 기록**
> - **로그(학생들의 일기)** = 각자가 쓴 상세한 서술 — "왜"가 담김
> - **메트릭(출석부·성적 통계)** = 숫자 집계 — 추세와 비율
> - **트레이스(수학여행 경로 기록)** = 한 여정이 어디를 거쳤나
> - **Events(교무실 방송 기록)** = 학교(플랫폼)가 공지한 사건들 — "3반 철수, 보건실로 이동됨(OOM)" — 학생 일기엔 없는 학교의 조치가 여기에. 단 ★칠판이라 1시간 뒤 지워짐 — 사진(수집)을 안 찍으면 증발
> - **audit(교무실 출입·결재 대장)** = 누가 언제 무엇을 승인/변경했나 — "누가?"의 유일한 답
> - **신호 지도** = 다섯 기록이 어디 보관되고 언제 폐기되는지의 안내판 — 조사할 일이 생기면 어느 기록부터 열지 즉답

---

## 1. K8s Events 해부

```
Event의 구조:
  involvedObject: 무엇에 관한 사건 (Pod/Deployment/Node...)
  reason: 사건 유형 코드 — ★ 조사의 열쇠
  message: 사람용 설명
  type: Normal | Warning
  count/firstTimestamp/lastTimestamp: 반복 압축 (같은 사건 N회)
  source: 누가 보고했나 (kubelet, scheduler, controller...)

실무 단골 reason 사전:
  FailedScheduling  스케줄 불가 (Insufficient cpu? taint 불일치?)
  OOMKilled(상태)+Killing  메모리 한도 초과 → 재시작 조사 1순위
  Evicted           노드 압박 축출 (DiskPressure·MemoryPressure)
  ImagePullBackOff / ErrImagePull  이미지 못 가져옴 (오타·인증·레지스트리)
  Unhealthy         Liveness/Readiness 프로브 실패
  BackOff           CrashLoop 재시도 대기
  FailedMount       볼륨 마운트 실패 (PVC·시크릿 없음)
  NodeNotReady      노드 이상

조회:
  kubectl get events --sort-by=.lastTimestamp
  kubectl get events --field-selector involvedObject.name=X,type=Warning
  kubectl describe pod X   # 해당 오브젝트의 이벤트가 하단에

★ 휘발성: 기본 TTL 1시간 (--event-ttl) — etcd 부담 때문의 설계
  → 보존하려면 수집기로 뽑아 로그 저장소로 (exporter가 Events를
    watch해 stdout/저장소로 — kubernetes-event-exporter 등, lab-01)
  → 수집된 Events는 사실상 구조화 로그 — 검색·알림 가능해짐
```

## 2. audit 로그 — "누가?"의 신호

```
무엇: API 서버가 모든 요청을 기록 — 누가(user/SA), 무엇을(verb+resource),
     언제, 어디서(IP), 결과(코드)

레벨 (audit policy로 리소스별 설정):
  None            기록 안 함
  Metadata        누가·무엇을·언제 (본문 없음) — 기본 권장
  Request         + 요청 본문 (무엇을 어떻게 바꾸려 했나)
  RequestResponse + 응답 본문 (가장 상세 = 가장 비쌈)

정책 설계의 감각 (비용 트레이드오프):
  전부 RequestResponse → 볼륨 폭발 (읽기 요청이 대부분인데 전부 기록)
  관례: 시크릿 접근·삭제·RBAC 변경은 상세하게,
       대량 읽기(get/list/watch)는 Metadata 또는 제외,
       kube-system 헬스체크 등 소음은 None

답하는 질문:
  "누가 이 Deployment를 지웠나" — delete 요청 기록
  "이 SA가 어젯밤 뭘 조회했나" — 보안 조사 (cncf 30의 탐지와 교차)
  "누가 RBAC을 바꿨나" — 권한 변경 추적 (규정 준수)

EKS에서: 컨트롤 플레인 로깅 옵션으로 audit을 CloudWatch Logs로 (13)
  자체 클러스터: --audit-policy-file·--audit-log-path (lab-01에서 kind로)
```

## 3. 신호 지도 (이 트랙의 종합)

```
신호       원산지(01)            수명(기본)         비용 축(01)      질문
──────────────────────────────────────────────────────────────────────
로그       노드 /var/log/pods    로테이션 10Mi×5     볼륨×보존        왜?
           (containerd가 기록)    (분~시 단위 휘발)   (02)            (서술)
메트릭     각 /metrics 노출       scrape 전엔 순간값   카디널리티       얼마나요?
           (cAdvisor·컴포넌트·앱)  (수집해야 이력)     (03)            추세? 비율?
트레이스   앱 SDK(계측 필수)      수집 전엔 없음      샘플링율×span    어디가?
           (04)                                     (04)            (여정)
Events    API 서버              ★ TTL 1시간        수집 시 로그화    플랫폼이 왜?
           (kubelet 등이 보고)                       (거의 무료)      (조치·사건)
audit     API 서버(정책 필요)    로그 파일/CW        레벨×범위        누가?
           (2절)                                    (폭발 주의)      (행위자)

파이프라인 요구사항으로 읽기 (06~의 명세):
  로그: 노드 파일 tail → 파싱 → 중앙 저장 (06·07 → 12·13·18)
  메트릭: scrape → TSDB (08 → 14)
  트레이스: SDK → Collector → 백엔드 (11 → 12·16·17)
  Events: watch → 로그화 (lab-01 → 로그 파이프라인 합류)
  audit: 정책 → 파일/CloudWatch (13)
```

## 4. 질문 카탈로그 → 신호 대응 (반사신경)

```
[가용성·에러]
"서비스가 죽었나요?"            메트릭(up·성공률) → 알림(10)
"5xx가 늘었습니다, 어디서?"       메트릭 라벨 분해(path·pod) → 트레이스
"Pod가 CrashLoop"            Events(describe) + logs --previous (02)
"Pod가 안 뜬다"              Events(FailedScheduling·FailedMount)

[성능]
"느려졌다"                   메트릭(p99, 03) → 트레이스(어디가, 04)
"특정 유저만 느리다"           트레이스(사례) + 로그(trace_id 필터)
"디스크 언제 차나"            메트릭(predict_linear)

[변경·원인]
"그때 무슨 변화가 있었나"      Events(배포·스케일) + GitOps 이력(cncf 14)
"누가 지웠/바꿨나"            audit
"재발 패턴인가"               보존된 Events·로그 (수집해 놨어야!)

[보안]
"이상한 접근이 있나"           audit + Falco(cncf 30)

★ 패턴: 넓은 신호(메트릭)로 시작해 좁은 신호(트레이스→로그)로,
  플랫폼 행동은 Events, 사람 행동은 audit
```

## 5. 소스/도구에서 확인하기

- Events TTL: kube-apiserver --event-ttl
- audit policy: kubernetes.io/docs/tasks/debug/debug-cluster/audit/
- kubernetes-event-exporter (Events → 로그화)
- EKS 컨트롤 플레인 로깅(13에서), cncf 30(런타임 보안과의 교차)

## 요약 카드

| 질문 | 답 |
|------|----|
| Events 구조? | involvedObject+reason+type(Normal/Warning)+count 압축 |
| 단골 reason? | FailedScheduling·OOMKilled·Evicted·ImagePullBackOff·Unhealthy·FailedMount |
| Events 함정? | TTL 1시간 휘발 — 수집기로 로그화해야 보존·검색·알림 |
| audit이 답하는 것? | "누가" — 사용자/SA의 API 행위 기록 |
| audit 레벨? | None/Metadata/Request/RequestResponse — 시크릿·삭제·RBAC은 상세, 읽기는 가볍게 |
| 지도 다섯 줄? | 로그(왜)·메트릭(얼마나)·트레이스(어디가)·Events(플랫폼이 왜)·audit(누가) |
| 조사 패턴? | 넓게(메트릭)→좁게(트레이스→로그), 플랫폼=Events, 사람=audit |
| 졸업 과제? | SIGNALS-MAP.md — 실습으로 확인한 사실로 자기 지도 그리기 |
