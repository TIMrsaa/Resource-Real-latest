# 이론 — 진단 체계와 장애 10선 지도

> **🌱 17세 눈높이 비유: 응급실 분류 프로토콜**
> 환자(장애)가 실려오면 병명을 찍는 게 아니라 **분류부터** 합니다:
> "입원 수속이 안 됨"(Pending — 스케줄 문제) / "수속은 됐는데 깨어나질 못함"(기동 실패) /
> "깨어났는데 말이 안 통함"(연결 문제). 계통이 갈리면 검사(명령)는 몇 개로 좁혀집니다.
> 베테랑의 비밀은 암기량이 아니라 **분류가 빠른 것**입니다.

---

## 1. 대분류 — Pod의 일생 어디서 멈췄나

```
Pod 단계        멈춤의 의미                  1순위 명령
─────────────────────────────────────────────────────────
Pending         스케줄 불가/볼륨/이미지 전    describe pod (Events!)
ContainerCreating  볼륨 마운트/CNI/이미지 풀   describe pod + 노드 이벤트
CrashLoopBackOff   떴다가 죽기를 반복         logs --previous   ★
ImagePullBackOff   이미지를 못 가져옴         describe (정확한 사유 문장)
Running인데 이상   앱/연결/프로브 문제         logs + endpoints + 프로브 설정
OOMKilled       메모리 limit 초과           describe (lastState.reason)
Evicted         노드가 쫓아냄               describe (message에 사유)
```

**제1원칙: `kubectl describe`의 Events가 전체 진단의 7할입니다.** K8s는 거의 모든 결정(거부/실패/재시도)을 이벤트로 남깁니다 — 추측 전에 읽어라.

## 2. 장애 10선 지도

### 워크로드 5선 (lab-01)

| # | 증상 | 전형적 원인 | 결정적 단서 |
|---|------|------------|------------|
| 1 | CrashLoopBackOff | 앱 시작 실패(설정/의존성), 잘못된 커맨드 | `logs --previous`의 마지막 줄 |
| 2 | ImagePullBackOff | 오타/없는 태그/프라이빗 권한 | describe의 "manifest unknown"/"unauthorized" |
| 3 | OOMKilled (137) | limit < 실사용, 메모리 누수 | `lastState.terminated.reason: OOMKilled` |
| 4 | Pending | 리소스 부족/taint/quota/PVC | describe의 "0/N nodes available: ..." 집계 |
| 5 | Running인데 503 | readiness 실패 → endpoints 0 | `kubectl get endpoints` 가 비어 있음 |

### 연결/플랫폼 5선 (lab-02)

| # | 증상 | 전형적 원인 | 결정적 단서 |
|---|------|------------|------------|
| 6 | 이름 해석 실패 | CoreDNS 다운/과부하, ndots(모듈 16) | `nslookup kubernetes.default` 실패 |
| 7 | Service 연결 불가 | **셀렉터-라벨 불일치**, port 오기재 | endpoints 없음 + 라벨 대조 |
| 8 | 특정 구간만 차단 | NetworkPolicy (모듈 15) | "IP로도 안 됨" + netpol 목록 |
| 9 | PVC Pending | StorageClass 없음/오타, 용량 | describe pvc의 "no storage class" |
| 10 | 노드 NotReady | kubelet/디스크/네트워크 | describe node의 Conditions |

## 3. 두 개의 황금 명령

### `kubectl logs --previous` — 죽은 자의 유언

CrashLoop 중인 컨테이너의 `logs`는 **방금 재시작한(아직 안 죽은) 프로세스**의 로그라 단서가 없을 수 있습니다. 죽은 직전 컨테이너의 로그가 `--previous`입니다. CrashLoop 진단에서 가장 많이 까먹는 한 방.

### `kubectl get endpoints <svc>` — 연결 문제의 분기점

```
endpoints가 비어 있습니다  → Service 쪽 문제: 셀렉터 불일치 or 전원 NotReady(readiness)
endpoints가 차 있습니다    → 경로 문제: NetworkPolicy, 포트, DNS, 클라이언트
```
연결 장애에서 이 한 명령이 수사 방향을 절반으로 줄입니다 (모듈 05의 그 원리).

## 4. 증상→의심 진단 카드 (이 모듈의 산출물)

```markdown
# K8s 진단 카드 — 증상부터 역방향
| 증상 | 1순위 의심 | 확인 한 방 |
|------|-----------|-----------|
| CrashLoop | 앱 시작 실패 | logs --previous | tail -5 |
| Pending | 자원/taint/quota | describe pod | grep -A5 Events |
| 503/연결 거부 | endpoints 0 | get endpoints <svc> |
| 이름만 안 풀림 | DNS/ndots | exec ... nslookup <name> |
| IP로도 안 됨 | NetworkPolicy/포트 | get netpol -A + 포트 대조 |
| 간헐 타임아웃 | conntrack/리소스 스로틀 | 노드 메트릭 (모듈 28/13) |
| 노드째 이상 | kubelet/디스크 | describe node | grep -A8 Conditions |
| 다 느림 | control plane/expensive LIST | APF 메트릭 (모듈 37) |
```

## 5. 재발 방지가 진짜 종결

장애 대응의 마지막 질문은 "고쳤나요?"가 아니라 **"같은 장애가 다시 오면 시스템이 먼저 아는가요?"**:

- CrashLoop/OOM → requests/limits 재산정 + 알림
- 503 → readiness probe 정비(모듈 14) + PDB(19)
- 설정 실수류 → admission 정책으로 차단(23), CI에서 검증
- "몰랐다"류 → 그 메트릭/이벤트에 알림 추가

postmortem(사후 분석)의 본질: 사람을 탓하면 배움이 끝나고, **시스템을 고치면 장애가 자산이 됩니다.**

## 6. 소스/도구에서 확인하기

- 공식 디버깅 가이드: https://kubernetes.io/docs/tasks/debug/
- Pod 디버깅 흐름도: https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/
- `kubectl debug`(임시 컨테이너/노드 디버깅): 모듈 29에서 익힌 그 도구가 여기서 주력

## 요약 카드

| 질문 | 답 |
|------|----|
| 진단의 첫 명령? | describe (Events가 7할) |
| CrashLoop의 황금 명령? | logs **--previous** |
| 연결 장애의 분기점? | get endpoints — 비었나 찼나 |
| "이름만 안 됨"의 의심? | DNS (nslookup 한 방) |
| "IP로도 안 됨"의 의심? | NetworkPolicy/포트 |
| 대응의 종결 조건? | 재발 시 시스템이 먼저 알게 만들기 |
