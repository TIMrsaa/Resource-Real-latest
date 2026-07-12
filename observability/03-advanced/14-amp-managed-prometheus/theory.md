# 이론 — remote_write, 에이전트 모드, IRSA 인증, AMP 규칙, 요금, 판단

> **🌱 17세 눈높이 비유: 동네 서점과 중앙 도서관의 분업**
> - **자체 Prometheus(동네 서점이 전부 소장)** = 우리 가게 책장에 다 꽂음 — 공간(디스크)이 차면 한계, 불나면(장애) 끝
> - **AMP(중앙 도서관에 납본)** = 우리는 책을 만들고(수집) 도서관에 보내기만(remote_write) — 보관·확장·화재 대비는 도서관이
> - **에이전트 모드** = 서점에서 판매대(로컬 조회)를 없애고 제작·납본만 — 자리는 아끼지만 손님은 도서관까지 가야
> - **SigV4/IRSA(납본 허가증)** = 도서관은 허가증 있는 서점만 받음 — 직원증(ServiceAccount)에 허가(IAM 롤)를 연동
> - **요금(납본 권수 과금)** = 보내는 책 수만큼 — 잡지 나부랭이(고카디널리티 소음)까지 보내면 요금 폭탄 → 보내기 전 선별(relabeling)
> - **핵심** = 만드는 규칙(수집 체계)은 서점의 것, 보관의 물리는 도서관의 것 — 절단선이 설계입니다

---

## 1. remote_write — 프로토콜이 만드는 자유

```
remote_write: Prometheus가 수집한 샘플을 원격 저장소로 스트리밍하는
  표준 프로토콜 — 받는 쪽이 AMP든 Thanos든 Mimir든 동일
  → 저장소 교체가 remote_write 설정 교체 (lock-in 완화 — 표준의 가치, cncf 06)

동작:
  scrape → WAL → remote_write 큐 → (배치·재시도) → 원격
  큐 파라미터(capacity·max_shards): 폭주·원격 장애 시 완충
  원격 다운 시: 큐·WAL이 버팀 (한도 초과 시 드롭 — 06의 버퍼 물리 동일!)
  → remote_write 지연·드롭 메트릭 감시 (prometheus_remote_storage_*)
```

## 2. 에이전트 모드

```
일반: scrape → 로컬 TSDB(쿼리·룰 평가) + remote_write
에이전트: scrape → WAL → remote_write만
  로컬 쿼리 API 없음 / 룰 평가 없음 / 리소스 최소

판단:
  에이전트: "순수 수집기" — 쿼리·알림 전부 AMP 쪽에서 (AMG·관리형 룰)
  하이브리드(흔한 실전): 짧은 로컬 보존(수 시간~수일) + remote_write
    → 로컬 대시보드·알림의 자율성 유지 + 장기는 AMP
  → 네트워크 단절 시 로컬 알림이 살아있는가가 갈림길 (가용성 설계)
```

## 3. IRSA — remote_write의 관문 (eks 파트 재사용)

```
AMP API는 SigV4 서명 요구 → Pod가 IAM 자격이 필요
IRSA 흐름:
  ① IAM 롤 (AmazonPrometheusRemoteWriteAccess 정책)
  ② 롤의 신뢰 정책: EKS OIDC 공급자 + 특정 SA 조건
  ③ ServiceAccount 어노테이션: eks.amazonaws.com/role-arn
  ④ Prometheus 스펙에서 그 SA 사용 + remoteWrite.sigv4.region 설정
→ 키 없이 Pod가 서명 — eks 파트의 IRSA가 관측 스택의 공통 관문
  (16 ADOT·15 AMG 데이터소스·18에서도 같은 패턴)
```

## 4. kube-prometheus-stack에서의 연결 (08 체계 유지)

```yaml
prometheus:
  prometheusSpec:
    serviceAccountName: amp-irsa            # IRSA SA
    remoteWrite:
      - url: https://aps-workspaces.<region>.amazonaws.com/workspaces/<ws-id>/api/v1/remote_write
        sigv4: { region: <region> }
        queueConfig: { maxSamplesPerSend: 1000, capacity: 2500 }
    # retention: 2h (하이브리드) 또는 agent 모드

★ ServiceMonitor·relabeling·recording rules는 그대로 —
  절단선이 "수집과 저장 사이"이므로 08의 체계는 손대지 않습니다
  (metricRelabelings drop이 AMP 샘플 요금의 수문이 됩니다!)
```

## 5. AMP의 관리형 규칙·Alertmanager

```
AMP 워크스페이스에 룰 네임스페이스 업로드 (YAML — Prometheus 형식 그대로):
  recording rules: AMP 쪽에서 평가 (에이전트 모드일 때 필수)
  alerting rules → 관리형 Alertmanager → SNS로 라우팅
    (10의 Alertmanager 대비: 라우팅 대상이 SNS 중심 — 거기서 Slack 등으로)

이관 판단:
  하이브리드(로컬 유지)면: 룰은 로컬 평가 유지가 단순 (10 그대로)
  에이전트 모드면: 룰·알림 전부 AMP로 (평가 주체가 없어지므로)
```

## 6. 요금 모델과 판단

```
AMP 과금 (개념 — 최신 요금표 확인):
  샘플 ingest (10억 샘플당) + 저장(샘플·월) + 쿼리(처리 샘플)
  샘플/월 ≈ 활성 시계열 × (2,592,000초 ÷ scrape 간격)
  예: 10만 시계열 × 15s 간격 ≈ 172억 샘플/월 — 계산해 보는 습관!
  → 카디널리티(03·08)와 scrape 간격이 요금의 두 손잡이

판단표 (자체 vs AMP vs Thanos/Mimir — 24에서 최종):
              자체(로컬만)     AMP              Thanos/Mimir(24)
보존          짧음(주 단위)    장기(관리형)       장기(오브젝트 스토리지)
운영          서버 1대 수준    거의 없음          상당(컴포넌트 다수)
확장          벽(08)          AWS가             직접 설계
멀티클러스터   별도 구성        워크스페이스로 집약  글로벌 쿼리
비용          인프라비         샘플 종량          인프라+운영 (대규모선 유리 가능)
어울림        소규모·단순      AWS 중심·운영 최소  초대규모·멀티클라우드·역량 보유

→ 09·39·40의 "관리형 우선, 자체는 조건(규모+역량)"이 그대로
```

## 7. 소스/도구에서 확인하기

- AMP 문서: docs.aws.amazon.com/prometheus — remote_write·rules·alertmanager
- AMP 요금: aws.amazon.com/prometheus/pricing
- IRSA: eks 파트 해당 모듈 (신뢰 정책·OIDC)
- awscurl: SigV4 서명 쿼리 도구 (lab에서 사용)

## 요약 카드

| 질문 | 답 |
|------|----|
| 절단선? | 수집(체계·규약 — 남음)과 저장(물리 — 넘김) 사이 |
| remote_write? | 표준 프로토콜 — AMP/Thanos/Mimir 교체 가능 (lock-in 완화) |
| 에이전트 모드? | 저장·쿼리·룰 없는 순수 수집기 — 쿼리·알림은 AMP 쪽으로 |
| 하이브리드? | 짧은 로컬 보존+remote_write — 로컬 알림 자율성 유지 (흔한 실전) |
| 인증? | SigV4 ← IRSA(SA에 IAM 롤) — AWS 관측 스택 공통 관문 |
| 08 체계는? | SM·relabeling·rules 그대로 — relabel drop이 AMP 요금 수문 |
| 요금 손잡이? | 카디널리티 × scrape 간격 = 샘플 수 (계산 습관!) |
| 판단? | 관리형 우선(AMP), 자체 확장(Thanos/Mimir)은 규모+역량 조건 (24 최종) |
