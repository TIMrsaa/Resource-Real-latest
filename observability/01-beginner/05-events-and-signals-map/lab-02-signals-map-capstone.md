# Lab 02 — 질문 카탈로그 훈련과 SIGNALS-MAP.md (졸업 과제)

> beginner 트랙의 마무리. 실무 질문 15개를 신호 지도에 대응시키는 훈련을 하고(답을 보기 전에 스스로!), 자기 손으로 SIGNALS-MAP.md를 작성합니다. 이 지도는 06~24를 지나며 계속 갱신되는 living document입니다.

## 1. 질문 카탈로그 훈련

각 질문에 대해 ① 첫 신호 ② 구체 명령/방법 ③ 그 다음 단계를 적어라. 그 다음 접힌 답과 비교.

**Q1. "api 서비스가 느려졌대요"**
<details><summary>답</summary>

① 메트릭 — p99 지연(전체 평균 금지, 03) ② (파이프라인 후) histogram_quantile, 지금은 kubectl top으로 리소스 배제 ③ 라벨 분해(path·pod별)로 좁히고 → 트레이스로 구간 특정
</details>

**Q2. "Pod가 자꾸 재시작해요"**
<details><summary>답</summary>

① Events+상태 ② `kubectl describe pod`(OOMKilled? Unhealthy?) + `kubectl logs --previous`(유언) ③ OOM이면 limits·메모리 추세(메트릭), 프로브면 앱 상태·설정
</details>

**Q3. "어제 새벽에 서비스가 5분 죽었었대요. 왜죠?"**
<details><summary>답</summary>

① 보존된 신호만 가능! — Events는 이미 휘발(1h), 로그도 로테이션 가능성 ② 수집해 둔 Events 로그(lab-01의 exporter)·중앙 로그·메트릭 이력에서 그 시각 조회 ③ **수집을 안 해뒀다면 조사 불가 — 이 질문이 파이프라인(06~)의 존재 이유**
</details>

**Q4. "누가 프로덕션 ConfigMap을 바꿨죠?"**
<details><summary>답</summary>

① audit ② audit 로그에서 verb=patch/update + objectRef=configmaps 검색 ③ GitOps(cncf 14)라면 Git 이력과 대조 — Git에 없는 변경 = 수동 변경(드리프트)
</details>

**Q5. "결제 요청이 어디서 막히는지 모르겠어요 (서비스 5개 경유)"**
<details><summary>답</summary>

① 트레이스 (이 질문의 유일한 정답, 04) ② trace 간트에서 최장 span ③ 그 서비스의 로그(trace_id로)·메트릭으로 원인
</details>

**Q6. "노드 디스크가 언제 차나요?"**
<details><summary>답</summary>

① 메트릭 ② node-exporter의 filesystem 메트릭 + predict_linear(추세 외삽) ③ 알림 규칙(10)로 "6시간 내 고갈 예측 시" 사전 경보
</details>

**Q7. "이 SA 토큰이 유출된 것 같아요. 뭘 했는지 알 수 있나요?"**
<details><summary>답</summary>

① audit ② user=SA로 필터해 행위 타임라인 ③ 이상 행위는 Falco(cncf 30)류 런타임 탐지와 교차 — 관측과 보안의 접점
</details>

**Q8. "배포 후 에러율이 뛰었어요. 새 버전 때문인가요?"**
<details><summary>답</summary>

① 메트릭 라벨 분해 ② 에러율을 version 라벨로 분리(카나리 비교, cncf 16의 롤아웃 분석) ③ 새 버전만 높으면 롤백 + 그 버전 로그·트레이스
</details>

**Q9. "특정 고객사만 타임아웃이래요"**
<details><summary>답</summary>

① 로그(고객 식별은 unbounded — 메트릭 라벨 금지!, 03) ② 구조화 로그에서 tenant 필드 필터 ③ 해당 요청 trace_id로 트레이스 점프 — 신호 분담의 전형
</details>

**Q10. "kubectl top이랑 Grafana 숫자가 달라요. 버그인가요?"**
<details><summary>답</summary>

버그 아님(03 lab-02) — 다른 파이프라인(metrics-server vs Prometheus)·창·시점. 정밀 비교는 같은 창으로.
</details>

**Q11. "HPA가 <unknown>이래요"**
<details><summary>답</summary>

① 리소스 메트릭 파이프라인 점검 ② metrics-server 상태·Metrics API(apiservices) ③ 이건 관측 장애가 아니라 **플랫폼 반사신경 장애** — 우선순위 높음(03)
</details>

**Q12. "로그가 안 보여요 (kubectl logs가 비어요)"**
<details><summary>답</summary>

① 로그 경로 지식(02) ② 앱이 stdout에 쓰나요?(파일에 쓰는 레거시?) 로테이션에 밀렸나요?(대량 로그) 컨테이너가 재시작했나요?(--previous) ③ 파일 쓰는 앱이면 사이드카 패턴(02)
</details>

**Q13. "이미지 풀이 왜 느리죠/실패하죠?"**
<details><summary>답</summary>

① Events ② ImagePullBackOff·ErrImagePull의 message(오타? 인증? 레지스트리?) ③ 대규모 풀 병목이면 cncf 35(P2P)의 영역
</details>

**Q14. "메모리 누수가 의심돼요"**
<details><summary>답</summary>

① 메트릭 추세(container_memory_working_set 우상향?) ② 재시작(OOMKilled) 이력과 대조 ③ 확정·원인은 프로파일링(20) — 어느 코드가 잡고 있나
</details>

**Q15. "지금 우리 관측 시스템 자체는 건강한가요?"**
<details><summary>답</summary>

메타 질문(22의 관측의 관측) — 수집기 지연·드롭, Prometheus 시계열 수, 저장소 용량을 **관측 시스템의 메트릭**으로. "관측이 죽으면 모든 장애가 안 보인다"(03 사고)
</details>

**채점 기준** — 정답 자체보다 **패턴**: 넓은 신호(메트릭)에서 좁은 신호(트레이스→로그)로, 플랫폼 행동은 Events, 사람 행동은 audit, unbounded 식별자는 로그로. 이 반사가 자리 잡았으면 통과입니다.

## 2. 졸업 과제 — SIGNALS-MAP.md 작성

자기 klaster(kind)에서 **직접 확인한 사실**로 채워라. 템플릿:

```markdown
# SIGNALS-MAP — <이름>의 신호 지도 (vN, 날짜)

## 1. 신호 인벤토리
| 신호 | 원산지(확인한 경로) | 수명(확인 방법) | 비용 축 | 첫 질문 |
|------|--------------------| ---------------|---------|---------|
| 로그 | /var/log/pods/... (docker exec로 확인) | 10Mi×5 (flooder 실험) | 볼륨×보존 | 왜? |
| ...  | | | | |

## 2. 수집·보존 현황 (living — 파이프라인 지을 때마다 갱신)
| 신호 | 수집기 | 저장소 | 보존 | 상태 |
|------|--------|--------|------|------|
| 로그 | (없음→06에서 Fluent Bit) | - | 노드 로테이션뿐 | ❌ |
| Events | event-exporter(lab-01) | stdout뿐 | - | 🔶 부분 |
| ...  | | | | |

## 3. 나의 질문 카탈로그 (조사 반사)
- "재시작 왜?" → describe(Events) + logs --previous
- (훈련 1의 15문항 중 자기 언어로 10개 이상)

## 4. 갱신 로그
- v1 (05 수료): 최초 작성 — 수집 전무, 원산지만 파악
- (06 후) v2: 로그 파이프라인 추가...
```

**작성 규칙**
- 각 칸은 "실습에서 어떻게 확인했는지"를 함께 (경로·명령·실험)
- 2절(수집·보존)은 지금 대부분 ❌인 것이 정상 — **그 ❌들이 intermediate의 할 일 목록**입니다
- 06·08·11·13… 각 모듈을 마칠 때마다 2절을 갱신하고 갱신 로그에 한 줄

## 3. 정리

```bash
kind delete cluster --name signals
rm -rf /tmp/audit
```

## 정리

- 15문항 반사 훈련: 넓게(메트릭)→좁게(트레이스→로그), 플랫폼=Events, 사람=audit
- Q3("어제 새벽")의 답이 핵심 — **수집해 두지 않은 신호로는 과거를 조사할 수 없다** = 파이프라인의 존재 이유
- SIGNALS-MAP.md의 ❌들 = intermediate(06~12)의 요구사항 명세
- **★ beginner 수료: 신호의 원리와 지도를 갖췄습니다 — 이제 파이프라인을 짓습니다**
