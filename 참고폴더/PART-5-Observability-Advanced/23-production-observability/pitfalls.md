# 흔한 함정 5선 — 23. Production Observability

## 1. remote_write 큐 적체로 메모리 폭증

**증상**: Prometheus 메모리 사용 급증, 메트릭 누락.

**원인**: remote_write 대상이 느려서 큐 적체.

**진단**:
```promql
prometheus_remote_storage_samples_pending
prometheus_remote_storage_samples_dropped_total
```

**해결**:
```yaml
remoteWrite:
  - url: ...
    queueConfig:
      maxShards: 200
      capacity: 2500
      maxSamplesPerSend: 1000
```

shards 늘림 + 대상의 느림 원인 해결.

---

## 2. SLO alert 가 너무 자주 fire (false positive)

**증상**: alert fatigue. 진짜 문제 무감각.

**원인**: 단일 임계 (`error_rate > 1% for 5m`) — 일시적 spike 도 alert.

**해결**: multi-burn-rate. 또는 더 긴 `for` (15m, 30m).

---

## 3. inhibition 잘못 설정 → 진짜 alert 도 막음

**증상**: critical 발생했는데 통지 안 옴.

**원인 후보**:
- 다른 critical 이 firing 중 (자기 자신을 source 로)
- 잘못된 equal labels — 의도치 않게 매칭

**진단**:
```bash
amtool config show --alertmanager.url=http://localhost:9093
```

inhibit_rules 검토.

---

## 4. AMP retention 끝난 데이터 갑자기 사라짐

**증상**: 1년 전 데이터 보려고 하니 비어있음.

**원인**: AMP 의 retention 은 150 일 (기본) 또는 15개월. 이후 자동 삭제.

**해결**:
- 정책 조정 (AMP 의 retention 설정)
- 더 긴 보관이 필요하면 Thanos S3 (무한)

---

## 5. Alert annotation 의 template 변수가 비어 출력

**증상**: 통지 메시지가 `service: <no value>` 형태.

**원인**: `{{ $labels.service }}` 인데 실제 alert 에 그 라벨 없음 (recording rule 에서 제거됐거나).

**해결**:
- recording rule 의 `sum by (...)` 에 필요한 라벨 포함
- annotation 에서 `{{ $labels.service | default "unknown" }}` (Go template default)

---

## 부록 — Production Observability 체크리스트

- [ ] Prometheus replicas: 2+ 또는 remote_write 로 HA
- [ ] 장기 저장소 (Thanos / AMP) 연결
- [ ] retention 적정 (12h 로컬 + 무한 외부)
- [ ] SLO 정의 + multi-burn-rate alert
- [ ] Alert routing (severity 별 다른 channel)
- [ ] inhibition rule 로 noise 줄임
- [ ] Runbook URL 모든 alert 에 포함
- [ ] silence 권한 분리 (모두에게 silence 권한 X)
- [ ] Watchdog alert 로 모니터링 자체 점검
- [ ] 대시보드 provisioning (코드화)
