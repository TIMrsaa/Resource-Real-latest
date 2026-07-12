# 이론 — 확장 한계, 병목 4대장, 클라이언트 매너

> **🌱 17세 눈높이 비유: 학생 수가 10배가 된 학교**
> 학생 300명일 땐 멀쩡하던 학교가 3000명이 되면 **예측 가능한 순서로** 무너집니다:
> ① **학적부 보관실**(etcd)이 가득 차고, 서류 넘겨주는 속도가 한계에 닿습니다
> ② 행정실(API 서버)에 "전교생 명단 출력해주세요"(full LIST) 같은 민원이 겹치면 행정실 컴퓨터가 멈춥니다 — 그래서 **민원 종류별 줄 세우기**(APF)를 도입합니다
> ③ 반 배정 담당자(스케줄러)가 전학생을 초당 몇 명까지만 배정할 수 있습니다 — 신학기(대량 생성)엔 줄(Pending)이 생깁니다
> 핵심: 한계는 학생 수 자체보다 **"전교생 명단 출력" 같은 나쁜 민원 습관**에서 먼저 옵니다.

---

## 1. 공식 확장 한계 (SIG Scalability 기준)

| 항목 | 한계 | 비고 |
|------|------|------|
| 노드 | ≤ 5,000 | 그 이상은 멀티 클러스터로 |
| 총 Pod | ≤ 150,000 | |
| 총 컨테이너 | ≤ 300,000 | |
| 노드당 Pod | ≤ 110 (기본) | EKS는 ENI/IP가 먼저 한계(모듈 27) |

→ 이 수치는 "여기까지 SLO(API p99 ≤ 1s 등)를 보장하며 테스트했다"는 뜻이지 절벽이 아닙니다. 실제론 **객체 수 × 객체 크기 × 변경 빈도(churn) × 클라이언트 행동**의 곱이 진짜 한계를 정합니다 — 노드 50개여도 Job 시체 30만 개면 무너집니다.

## 2. 병목 ① etcd — 가장 먼저, 가장 치명적

- **저장 한도**: 쿼터 기본 2GB, 권장 상한 ~8GB(모듈 22). 초과 시 **클러스터 전체가 읽기 전용**이 되는 단일 장애점
- **무엇이 채우나**: Pod 시체(Evicted/Completed), 이벤트(기본 1h TTL이지만 폭주 시), 거대 ConfigMap, 끝없이 쌓이는 CR
- **watch 증폭**: 객체 1개가 바뀌면 그걸 watch하는 **모든** 클라이언트에게 복사 전송 — 노드 1000개면 Pod 업데이트 1건이 1000개의 kubelet/kube-proxy에 증폭될 수 있습니다. 변경 빈도(churn)가 곧 부하
- EKS: etcd 운영은 AWS 몫이지만 **저장 한도는 우리 몫** — `apiserver_storage_objects` 메트릭으로 종류별 객체 수를 감시(lab-01)

## 3. 병목 ② API 서버 — expensive LIST와 APF

### LIST가 비싼 이유

`kubectl get pods -A`(full LIST) 한 번 = etcd 범위 읽기 + **전체 객체를 API 서버 메모리에 직렬화** + 전송. Pod 15만 개면 요청 1건에 수 GB 메모리가 출렁입니다. 대규모 사고 보고서의 단골 주범.

| 패턴 | 비용 | 비고 |
|------|------|------|
| full LIST (매번) | 최악 | 폴링 루프 = 클러스터 살인 |
| LIST + `resourceVersion=0` | 저렴 | etcd 대신 **watch cache**에서 응답 |
| 페이지네이션 (`limit`/`continue`) | 중간 | 메모리 스파이크 방지 |
| **informer** (LIST 1회 + WATCH) | 최선 | 모듈 31 — 변경분만 구독 |

### APF (API Priority and Fairness) — 과부하 방어선

모든 요청을 **FlowSchema**(누구의 어떤 요청인가 분류) → **PriorityLevel**(우선순위별 동시 실행 슬롯+큐)로 나눕니다:

```
system 레벨:       kubelet 하트비트 등 — 절대 밀리면 안 됨
workload-high:     kube-system 컨트롤러
workload-low:      일반 SA의 컨트롤러
global-default:    나머지 (우리의 kubectl)
→ 폭주 클라이언트는 자기 레벨의 큐에서만 기다리거나 429를 받고,
  다른 레벨(kubelet 하트비트)은 영향 없음 — "한 명의 폭주가 전체 마비"를 차단
```

429를 받으면 클라이언트는 `Retry-After`대로 물러나야 합니다(client-go는 자동). **APF는 보호 장치지 성능 향상이 아닙니다** — 429가 보이면 클라이언트를 고쳐야 합니다.

## 4. 병목 ③ 스케줄러 — 초당 배치 수

- 처리량: 대략 **초당 수십~수백 Pod** (플러그인 구성/노드 수에 따라). 5000 Pod 대량 생성 시 수십 초~수 분의 Pending 적체는 정상 범위
- **percentageOfNodesToScore**: 노드 5000개를 전부 채점(Score)하면 느리니, Filter 통과 노드 중 **일부만 채점**하고 끊습니다. 기본값은 적응형(클러스터가 클수록 낮은 %, 최소 5%) — "최적 노드"를 포기하고 "충분히 좋은 노드"를 빨리 찾는 트레이드오프(모듈 25의 프레임워크에서 이 단계가 보입니다)
- 스케줄링을 느리게 만드는 사용자 요인: 무거운 podAffinity(전 노드 대조), topologySpreadConstraints 남용, 거대한 단일 ns

## 5. 병목 ④ 노드/네트워크 — 흩어진 한계들

| 한계 | 증상 | 대응 |
|------|------|------|
| CoreDNS 2 replicas 고정 | DNS 지연/드랍 (모듈 16) | replicas 비례 증설 + **NodeLocal DNSCache**(노드마다 DNS 캐시 DaemonSet — 질의의 대부분을 노드 안에서 끝냄) |
| conntrack 테이블 포화 | 간헐 타임아웃 (모듈 28) | max 상향, 커넥션 풀 |
| ARP/neighbor 캐시(gc_thresh) | 대규모에서 "no route to host" | 노드 sysctl 상향 |
| 이미지 풀 폭주 | 신규 노드 웜업 지연 | 이미지 슬리밍, 캐싱(EKS는 SOCI/스냅샷터) |

## 6. EKS에서의 분업 정리

| 층 | AWS가 함 | 우리가 함 |
|----|----------|----------|
| etcd | 운영/스케일/백업 | **객체 수 위생** (TTL, history limit, 시체 정리) |
| API 서버 | 부하 따라 자동 증설 | **클라이언트 매너** (informer, 페이지네이션, 셀렉터), APF 관측 |
| 스케줄러 | 운영 | Pod 스펙 다이어트, 대량 생성 시 점진 투입 |
| 노드 | AMI 제공 | DNS 캐시, sysctl, 이미지 전략 |

## 7. 소스/도구에서 확인하기

- 공식 한계: https://kubernetes.io/docs/setup/best-practices/cluster-large/
- APF: https://kubernetes.io/docs/concepts/cluster-administration/flow-control/
- percentageOfNodesToScore: `pkg/scheduler/apis/config/types.go`
- kwok (가짜 노드 시뮬레이터): https://kwok.sigs.k8s.io/

## 요약 카드

| 질문 | 답 |
|------|----|
| 공식 한계? | 5,000노드 / 150k Pod / 노드당 110 |
| 가장 먼저 부러지는 곳? | etcd (저장 한도 + watch 증폭) |
| API 서버 살인 패턴? | 폴링 full LIST — informer로 교체 |
| APF의 역할? | 요청을 분류해 폭주를 그 줄 안에 가둠 (보호지 성능 아님) |
| 스케줄러의 대규모 트릭? | 노드 일부만 채점 (percentageOfNodesToScore) |
| DNS 규모 대응? | CoreDNS 증설 + NodeLocal DNSCache |
