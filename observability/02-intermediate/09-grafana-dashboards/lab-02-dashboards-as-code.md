# Lab 02 — 대시보드 as code: 프로비저닝과 GitOps

> lab-01의 JSON을 ConfigMap 프로비저닝으로 전환해 "클릭 대시보드"의 운명(유실·불일치)에서 벗어납니다. sidecar 자동 로드, uid 안정성, 그리고 UI 수정→Git 반영의 운영 루프를 만듭니다.

## 1. 클릭 대시보드의 운명 체험

```bash
# lab-01에서 Import로 만든 대시보드는 Grafana 내부 DB(SQLite)에만 있습니다
kubectl -n monitoring get pod -l app.kubernetes.io/name=grafana
kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana
kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=180s

kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
sleep 3
# 브라우저 확인: Import한 대시보드가... 있습니다? 없습니다?
# (kube-prometheus-stack 기본은 영속볼륨 없음 — Pod 재생성이면 내부 DB 초기화
#  → Import 대시보드 소멸! 내장 대시보드는 남아있습니다 — 왜? 그들은 CM 프로비저닝이라)
```

**관찰** — 내장 대시보드(Node Exporter 등)는 살아남고 Import한 것만 죽었습니다. 차이가 바로 **프로비저닝**(ConfigMap → sidecar) 여부입니다. 내장 대시보드의 생존 방식을 우리 것에도 적용합니다.

## 2. ConfigMap 프로비저닝 — sidecar의 계약

```bash
# lab-01의 JSON을 ConfigMap으로 (라벨이 계약!)
kubectl -n monitoring create configmap red-dashboard \
  --from-file=red-dashboard.json=/tmp/red-dashboard.json
kubectl -n monitoring label configmap red-dashboard grafana_dashboard="1"

kubectl -n monitoring create configmap overview-dashboard \
  --from-file=overview-dashboard.json=/tmp/overview-dashboard.json
kubectl -n monitoring label configmap overview-dashboard grafana_dashboard="1"

# sidecar가 라벨 달린 CM을 감지해 자동 로드 (수십 초 내)
sleep 45
# 브라우저: Dashboards에 "Service RED"·"L1 Overview" 재등장!
```

```bash
# 이제 Grafana Pod를 다시 죽여도:
kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana
kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=180s
sleep 45
# 대시보드 생존! — 진실이 CM(→Git)에 있으므로 Pod는 소모품
```

**계약 정리** — `grafana_dashboard: "1"` 라벨의 CM에 JSON을 넣으면 sidecar가 로드합니다. CM은 kubectl이 아니라 **Git 저장소 + GitOps**(cncf 14·15)로 관리하는 것이 완성형:

```
repo/dashboards/red-dashboard.json  →  (CI 또는 kustomize configMapGenerator)
  →  ConfigMap  →  ArgoCD/Flux sync  →  sidecar 로드
변경 = PR — 리뷰·이력·롤백이 공짜로
```

## 3. 운영 루프 — UI는 초안, Git이 진실

```
실무 흐름:
  ① 조사 중 UI에서 패널 추가·수정 (빠른 실험 — 여기까진 자유)
  ② 쓸 만하면: 대시보드 Settings → JSON Model → 복사
  ③ Git의 json 파일에 반영 → PR → 머지 → GitOps 반영
  ④ UI의 임시 수정은 다음 sync/재시작에 원복돼도 무방 (진실은 Git)

규율:
  uid 고정 — 링크(L1→L2 드릴다운·알림 착지)가 uid 기반이라
    uid가 바뀌면 조용히 끊깁니다 (조용한 실패 계열!)
  datasource는 변수/기본값으로 — 환경(스테이징/프로덕션) 이식성
  대시보드 리뷰 관점: "새 패널은 어떤 질문의 답인가" (그래프 벽 방지)
```

## 4. 안티패턴 점검 실습

kube-prometheus-stack 내장 대시보드 하나(예: Kubernetes / Compute Resources / Namespace)를 열고 theory 6절의 안티패턴 체크리스트로 리뷰하세요:

```
□ 패널마다 답하는 질문이 있는가요?
□ 평균만 있는 지연 패널은 없는가요?
□ counter 원값 플롯은 없는가요?
□ 색·임계·단위가 맥락을 주는가요?
□ 어디로 드릴다운하나요? (링크)
→ 내장 대시보드도 완벽하지 않습니다 — 좋은 예와 아쉬운 예를 구분하는 눈이
  "우리 질문에 맞게 다듬는" 능력입니다 (커뮤니티 대시보드를 쓸 때의 태도)
```

## 5. SIGNALS-MAP 갱신 (과제)

```
시각화 항목 추가:
  대시보드: L1 Overview → L2 Service RED (드릴다운·배포 마커)
  관리: ConfigMap 프로비저닝 (grafana_dashboard=1) — Git이 진실
  다음: 10에서 알림이 L1/L2로 착지, 12에서 로그·트레이스 링크 합류
```

## 6. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name grafana
rm -f /tmp/red-dashboard.json /tmp/overview-dashboard.json
```

## 정리

- 클릭(Import) 대시보드는 Pod와 함께 죽었습니다 — 내장이 살아남은 이유 = CM 프로비저닝
- 계약: `grafana_dashboard: "1"` 라벨 CM → sidecar 자동 로드 — Git+GitOps가 완성형
- 운영 루프: UI는 초안(실험) → JSON export → Git PR — 진실은 Git
- uid 고정(링크 안정)·datasource 변수화(환경 이식) — 조용한 끊김 방지
- **★ 대시보드도 코드입니다 — 리뷰 질문은 "이 패널은 어떤 질문의 답인가"**
