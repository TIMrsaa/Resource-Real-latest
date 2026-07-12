# 학습 가이드 — 무엇이 남고 무엇이 넘어가나

## 08의 벽과 세 갈래 답

```
08의 결론: 단일 Prometheus의 벽 — 장기 보존·수평 확장·HA
세 갈래:
  ① 자체 확장: Thanos/Mimir (cncf 45, 24모듈) — 오브젝트 스토리지 + 운영
  ② 관리형: AMP — 같은 프로토콜, AWS가 저장 운영
  ③ 그냥 삽니다: 상용 SaaS
→ 이 모듈은 ②를 짓고, 24에서 ①과 최종 비교
```

## 핵심 그림 — 절단선이 어디인가

```
[클러스터 안 — 그대로 남는 것 (08의 전부)]
  ServiceMonitor 셀프서비스, relabeling 수문, scrape
  Prometheus (★ 에이전트 모드 가능 — 아래)
      │ remote_write (+ SigV4 서명)
      ▼
[AWS — 넘어가는 것]
  AMP 워크스페이스: TSDB 저장·확장·HA
  + 관리형 규칙(recording/alerting)·관리형 Alertmanager
      ▲
  쿼리: PromQL API (Grafana/AMG가 데이터소스로)

절단선 = "수집과 저장 사이"
  수집 체계(팀 셀프서비스·수문)는 우리 것 — 조직의 규약이므로
  저장(디스크·확장·백업)은 AWS 것 — 물리 운영이므로
→ cncf의 "시스템 vs 오케스트레이터" 구분과 닮은 절단 감각
```

## 에이전트 모드 — 저장 안 하는 Prometheus

```
일반 모드: scrape → 로컬 TSDB 저장 + remote_write (이중 저장)
에이전트 모드 (--enable-feature=agent):
  scrape → remote_write만 (로컬 쿼리·알림 평가 없음, WAL만)
  → 리소스 대폭 절감 — "수집기"로 순수화
트레이드오프:
  로컬 쿼리 불가 → 모든 쿼리가 AMP로 (네트워크 의존↑)
  알림 평가도 AMP 관리형 규칙으로 이관해야
→ 선택: 로컬 조회·알림의 자율성 vs 리소스 절감
  (하이브리드: 짧은 로컬 보존 + remote_write도 흔한 실전)
```

## 인증 — IRSA가 여기서 재등장

AMP의 remote_write는 SigV4 서명이 필요합니다. Pod가 AWS API에 서명하려면? — eks 파트에서 배운 **IRSA**(IAM Roles for Service Accounts)입니다:

```
ServiceAccount에 IAM 롤 연결 → Prometheus Pod가 그 롤로 SigV4 서명
→ 시크릿 없이 (키 배포 없이) AWS 인증 — eks 파트 지식의 재사용
→ 16(ADOT)·15(AMG)·18에서도 같은 패턴 반복 — AWS 관측 스택의 공통 관문
```

## 요금 모델 — 카디널리티가 다시 (이번엔 샘플 수로)

```
AMP 과금: 수집 샘플 수(억 단위당) + 저장 + 쿼리 샘플 처리
  샘플 수 = 활성 시계열 × scrape 빈도
  → 03·08의 카디널리티 규율이 여기서도 요금
  → 13의 CW 커스텀 메트릭보다 고카디널리티에 유리한 구조지만 무한은 아님
  → relabeling 수문(08)이 AMP 요금의 수문이기도
```

## 판단 미리보기 (lab-02에서 정리)

```
자체 Prometheus(로컬만): 소규모·짧은 보존이면 충분 — 가장 단순
AMP: 장기·확장 필요 + 운영 최소화 + AWS 생태(AMG·IAM) → 관리형 우선(09)
Thanos/Mimir(24): 멀티클라우드·초대규모·비용 최적화 여지 + 운영 역량
→ "관리형 우선, 자체는 조건"의 관측판
```
