# 이론 — 관측성 3축과 AWS 네이티브 파이프라인의 해부

> **🌱 17세 눈높이 비유: 자동차의 계기판, 블랙박스, 내비 기록**
> 차에 무슨 일이 생겼는지 아는 세 가지 장치:
> - **계기판(메트릭)** = 속도·연료·엔진온도 — 숫자 몇 개로 "지금 이상한가"를 즉시. 경고등(알람)은 계기판 위에 섭니다
> - **블랙박스(로그)** = 그 순간의 영상 — "왜 그랬는가"의 서술. 대신 용량이 큽니다
> - **내비 주행기록(트레이스)** = 한 여행이 어떤 길을 거쳤나 — 여러 구간 중 "어디서" 막혔는지
> - 그리고 어른의 사정: **블랙박스를 4K 상시녹화로 전 좌석에 달면 저장 비용이 차 유지비를 넘습니다** — 관측성은 언제나 "무엇을 남길 것인가"의 편집입니다

---

## 1. 3축이 답하는 질문이 다릅니다

| 축 | 질문 | 형태 | k8s 38과의 관계 |
|----|------|------|----------------|
| 메트릭 | 이상한가? 얼마나요? 언제부터? | 시계열 숫자 (쌉니다, 알람 가능) | describe 전에 울리는 사이렌 |
| 로그 | 왜? 무슨 일이 있었나요? | 텍스트 스트림 (비쌉니다, 검색) | logs --previous의 상시 보관판 |
| 트레이스 | 여러 서비스 중 어디서? | 요청 단위 경로 | (ADOT/X-Ray — 여기선 지도만) |

k8s 38의 진단 루틴은 장애 **후** 클러스터에 물었습니다. 관측성은 같은 질문을 **미리, 밖에**(클러스터가 죽어도 남는 곳에) 적어두는 것 — Pod가 사라져도 로그는 CloudWatch에 있습니다(`logs --previous`의 한계 탈출).

## 2. 부품 지도 — amazon-cloudwatch-observability 애드온

11에서 배운 관리형 애드온 하나가 이 모듈의 전 부품을 깝니다:

```
EKS Addon: amazon-cloudwatch-observability
  └─ Operator (Deployment — k8s 30의 그 패턴)
       ├─ cloudwatch-agent   (DaemonSet) ── 메트릭 수집 → Container Insights
       └─ fluent-bit         (DaemonSet) ── 로그 수집   → CloudWatch Logs
```

만들어지는 로그 그룹 4형제 (`/aws/containerinsights/<클러스터>/...`):

| 로그 그룹 | 내용 |
|-----------|------|
| `/application` | **컨테이너 stdout/stderr** — 주인공 |
| `/dataplane` | containerd/kubelet 등 노드 데몬 로그 |
| `/host` | 노드 OS 로그 (dmesg 등) |
| `/performance` | **성능 이벤트(EMF)** — §4의 반전 |

## 3. 로그의 길 — stdout이 CloudWatch에 닿기까지

```
앱이 stdout에 한 줄 출력
 → containerd가 노드 파일로: /var/log/containers/<pod>_<ns>_<container>-<id>.log
 → Fluent Bit(그 노드의 DaemonSet Pod)이 tail
     + kubernetes 필터: 파일명에서 pod/ns를 알아내 API로 라벨 등 메타데이터를 붙임
 → CloudWatch Logs로 배송 (/application)
```

이 구조에서 읽을 것 세 가지: ① 로그 수집이 **노드 단위**입니다(DaemonSet — k8s 13이 여기 있습니다) ② 앱이 **파일이 아니라 stdout에 쓰는 게** 12-factor인 이유 — 파이프라인이 stdout만 줍는다 ③ 메타데이터(ns/pod/라벨)가 붙어서 가므로 나중에 "이 ns의 로그만" 검색이 됩니다.

## 4. 메트릭의 길 — 사실은 이것도 로그입니다

cloudwatch-agent는 kubelet/cAdvisor에서 CPU·메모리·네트워크를 긁어 **EMF**(Embedded Metric Format — 메트릭 정의를 품은 JSON 로그)로 `/performance` 로그 그룹에 씁니다. CloudWatch가 그걸 받아 `ContainerInsights` 네임스페이스의 메트릭으로 세웁니다:

```
pod_cpu_utilization, pod_memory_utilization, node_cpu_utilization,
cluster_failed_node_count, pod_number_of_container_restarts ...
```

함의: "메트릭이 안 보인다" 디버깅의 종착지는 `/performance` 로그 그룹입니다 — 로그가 오는데 메트릭이 없다면 EMF 단계, 로그부터 없다면 agent/권한 단계.

## 5. 읽기와 울리기 — Logs Insights, 알람

**Logs Insights** = 로그 그룹 위의 쿼리 엔진 (저장된 것을 스캔 — 스캔량 과금):

```
fields @timestamp, log
| filter kubernetes.namespace_name = "shop" and log like /ERROR/
| stats count(*) as errors by kubernetes.pod_name, bin(5m)
| sort errors desc
```

**알람** = 메트릭에 조건을 걸어 상태기계(OK/ALARM/INSUFFICIENT_DATA)를 돌리고, 상태 전이 시 SNS로 발사. "장애 전에 아는" 장치의 최소 구성이 [메트릭 → 알람 → SNS → 사람/자동화]입니다. eks 파트에서 반복 예고된 것들 — ipamd 메트릭(07), Degraded 애드온(11), Pending 적체(k8s 37) — 전부 이 틀에 담깁니다.

## 6. 비용 구조 — 관측성의 어른의 사정

| 과금 항목 | 구조 | 함정 |
|-----------|------|------|
| 로그 **수집** | GB당 (저장보다 훨씬 비쌈) | 디버그 로그 전면 수집 = 폭탄 |
| 로그 저장 | GB·월 | 보존 기본값이 **무기한(Never expire)** |
| Insights 쿼리 | 스캔 GB당 | 시간 범위 무한정 쿼리 |
| 메트릭/알람 | 개당 | Container Insights는 Pod 수에 비례 |

통제 수단 3종 (lab-02의 한 축):

1. **보존 정책** — 로그 그룹마다 retention 설정 (7~30일이 흔한 답)
2. **수집 필터** — Pod annotation `fluentbit.io/exclude: "true"`(그 Pod 제외), 애드온 configuration-values로 수집 범위 조정(11의 그 통로)
3. **수집량 감시** — 로그 그룹 `IncomingBytes` 메트릭에 알람 = "관측성을 관측"

## 7. 소스/도구에서 확인하기

- Fluent Bit: https://github.com/fluent/fluent-bit — `plugins/filter_kubernetes/`(메타데이터 주입부)
- CloudWatch Agent: https://github.com/aws/amazon-cloudwatch-agent
- 애드온 문서: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-EKS-addon.html
- EMF 명세: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format_Specification.html

## 요약 카드

| 질문 | 답 |
|------|----|
| 3축의 질문? | 메트릭=이상한가·얼마나 / 로그=왜 / 트레이스=어디서 |
| 설치 단위? | amazon-cloudwatch-observability 애드온 (Operator→agent DS+Fluent Bit DS) |
| 로그의 길? | stdout → 노드 파일 → Fluent Bit(DS) → /application |
| 메트릭의 반전? | EMF 로그(/performance)로 들어와 메트릭이 됩니다 |
| 알람 최소 구성? | 메트릭 → 알람(상태기계) → SNS |
| 비용의 주범? | 수집(GB) 과금 + 무기한 보존 기본값 |
| 통제 3종? | 보존 정책 / 수집 필터 / IncomingBytes 감시 |
