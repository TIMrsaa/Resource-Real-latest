# payment-service

AWS SQS 메시지를 컨슘하여 결제 처리를 시뮬레이션하는 워커 서비스.
**Part 3 KEDA 학습의 핵심**: SQS 큐 길이 기반 ScaledObject 시연.

---

## 코드 한눈에 보기

```
main.go
  ├─ SQS_QUEUE_URL 환경변수 필수 검증
  ├─ AWS SDK 기본 설정 로드 (IRSA/IAM Role 자동 인식)
  ├─ Consumer 구조체 생성 (consumer/sqs.go)
  ├─ Handler 콜백 정의: 메시지 받으면 JSON 파싱 + 로그
  ├─ :9090 메트릭/헬스체크 별도 고루틴
  └─ Run() 호출 → 무한 루프로 PollOnce() 반복
                    + ctx.Done()으로 graceful shutdown

consumer/sqs.go
  ├─ Client interface: SQS API 추상화 (테스트 시 mock 가능)
  ├─ PollOnce: ReceiveMessage(MaxNumberOfMessages=10, WaitTimeSeconds=5)
  │    ├─ 받은 메시지 각각에 대해 Handler 호출
  │    └─ 성공 시 DeleteMessage (실패면 Visibility Timeout 후 재시도)
  └─ Run: ctx 살아있는 동안 PollOnce 무한 반복
```

**Long Polling (WaitTimeSeconds=5)**:
즉시 빈 응답 반환 대신 **메시지 들어올 때까지 5초 대기**.
- 빈 응답 횟수 ↓ = AWS API 호출 비용 ↓
- 메시지 도착 시 즉시 반환 = 응답 속도 ↑

**Visibility Timeout 동작**:
1. ReceiveMessage 호출 시 메시지가 "보이지 않음" 상태로 N초 동안 잠김
2. 그 안에 DeleteMessage 호출 → 메시지 영구 삭제
3. 안 부르면 → Visibility Timeout 만료 → 다시 큐에 노출 → 다른 컨슈머가 처리
   = 자연스러운 재시도 메커니즘 (At-Least-Once 보장)

---

## 동작

1. `SQS_QUEUE_URL` 큐를 long-poll
2. 메시지 수신 시 JSON 파싱 → 로깅 (실제 결제 호출은 시뮬레이션 처리)
3. 정상 처리 후 메시지 삭제 (실패 시 visibility timeout 후 재시도)

---

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `SQS_QUEUE_URL` | (필수) | SQS 큐 URL (없으면 즉시 종료) |
| `AWS_REGION` | (AWS SDK 기본값) | AWS 리전 |

**AWS 인증은 어떻게?**
`config.LoadDefaultConfig()` 가 자동 탐색:
1. 로컬: `~/.aws/credentials` 또는 환경변수 (AWS_ACCESS_KEY_ID 등)
2. EKS Pod: **IRSA로 SA에 매핑된 IAM Role의 임시 자격증명**

→ 코드에 자격증명이 없음 = 보안 + 환경 무관 동작

---

## 로컬 실행 (LocalStack 사용 시)

LocalStack = AWS 서비스를 로컬에서 흉내 내는 도구 (개발용).

```bash
# 1. LocalStack SQS 시작
docker run -d --rm -p 4566:4566 -e SERVICES=sqs localstack/localstack

# 2. 큐 생성
aws --endpoint-url=http://localhost:4566 sqs create-queue --queue-name payments

# 3. payment-service 실행 (가짜 자격증명 + LocalStack 엔드포인트)
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1 \
  SQS_QUEUE_URL=http://localhost:4566/000000000000/payments \
  go run .

# 4. 다른 터미널에서 메시지 보내기
aws --endpoint-url=http://localhost:4566 sqs send-message \
  --queue-url http://localhost:4566/000000000000/payments \
  --message-body '{"order_id":"o1","amount":100}'

# → payment-service 로그: "processed payment" {map}
```

---

## 테스트

```bash
go test ./...
```

`consumer/sqs_test.go` 는 `Client` interface를 mock으로 구현해 SQS 의존성 제거.
이게 `Client interface` 를 만들어둔 이유 (의존성 역전 원칙).

---

## Part 3 KEDA 트리거

```yaml
# Part-3-13 sqs-scaledobject.yaml 참고
triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: ...
      queueLength: "5"  # 메시지 5개당 파드 1개
```

**시나리오 (Part-3-14 콤보)**:
- 큐에 메시지 0개 → Pod 0개 (scale-to-zero)
- 메시지 1000개 한번에 → KEDA가 200개 Pod 요청 → Karpenter가 노드 자동 증설
- 처리 완료 → 큐 비움 → KEDA가 0으로 → Karpenter가 빈 노드 종료
- 결과: **사용한 만큼만 비용**

---

## EKS 배포 시 IAM 권한 (IRSA 필요)

ServiceAccount에 매핑할 IAM 정책:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ],
    "Resource": "arn:aws:sqs:ap-northeast-2:ACCOUNT_ID:eks-study-payments"
  }]
}
```
