# 이론 — 2층 구조, Fluentd 설정 모델, forward 신뢰성, 애그리게이터 역할, 판단

> **🌱 17세 눈높이 비유: 동네 수거차와 권역 재활용 센터**
> - **단층(각 동네 차가 처리장 직행)** = 동네 차 300대가 제각각 소각장·재활용장·매립지 3곳을 다 다님 — 길도 다 알아야 하고 출입증도 300장×3
> - **2층(권역 센터 경유)** = 동네 차는 가까운 권역 센터(애그리게이터)에만 내려놓음 — 센터의 대형 트럭이 분류·가공 후 각 처리장으로
> - **분업** = 동네 차(Bit)는 작고 빠르게 수거만, 센터(Fluentd)는 크고 정교하게 분류·가공(마스킹)·배송
> - **새 비용** = 센터 자체를 운영해야 함(인력·설비·야적장=버퍼) + 센터가 멈추면 전 동네가 영향
> - **ack(인수증)** = 동네 차가 "내려놓았음"이 아니라 센터의 "받았음" 확인까지 기다려야 분실이 없습니다
> - **판단** = 동네 3곳·처리장 1곳이면 센터는 사치 — 규모가 센터를 정당화합니다

---

## 1. 2층 구조 — 문제와 답

```
단층 (06): [Bit×노드수] → 목적지들
  연결 = 노드 × 목적지 (곱), 정책·인증 분산, 가공이 노드 부담

2층: [Bit×노드수] → [Fluentd×소수] → 목적지들
  노드층: 읽기·CRI·메타데이터만 (가볍게 유지)
  집계층: 파싱 심화·마스킹·변형·라우팅·배달 (무거운 것 집중)

효과:
  연결: 노드×1 + 집계×목적지 (합) — 곱→합
  정책 변경: 집계층 replicas 몇 개만 롤링 (DaemonSet 전체 X)
  목적지 인증: 집계층에만
  버퍼: 집계층에 집중 → 큰 디스크·모니터링 한곳

비용:
  운영점 +1 (집계층의 HA·스케일·버퍼)
  홉 +1 (지연·장애 지점)
  forward 구간 신뢰성 설계 필요 (3절)
```

## 2. Fluentd 설정 모델

```
<source>                          # 입력
  @type forward                   # Bit들이 보내는 것을 수신 (24224)
  port 24224
</source>

<filter kube.**>                  # 가공 (태그 패턴)
  @type record_transformer        # 필드 추가·변형
  <record>
    cluster prod-a
  </record>
</filter>

<match kube.shop.**>              # ★ 출력 — 위에서부터 첫 일치가 소비!
  @type copy                      # 하나를 여럿으로
  <store>
    @type opensearch ...          # 검색용
  </store>
  <store>
    @type s3 ...                  # 아카이브
  </store>
</match>
<match **>                        # 캐치올 (마지막에!)
  @type stdout
</match>

<label @AUDIT>                    # 격리된 파이프라인 (내부 라우팅용)
  <match **> ... </match>
</label>

핵심 감각:
  ① match는 순차 — 첫 일치가 레코드를 소비 (좁은 패턴을 위에)
  ② copy — 다중 목적지의 표준 수단
  ③ label — 파이프라인 격리 (audit 전용 흐름 등)
  ④ 버퍼는 match(출력)별 <buffer> — cncf 14의 청크·플러시가 여기
```

## 3. forward 프로토콜 — 구간의 신뢰성

```
Bit 쪽 (출력):
  [OUTPUT]
      Name          forward
      Match         kube.*
      Host          fluentd.logging.svc
      Port          24224
      Require_ack_response  True     # ★ ack까지 기다림 (at-least-once에 근접)

Fluentd 쪽 (입력): <source> @type forward

신뢰성 옵션의 의미:
  ack 없음(기본): TCP 전송 = 성공 취급 — Fluentd가 받자마자 죽으면 유실
  ack 있음: Fluentd가 버퍼에 기록 후 응답 — 유실 창 축소, 지연·처리량 대가
  → 감사급 로그는 ack, 대량 일반 로그는 트레이드오프 판단 (06의 등급별 설계)

로드밸런싱·HA:
  Bit forward는 Upstream 설정으로 다중 Fluentd에 분산 가능
  K8s에선 Service(ClusterIP) 뒤에 Fluentd replicas — 단 장기 TCP 연결이라
  분산이 고르지 않을 수 있음 (headless + Upstream이 더 고름)
  집계층은 Deployment ×N + PDB (여기도 가용성 설계!)

중복의 수용:
  ack 재전송 시나리오에서 중복 가능 = at-least-once
  → 저장소에서 멱등 처리(문서 ID) 또는 중복 허용 — "정확히 한 번"은 환상 (cncf 40의 메시징과 동일)
```

## 4. 애그리게이터의 대표 역할

```
① 민감정보 마스킹 (한곳에서):
   record_transformer·정규식으로 카드번호·토큰 마스킹
   → 노드 300곳이 아니라 집계층 한곳의 정책 (02의 "최후의 그물")

② 다중 배달 (copy):
   같은 로그를 OpenSearch(검색, 단기) + S3(아카이브, 장기) 동시에
   → 18·22의 저장 계층화가 여기서 구현됨

③ 재라우팅·강화:
   네임스페이스→테넌트 매핑, 클러스터 식별 필드 추가(멀티클러스터, 24),
   레코드 기반 조건 라우팅 (rewrite_tag_filter)

④ 유량 완충:
   목적지별 buffer 정책(파일 버퍼·플러시 간격·재시도)을 집계층에서 통일 관리
   → 목적지 장애의 버퍼가 한곳에 (모니터링 단일점)
```

## 5. 판단 — 단층이냐 2층이냐

```
단층(Bit 직행)이 맞습니다:
  노드 수십 대 이하, 목적지 1~2개, 가공 단순(파싱·필터 정도)
  → 2층은 운영점만 늘림 (과잉 설계)

2층이 값을 냅니다:
  노드 수백+, 목적지 다수(검색+아카이브+SaaS), 무거운 가공(마스킹·변형),
  정책 변경이 잦음, 멀티클러스터 로그를 한곳으로 모을 때(24)

중간 해법:
  Bit 단독 + 목적지 2개까지는 Bit의 다중 OUTPUT으로 버팀
  Fluentd 대신 OTel Collector gateway(11·16)로 통일하는 흐름도 —
  로그·메트릭·트레이스를 한 게이트웨이로 (신호 통합의 방향)

★ cncf의 반복 판단: 층은 필요가 정당화할 때만 (46의 점진 도입과 동일)
```

## 6. 소스/도구에서 확인하기

- Fluentd 문서: docs.fluentd.org — config-file·forward·buffer
- Fluent Bit forward 출력: docs.fluentbit.io (Upstream 포함)
- cncf 14: 버퍼 청크·백프레셔의 내부 (집계층 버퍼 이해의 기반)
- fluent/fluentd-kubernetes-daemonset·helm 차트

## 요약 카드

| 질문 | 답 |
|------|----|
| 2층의 효과? | 연결 곱→합, 정책·인증 집중, 노드 경량 유지, 버퍼 단일점 |
| 2층의 비용? | 운영점+1(HA·버퍼), 홉+1, forward 신뢰성 설계 |
| Fluentd 문법 핵심? | match 순차(첫 일치 소비!)·copy(다중 출력)·label(격리) |
| forward ack? | Fluentd 버퍼 기록 후 응답 — 유실 창 축소, 지연 대가 (등급별) |
| 정확히 한 번? | 환상 — at-least-once + 저장소 멱등/중복 수용 |
| 집계층 역할? | 마스킹(한곳)·copy 다중 배달·재라우팅·유량 완충 |
| 단층으로 충분? | 노드 수십·목적지 1~2·가공 단순이면 — 층은 필요가 정당화 |
| 대안 흐름? | OTel Collector gateway로 신호 통합(11·16) |
