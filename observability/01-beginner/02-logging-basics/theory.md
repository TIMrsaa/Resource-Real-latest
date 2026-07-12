# 이론 — stdout 표준, CRI 포맷, 로테이션, kubectl logs, 예외 패턴, 구조화

> **🌱 17세 눈높이 비유: 학급 일지 제출 시스템**
> - **파일에 쓰는 앱(각자 공책에 일기)** = 전학 가면(재시작) 공책도 사라지고, 선생님(수집기)이 30명 공책 위치를 다 알아야 함
> - **stdout 표준(제출함에 내기)** = 모두 교실 앞 제출함(stdout)에 내면, 담임(containerd)이 학급 캐비닛(/var/log/pods/)에 정리
> - **CRI 포맷(접수 도장)** = 담임이 매장 마다 "받은 시각·어느 함(stdout/err)" 도장을 찍어 보관
> - **로테이션(캐비닛 용량)** = 캐비닛이 차면 오래된 것부터 폐기(10Mi×5) — 무한 보관은 없습니다, 오래 남기려면 도서관(중앙 저장, 06~)으로
> - **--previous(전학생의 마지막 일기)** = 쫓겨난(재시작) 직전 컨테이너가 남긴 마지막 기록 — 사인 규명의 열쇠
> - **구조화(양식지 vs 자유 일기)** = 자유 일기는 읽어야 알지만, 양식지(날짜/과목/점수 칸)는 통계를 낼 수 있습니다

---

## 1. stdout 표준 — 왜 (12-factor)

```
컨테이너 파일에 로그를 쓰면:
  휘발: 컨테이너 재시작 = 파일 소멸
  디스크: 로테이션 책임이 앱에 (안 하면 노드 압박)
  수집: 컨테이너마다 다른 경로 → 수집기 설정 지옥

stdout/stderr 스트림으로 쓰면:
  런타임이 수신 → 노드 표준 위치에 기록 (앱과 분리)
  로테이션은 kubelet 책임
  수집기는 노드당 한 디렉터리 (DaemonSet 하나로 전부)

★ 12-factor 원칙: "로그는 이벤트 스트림 — 앱은 저장·라우팅에 관여하지 않는다"
  → 저장·라우팅은 실행 환경(K8s + 파이프라인)의 일 (06~)
```

## 2. CRI 로그 포맷 — containerd가 쓰는 형식

```
/var/log/pods/<ns>_<pod>_<uid>/<container>/0.log 의 각 줄:

2026-07-11T12:00:00.123456789Z stdout F {"level":"info","msg":"started"}
└──────── ①시각(RFC3339Nano) ──┘ └②──┘ ③ └───────── ④원문 ─────────┘

① 시각: containerd가 수신한 시각 (앱이 쓴 시각과 다를 수 있음!)
② 스트림: stdout | stderr (에러 분리의 근거)
③ 플래그: F(Full, 완결된 줄) | P(Partial, 긴 줄이 잘림 — 이어짐)
   → 16KB 넘는 줄은 P로 쪼개짐: 수집기가 재조립해야 (06의 함정)
④ 원문: 앱이 쓴 그대로 (JSON이면 여기가 JSON)

★ 수집기(Fluent Bit)의 첫 파서가 하는 일 = 이 CRI 포맷을 벗기는 것
  그 다음에야 원문(④)의 JSON 파싱 (06에서 실습)
```

## 3. 로테이션 — kubelet의 규칙과 유실의 물리

```
kubelet 설정 (기본값):
  containerLogMaxSize: 10Mi     # 파일 하나 최대
  containerLogMaxFiles: 5       # 보관 개수 (현재 + 회전 4)
  → 컨테이너당 최대 ~50Mi, 넘치면 가장 오래된 것 삭제

의미:
  노드 로컬 로그는 "임시 버퍼"다 — 보존 보장 없음
  대량 로그 앱은 몇 분 만에 회전 → kubectl logs로 과거를 못 봄
  ★ 수집기(06)가 tail보다 느리면 회전에 밀려 유실
    (cncf 14의 백프레셔·유실의 물리와 만나는 지점)

컨테이너 재시작 시:
  이전 컨테이너의 마지막 로그 파일은 잠시 보관
  → kubectl logs --previous가 읽는 것 (그 다음 재시작이면 사라짐)
```

## 4. kubectl logs 실전 옵션

```
kubectl logs <pod>                     # 현재 컨테이너 로그
  -c <container>                       # 멀티 컨테이너 Pod에서 지정
  -f                                   # 팔로 (tail -f)
  --previous                           # ★ 직전(죽은) 컨테이너 — 재시작 원인 조사 1순위
  --since=10m / --since-time=...       # 시간 범위
  --tail=100                           # 마지막 N줄
  -l app=web --prefix                  # ★ 라벨로 여러 Pod + 어느 Pod의 줄인지 표시
  --timestamps                         # CRI 수신 시각 표시
  deploy/web                           # 워크로드 이름으로 (한 Pod 선택됨)

재시작 조사 정석 (Events와 조합 — 01):
  kubectl describe pod X       # 상태·이벤트 (OOMKilled? Error?)
  kubectl logs X --previous    # 죽기 직전 무슨 말을 남겼나
```

## 5. 예외 패턴 — 파일에만 쓰는 앱

```
① 앱 수정 (최선): 로거 설정을 stdout으로 — 대부분 설정 한 줄
② 스트리밍 사이드카 (차선):
   [앱 컨테이너] --(emptyDir 볼륨 공유)--> /logs/app.log
   [사이드카] tail -F /logs/app.log → 자기 stdout
   → 표준 경로(CRI 파일)로 복귀, 수집기는 그대로
   비용: Pod마다 컨테이너 +1 (리소스), 로그 순서·유실 엣지
③ 수집기 사이드카 (최후): Pod 안에 Fluent Bit을 넣어 파일 직접 전송
   → 표준 우회, Pod마다 수집기 (무거움) — 정말 어쩔 수 없을 때만

★ 판단: ①을 먼저 시도. 사이드카는 "레거시 임시 다리"로 한정
```

## 6. 구조화 로깅 — 로그를 데이터로

```
비구조화: "Payment failed for user 123 after 3 retries (gateway timeout)"
  사람: 읽기 좋음 / 기계: 정규식 파싱(깨지기 쉬움), 집계 불가에 가까움

구조화(JSON): {"ts":"...","level":"error","event":"payment_failed",
              "user_id":123,"retries":3,"reason":"gateway_timeout",
              "trace_id":"4bf9..."}
  기계: 필드 필터·집계·조인이 즉시 / 사람: 뷰어가 예쁘게 보여줌

설계 원칙:
  ① 이벤트는 이름으로: event="payment_failed" (문장 파싱 금지)
  ② 값은 필드로: user_id·retries·reason (문장에 섞지 않기)
  ③ 레벨 규율: error=사람이 봐야 함 / warn=이상 징후 / info=주요 사건
     debug=개발용 (프로덕션 기본 off) — 레벨 인플레이션 경계
  ④ 컨텍스트 필드 표준화: trace_id(★ 12의 상관 열쇠)·request_id·
     user_id 등 조직 공통 필드 규약 (팀마다 다르면 조인 불가)
  ⑤ 민감정보 금지: 암호·토큰·PII는 로그에 안 씁니다 (마스킹, 규정)

효과 (파이프라인에서):
  Fluent Bit(06): merge_log로 JSON을 필드로 승격
  Loki(12)·CW Logs Insights(13)·OpenSearch(18): 필드 쿼리
  → "유저별 실패 상위 10" 같은 질문이 쿼리 한 줄
```

## 7. 소스/도구에서 확인하기

- kubelet 설정: `containerLogMaxSize`·`containerLogMaxFiles` (KubeletConfiguration)
- CRI 로그 스펙: kubernetes/cri-api 로그 포맷 문서
- 12-factor logs: https://12factor.net/logs
- cncf 14(Fluentd 버퍼·유실의 물리) — 파이프라인 내부는 그쪽

## 요약 카드

| 질문 | 답 |
|------|----|
| 왜 stdout? | 휘발·로테이션·수집 문제를 플랫폼에 위임 (12-factor) |
| CRI 포맷? | 시각+스트림(stdout/err)+플래그(F/P)+원문 — P는 16KB 분할(재조립!) |
| 로테이션? | kubelet 기본 10Mi×5 — 노드 로그는 임시 버퍼, 보존은 중앙(06~) |
| --previous? | 직전 죽은 컨테이너의 마지막 로그 — 재시작 조사 1순위 |
| 여러 Pod 로그? | kubectl logs -l app=X --prefix |
| 파일만 쓰는 앱? | ①앱 수정 ②스트리밍 사이드카 ③수집기 사이드카 (순서대로) |
| 구조화 원칙? | event 이름·값은 필드·레벨 규율·공통 컨텍스트(trace_id)·PII 금지 |
| 구조화의 가치? | grep만 되는 문장 → 필터·집계·조인이 되는 데이터 |
