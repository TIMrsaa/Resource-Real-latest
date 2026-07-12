# Lab 02 — 애그리게이터의 역할: 마스킹, copy 다중 배달, 판단

> 집계층이 값을 하는 순간들을 구현합니다 — 민감정보 마스킹(한곳의 정책), copy로 두 목적지 동시 배달(저장 계층화의 씨앗), match 순서의 함정 체험, 그리고 "단층 vs 2층" 판단 정리.

## 0. 준비 (lab-01 이어서 — talker의 카드번호가 재료)

```bash
kubectl -n logging logs deploy/fluentd --since=10s | grep card | tail -1
# ..."card":"1234-5678-9012-3456"...   ← 민감정보가 그대로 흐르고 있습니다!
```

## 1. 역할 ① — 민감정보 마스킹 (한곳의 정책)

```bash
kubectl -n logging patch configmap fluentd-config --type merge -p '
data:
  fluent.conf: |
    <source>
      @type forward
      port 24224
      bind 0.0.0.0
    </source>

    <filter kube.**>
      @type record_transformer
      <record>
        cluster kind-twotier
      </record>
    </filter>

    # ★ 마스킹: 카드번호 패턴을 집계층에서 일괄 차단 (02의 "최후의 그물")
    <filter kube.**>
      @type record_transformer
      enable_ruby true
      <record>
        card ${record["card"] ? record["card"].gsub(/\d{4}-\d{4}-\d{4}-(\d{4})/, "****-****-****-\\1") : nil}
      </record>
    </filter>

    <match kube.**>
      @type stdout
    </match>
'
kubectl -n logging rollout restart deploy/fluentd
kubectl -n logging rollout status deploy/fluentd --timeout=120s
sleep 15

kubectl -n logging logs deploy/fluentd --since=10s | grep card | tail -1 | head -c 300
# ..."card":"****-****-****-3456"...   ← ★ 마스킹됨!
```

**의미** — 마스킹 정책이 **집계층 replicas 2개**에만 있습니다. 노드 300대(가정)에 배포·동기화할 필요가 없고, 정책 변경은 이 ConfigMap 하나입니다. 물론 원칙은 여전히 "앱에서 애초에 안 찍기"(02)이고, 이것은 누수를 전제한 마지막 그물입니다 — 그물이 있다고 앱이 마음껏 찍으면 안 됩니다(그물 앞 구간, 즉 노드 파일·forward 구간에는 원문이 존재합니다!).

## 2. 역할 ② — copy 다중 배달 (검색 + 아카이브)

목적지 두 개를 흉내 내고(파일로), copy로 동시 배달합니다:

```bash
kubectl -n logging patch configmap fluentd-config --type merge -p '
data:
  fluent.conf: |
    <source>
      @type forward
      port 24224
      bind 0.0.0.0
    </source>

    <filter kube.**>
      @type record_transformer
      enable_ruby true
      <record>
        cluster kind-twotier
        card ${record["card"] ? record["card"].gsub(/\d{4}-\d{4}-\d{4}-(\d{4})/, "****-****-****-\\1") : nil}
      </record>
    </filter>

    <match kube.**>
      @type copy
      <store>                                # 목적지 1: "검색용" (즉시·stdout으로 흉내)
        @type stdout
      </store>
      <store>                                # 목적지 2: "아카이브" (파일 버퍼로 흉내 — 실전은 S3)
        @type file
        path /tmp/archive/kube
        <buffer time>
          timekey 60
          timekey_wait 10
          flush_mode interval
          flush_interval 30s
        </buffer>
        <format>
          @type json
        </format>
      </store>
    </match>
'
kubectl -n logging rollout restart deploy/fluentd
kubectl -n logging rollout status deploy/fluentd --timeout=120s
sleep 90

# 목적지 1(즉시): stdout에 흐르는 중
kubectl -n logging logs deploy/fluentd --since=20s | grep -c '"seq"'
# 목적지 2(아카이브): 파일이 시간 단위로 쌓임
kubectl -n logging exec deploy/fluentd -- ls /tmp/archive/
# kube.20260711.log ...   ← timekey별 아카이브 파일
```

**의미** — 같은 레코드가 **두 성격의 목적지**로 갔습니다: 즉시성(검색·조사용, 실전은 OpenSearch/Loki — 12·18)과 저비용 장기(아카이브, 실전은 S3 + 수명 정책). 이 분기가 22(비용)의 저장 계층화 전략의 뼈대입니다 — 비싼 검색 저장소엔 짧게, 싼 오브젝트 저장소엔 길게.

## 3. 함정 체험 — match 순서

```
만약 설정이 이랬다면:
  <match **>            # 캐치올이 위에!
    @type stdout
  </match>
  <match kube.shop.**>  # 도달 불능 — 위에서 이미 소비됨
    @type s3 ...        # shop 로그는 영원히 S3에 안 감 (에러도 없이!)
  </match>

Fluentd match는 순차·첫 일치 소비:
  → 좁은 패턴을 위에, 캐치올(**)은 항상 마지막에
  → 라우팅 누락은 조용합니다 — 변경 후 각 목적지 도달 검증 필수 (06의 교훈 재현)
```

## 4. 판단 정리 — 우리 조직은 단층? 2층?

| 축 | 단층(Bit 직행) | 2층(Bit→Fluentd) |
|----|---------------|------------------|
| 노드 수 | ~수십 | 수백+ |
| 목적지 | 1~2 | 3+ (검색+아카이브+SaaS...) |
| 가공 | 파싱·필터 | 마스킹·변형·조건 라우팅 |
| 정책 변경 빈도 | 낮음 | 잦음 (반경 축소가 값짐) |
| 운영 여력 | 최소 | 집계층 HA·버퍼 운영 가능 |

```
추가 고려:
  멀티클러스터 중앙화(24) → 2층이 자연스러움 (클러스터별 Bit → 중앙 Fluentd)
  신호 통합 지향 → Fluentd 대신 OTel Collector gateway(11·16)도 후보
    (로그만이 아니라 메트릭·트레이스까지 한 게이트웨이 — 방향성 있는 흐름)
  EKS + CloudWatch 단일 목적지(13) → 단층으로 충분한 경우 많음
```

## 5. SIGNALS-MAP 갱신 (과제)

```
05의 지도 2절을 갱신하세요:
  로그: Fluent Bit(노드, fs버퍼·ack) → Fluentd(집계, 마스킹·copy) → [stdout/archive]
  상태: 🔶 (목적지가 아직 흉내 — 12·13·18에서 실물로)
  갱신 로그: "07 수료 — 2층 구축, 마스킹·다중 배달 확보"
```

## 6. 정리

```bash
kind delete cluster --name twotier
rm -f /tmp/fb-forward.yaml
```

## 정리

- 마스킹을 집계층 한곳에서 — 정책 집중의 가치 (단, 그물 앞 구간엔 원문 존재 — 앱이 원칙)
- copy = 다중 배달: 즉시(검색) + 장기(아카이브) — 저장 계층화(22)의 뼈대
- match는 순차·첫 일치 소비 — 캐치올을 위에 두면 조용한 라우팅 구멍
- 판단표: 노드 수·목적지 수·가공 복잡도·변경 빈도·운영 여력 — 층은 필요가 정당화
- **★ 집계층의 본질 = 정책의 단일점 (마스킹·라우팅·버퍼) — 그 대가는 새 운영점**
