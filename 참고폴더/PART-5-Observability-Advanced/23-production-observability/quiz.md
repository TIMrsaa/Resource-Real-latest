# 퀴즈 — 23. Production Observability

### Q1. Prometheus HA 의 두 가지 접근은?

---

### Q2. Thanos / Mimir / AMP / VictoriaMetrics 중 운영 부담이 가장 낮은 것은?

---

### Q3. SLO 99.9% (30일) 의 error budget 시간 (분 단위) 는?

---

### Q4. multi-burn-rate alert 가 single-rate 보다 좋은 이유 두 가지를 적으세요.

---

### Q5. AlertmanagerConfig 의 `continue: true` 의 효과는?

---

### Q6. inhibition 과 silence 의 차이는?

---

### Q7. groupWait 와 groupInterval 의 차이는?

---

### Q8. AMP remote_write 가 sigv4 인증을 쓰는 이유는?

---

### Q9. Watchdog alert 가 항상 firing 인 이유는?

---

### Q10. (실습 검증) 현재 Alertmanager 로 들어가는 모든 active alert 를 보는 명령은?

---

## 정답

<details>

**Q1**: 다중 replicas (둘 다 scrape) + remote_write (중앙 storage 가 HA 책임) — 두 접근.
**Q2**: AMP (AWS 가 운영, 사용자 부담 0)
**Q3**: 30일 × 24h × 60min × 0.001 = 43.2 분
**Q4**: 빠른 사고 (1분 내 100% down) 도 알림. 느린 burn (작은 에러 누적) 도 알림. 즉, false negative + false positive 동시 줄임.
**Q5**: 그 route 가 매칭되어도 다음 route 도 평가. 한 alert 가 여러 receiver 로 동시 통지 가능.
**Q6**: inhibition: 한 alert 가 firing 이면 다른 alert 통지 차단 (자동, 규칙 기반). silence: 사람이 시작/종료 시각 + matchers 로 일시 차단 (수동).
**Q7**: groupWait: 첫 alert 후 같은 그룹 더 모으는 시간 (30s). groupInterval: 그룹 안 새 alert 추가 시 통지 빈도 (5m).
**Q8**: AMP 는 IAM 으로 인증. sigv4 가 AWS 의 HTTP 요청 서명 표준. 별도 자격증명 분배 불필요.
**Q9**: 모니터링 자체가 동작하는지 검증. Watchdog 이 firing 인 한 Prometheus + Alertmanager 정상.
**Q10**: `curl -s http://localhost:9093/api/v2/alerts | jq '.[].labels'`

</details>

다음: [pitfalls.md](./pitfalls.md)
