# Lab 04 — Alertmanager 라우팅 / 억제 / 묵음

> **🌱 Alertmanager 의 4대 핵심 기능**
> Prometheus 가 firing 알람을 전부 Alertmanager 로 보냄. AM 의 역할:
> 1. **Routing** (라우팅): 알람을 라벨 기반으로 적절한 receiver 로
> 2. **Grouping** (그룹화): 같은 라벨 set 알람을 묶어 1번에 통보 → 스팸 방지
> 3. **Inhibition** (억제): 더 심각한 알람 발생 시 관련 약한 알람 자동 숨김
> 4. **Silence** (묵음): 운영 작업 중 일시적으로 특정 알람 무시
>
> **AlertmanagerConfig CRD**: 위 설정을 K8s 객체로 관리 (Prometheus Operator).

## 1. AlertmanagerConfig CRD 적용

(실제 PagerDuty / Slack 키 없이 manifest 만 점검)

```bash
kubectl apply -f manifests/alertmanager-config.yaml
kubectl get alertmanagerconfig -n monitoring
```

> 실제 통지를 받으려면 Secret 으로 PagerDuty integration key / Slack webhook URL 생성 필요. 학습용은 webhook.site 사용.

> **🧠 AlertmanagerConfig vs 직접 ConfigMap**
> 옛날: Alertmanager 의 한 거대한 YAML config 파일.
> Operator + AlertmanagerConfig CRD: 작은 단위로 쪼개 namespace 별 관리.
>
> = 각 팀이 자기 NS 의 알람 라우팅을 자율적으로 (다른 팀 영향 X).
> Operator 가 모든 AlertmanagerConfig 를 통합해 최종 config 생성 → Alertmanager 에 적용.

## 2. Webhook receiver 임시 셋업 (학습용)

webhook.site 에서 unique URL 받아 다음 receiver 의 url 교체:
```yaml
receivers:
  - name: default-webhook
    webhookConfigs:
      - url: https://webhook.site/<unique-id>
        sendResolved: true
```

> **🧠 `sendResolved: true` 의 의미**
> AM 은 알람이 해소돼도 자동으로 통지 안 함. 명시적 `sendResolved: true` 설정 필요.
>
> 효과:
> - Firing 시: Slack/Webhook 에 "🔥 X started"
> - Resolved 시: "✅ X resolved" 추가 메시지
>
> on-call 이 "사고 끝났는지" 확인하려고 dashboard 들어가는 부담 감소.
> 단, resolve 메시지도 noise → 시급한 알람만 enable, 정보 알람은 false.

## 3. Alertmanager UI

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
```

http://localhost:9093

탭들:
- **Alerts** — 현재 firing
- **Silences** — 묵음
- **Status** — config + cluster
- **Settings** — runtime config

> **🧠 AM UI 의 디버깅 활용**
> - **Status → Cluster**: HA 모드일 때 다른 AM 인스턴스와 gossip 동기화 상태
> - **Status → Config**: 현재 적용된 라우팅/receiver/inhibit_rule 전부 — `kubectl get alertmanagerconfig` 결과의 실제 적용 형태
> - **Alerts → Filter**: 라벨로 검색 (`alertname=~"SLO.*"`)
>
> "왜 알람이 안 갔지?" → AM UI 의 Alerts 페이지에서 알람이 보이는지 확인 → 안 보이면 Prometheus → 보이는데 통지 X 면 라우팅/silence/inhibit 의심.

## 4. 묵음 (silence) — 운영 작업 중

배포 시 일시적 alert 차단:

UI 에서:
1. Silences → New silence
2. Matchers: `namespace = order`
3. Duration: 1h
4. Comment: "Deploy 진행 중"
5. Create

또는 CLI (amtool):
```bash
brew install amtool
amtool silence add 'namespace=order' --duration=1h --comment "deploy" \
  --alertmanager.url=http://localhost:9093
```

> **🧠 Silence 의 운영 패턴**
> - **계획된 작업**: 배포, DB 마이그레이션, 노드 업그레이드
> - **알려진 이슈**: 외부 서비스 outage 동안 자기 알람 mute
> - **반복 noise**: 임계값 튜닝 전 임시 mute
>
> **함정 — 영구 silence 누적**:
> "잠깐만 무음" 이 영원히 active → 진짜 사고도 무시.
> 해결: silence 에 항상 `--duration` 명시 (1h, 8h). 무한 (`-d 0`) 절대 금지.
> 정기적 silence 청소 (`amtool silence query --expired`).

## 5. 억제 (inhibition) 시연

위 config 의 inhibit_rule:
- critical 발생 시 같은 NS+service 의 warning 자동 억제

테스트:
1. critical alert 발생시킴 (예: SLO burn rate fast)
2. 동시에 같은 service 의 warning alert (예: SLO burn rate slow) 도 firing 이지만 통지 X
3. critical resolved 후 warning 통지 (만약 여전히 firing)

> **🧠 inhibition 의 가치 — "alert storm" 방지**
> 노드 NotReady 1개 발생 → 그 노드의 모든 Pod 알람 (CrashLoop, ImagePull, NetworkUnavailable...) 동시 firing.
> 결과: Slack 에 100개 알람 → on-call 이 진짜 원인 (노드) 못 봄.
>
> Inhibit 패턴:
> ```yaml
> inhibit_rules:
>   - source_matchers: [alertname=NodeNotReady]
>     target_matchers: [severity=warning]
>     equal: [node]    # 같은 node 의 warning 만 억제
> ```
> = "노드 죽으면 그 노드의 warning 들 자동 mute". critical 만 보임.

## 6. 라우팅 트리 검증

UI → Status → 현재 route 트리.

또는:
```bash
amtool config routes test severity=critical namespace=order \
  --alertmanager.url=http://localhost:9093
```

→ 어느 receiver 로 가는지.

> **🧠 라우팅 디버깅 — `amtool config routes test` 활용**
> 운영에서 "왜 이 알람이 PagerDuty 안 가지?" 가 흔한 이슈.
> 위 명령은 가상의 라벨 set 으로 라우팅 시뮬레이션 → 어느 receiver / 어떤 path 로 매칭되는지 출력.
>
> 새 라우팅 룰 추가 후 항상 시뮬레이션 → 의도한 receiver 로 가는지 검증.
>
> 실제 발사 전 `amtool` 으로 dry-run = 운영 사고 예방.

## 7. 그룹화 효과

`groupBy: [alertname, namespace]` — 같은 alert 이름 + NS 면 한 그룹 → 1번 통지에 포함.

`groupWait: 30s` — 첫 alert 후 30s 동안 같은 그룹 모음.
`groupInterval: 5m` — 그룹 안 새 alert 추가 시 5m 마다 통지.
`repeatInterval: 4h` — 같은 alert 가 계속 firing 이면 4h 마다 재통지.

> **🧠 4개 timing 파라미터의 직관**
> ```
>   t=0s:   Alert A firing
>             ↓ groupWait=30s (같이 묶을 후속 대기)
>   t=30s:  알람 묶음 1번째 통보 [A, B, C 모두 포함]
>             ↓ groupInterval=5m (새 알람 추가 시 묶어서)
>   t=5m30s: 그룹에 D 가 추가됐으면 [D] 통보
>             ↓ repeatInterval=4h (해소 안 되면 재공지)
>   t=4h30s: 여전히 firing 이면 [A, B, C, D 다시] 통보
> ```
>
> **권장값**:
> - **groupWait**: 10~30s (너무 길면 첫 알람 지연)
> - **groupInterval**: 5~10m (스팸 방지)
> - **repeatInterval**: 1h ~ 4h (잊지 않게)

## 8. Runbook 패턴 검증

annotation 의 `runbook_url` 이 통지 메시지에 포함되는지 webhook 응답에서 확인:
```json
{
  "alerts": [{
    "labels": {"alertname": "OrderServiceSLOBurnRateFast", "severity": "critical"},
    "annotations": {
      "summary": "...",
      "runbook_url": "https://wiki.example.com/runbooks/slo-burn"
    }
  }]
}
```

→ Slack notification template 에 link 포함하면 on-call 이 즉시 절차 확인.

> **🧠 Runbook 의 가치 — 새벽 3시의 on-call**
> 알람 받자마자 "뭘 봐야 하나?" 모르는 채 헤매면 MTTR (Mean Time To Resolve) 폭증.
> Runbook = "이 알람 받으면 따라야 할 절차" 문서.
>
> 좋은 runbook 의 구조:
> 1. **증상**: 이 알람이 정확히 무엇을 의미
> 2. **영향 범위**: 누가 영향받나 (사용자, 다른 서비스)
> 3. **즉시 조치**: 5분 안에 할 수 있는 mitigation (rollback, scale up)
> 4. **진단 명령**: 정확한 kubectl/grafana 쿼리 (복붙 가능)
> 5. **에스컬레이션**: 30분 안에 해결 안 되면 누구에게
>
> 모든 알람에 runbook URL 부착이 SRE 성숙도 지표.

## 9. 정리

```bash
kubectl delete -f manifests/alertmanager-config.yaml
```

## 학습 확인

1. group_wait 와 group_interval 의 차이는?
2. inhibition vs silence 의 차이는?
3. continue: true 가 있는 route 의 효과는?

> **힌트**:
> 1. group_wait = 첫 알람 후 같은 그룹 후속 대기 (한 번에 모아 보내기). group_interval = 그 그룹 내 후속 알람 추가 시 다시 통지하는 최소 간격.
> 2. inhibition = 라벨 매칭으로 자동 억제 (rule 기반, 영구), silence = 사람이 시간 한정으로 mute (수동, 만료 시 해제). 큰 사고 시 inhibit, 운영 작업 중 silence.
> 3. 매칭 후에도 다음 형제 route 도 평가 → 같은 알람이 여러 receiver 로. 기본은 첫 매칭에서 멈춤.

다음: [quiz.md](./quiz.md)
