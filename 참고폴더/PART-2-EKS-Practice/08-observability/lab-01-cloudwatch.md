# Lab 01 — CloudWatch Container Insights

## ⚠️ 비용

CloudWatch Logs ingestion 은 GB 당 청구. 학습 1~2시간 후 반드시 disable.

> **💸 CloudWatch Logs 비용 구조**
> - **Ingestion** (수집): $0.50/GB
> - **Storage** (저장): $0.03/GB-월
> - **Insights query**: 스캔된 데이터 GB당 $0.005
>
> Pod 100개가 분당 1KB 로그 → 일 14GB → 인입 비용만 일 $7. 학습 끝나면 즉시 삭제!

## 학습 확인 포인트

- [ ] Container Insights addon 설치
- [ ] CloudWatch 콘솔에서 Container Insights 페이지를 봤다
- [ ] 앱 로그가 CloudWatch Logs로 보내짐을 확인

> **🌱 핵심 개념 미리보기**
> - **Container Insights**: AWS가 만든 EKS 메트릭/로그 통합 모니터링. CloudWatch UI에 통합됨
> - **Fluent Bit**: 경량 로그 수집기. 노드의 /var/log/containers/ 를 읽어 CloudWatch로 전송 (DaemonSet)
> - **CloudWatch Agent**: CPU/메모리/디스크 메트릭 수집 (DaemonSet)
> - **Log Group**: CloudWatch Logs의 논리적 묶음. retention과 권한이 group 단위
>
> **CloudWatch vs Prometheus** (lab 02):
> - CloudWatch: AWS 매니지드, UI 통합, 장기 저장 쉬움, 비용 ↑
> - Prometheus: K8s 네이티브, PromQL 풍부, 자체 운영 필요, 비용 ↓
> 둘 중 하나만 쓰거나 병행 사용 모두 가능.

## 1. IRSA 셋업 (CloudWatch Observability)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=amazon-cloudwatch \
  --name=cloudwatch-agent \
  --attach-policy-arn=arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
  --override-existing-serviceaccounts \
  --approve --region=ap-northeast-2

eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=amazon-cloudwatch \
  --name=fluent-bit \
  --attach-policy-arn=arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
  --override-existing-serviceaccounts \
  --approve --region=ap-northeast-2
```

> **🧠 왜 SA 두 개에 같은 정책?**
> CloudWatch Agent와 Fluent Bit는 둘 다 CloudWatch에 데이터 보냄. 같은 정책(`CloudWatchAgentServerPolicy`) 사용.
> 분리 이유:
> - 컨테이너 분리 (한쪽 죽어도 다른 쪽 영향 X)
> - 향후 권한 차등화 가능 (예: Fluent Bit만 logs:PutLogEvents)
>
> **`--override-existing-serviceaccounts`**: 같은 이름 SA가 있으면 어노테이션 덮어씀.

## 2. addon 설치

```bash
eksctl create addon --cluster eks-study \
  --name amazon-cloudwatch-observability \
  --region ap-northeast-2
```

기다리기:
```bash
kubectl get pods -n amazon-cloudwatch --watch
```

기대 (시간 지나면):
```
NAME                              READY   STATUS    RESTARTS   AGE
amazon-cloudwatch-observability-controller-manager-xxx   1/1   Running   0   30s
cloudwatch-agent-aaaaa            1/1   Running   0          20s
cloudwatch-agent-bbbbb            1/1   Running   0          20s
fluent-bit-ccccc                  1/1   Running   0          15s
fluent-bit-ddddd                  1/1   Running   0          15s
```

> **🧠 떠 있는 컴포넌트 4종**
> - `controller-manager`: addon 설정 관리 (CRD watch)
> - `cloudwatch-agent` (DaemonSet): 노드별 메트릭 수집
> - `fluent-bit` (DaemonSet): 노드별 로그 수집
> - DaemonSet 이라 노드당 1개씩 (위에서 노드 2개라 각 2개)

## 3. CloudWatch Logs Group 확인

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights/eks-study/ \
  --query 'logGroups[].logGroupName' --output table
```

기대:
```
/aws/containerinsights/eks-study/application
/aws/containerinsights/eks-study/dataplane
/aws/containerinsights/eks-study/host
/aws/containerinsights/eks-study/performance
```

> **🧠 4개 Log Group 의 역할**
> | Group | 내용 | 출처 |
> |-------|------|------|
> | `application` | 앱 컨테이너의 stdout/stderr | Fluent Bit |
> | `dataplane` | EKS 데이터 플레인 로그 (kube-proxy, vpc-cni 등) | Fluent Bit |
> | `host` | 노드 OS 레벨 로그 (/var/log/messages 등) | Fluent Bit |
> | `performance` | CPU/메모리/네트워크 메트릭 (JSON) | CloudWatch Agent |

## 4. 테스트용 앱 로그 발생

```bash
kubectl run logger --image=busybox --restart=Never -- \
  sh -c 'for i in $(seq 1 50); do echo "[INFO] event $i at $(date)"; sleep 1; done'
```

> **`--restart=Never`**: Pod 만들 때 RestartPolicy 지정. 기본은 Always (Pod 죽으면 재시작 무한 반복).
> Never = 한 번 끝나면 끝. 일회성 작업에 적합.

대기:
```bash
sleep 60
```

## 5. CloudWatch Logs 에서 로그 확인

```bash
aws logs tail /aws/containerinsights/eks-study/application \
  --since 5m --filter-pattern '"event"' \
  | head -20
```

기대: `[INFO] event 1 at ...` 같은 로그.

> **`aws logs tail`**: tail -f 의 CloudWatch 버전.
> - `--since 5m`: 최근 5분 로그만
> - `--filter-pattern`: CloudWatch Logs Filter Pattern. 단순 키워드, JSON 필드 매칭 가능
> - `--follow`: 실시간 추적 (생략 시 한번 보고 끝)

## 6. Container Insights 대시보드 (콘솔)

CloudWatch → Insights → Container Insights → eks-study 선택.

기본 페이지에서 다음을 볼 수 있음:
- 노드별 CPU/Mem
- Pod 별 CPU/Mem 사용량
- Pod restart 횟수
- 네임스페이스별 리소스

> **콘솔이 보여주는 것의 정체**: 미리 정의된 CloudWatch Metrics 대시보드.
> 데이터는 `performance` log group의 JSON에서 추출됨 (CloudWatch Metric Filter로 메트릭화).

## 7. CloudWatch Logs Insights 쿼리

CloudWatch → Logs → Logs Insights → log group 선택 후:

```
fields @timestamp, @message
| filter @message like /event/
| sort @timestamp desc
| limit 50
```

> **🧠 Logs Insights 쿼리 언어**
> SQL과 비슷하지만 다름. CloudWatch만의 문법.
> - `fields`: 보여줄 필드 선택
> - `filter`: 조건 (정규식 가능)
> - `sort`: 정렬
> - `stats`: 집계 (count, avg, percentile 등)
> - `parse`: 정규식으로 필드 추출
>
> 예: 5분간 에러 로그 카운트
> ```
> fields @timestamp, @message
> | filter @message like /ERROR/
> | stats count() by bin(5m)
> ```
>
> **비용 주의**: 쿼리 시 스캔된 데이터 양만큼 과금. 너무 큰 시간 범위 X.

## 8. 정리

```bash
kubectl delete pod logger
```

addon 자체는 다음 lab 이후 일괄 제거 (Module 끝부분).

## 학습 확인 질문

1. Container Insights 가 만든 4개 Logs Group의 차이는?
2. Fluent Bit 가 stdout/stderr 외에 Pod 의 임의 파일도 수집하게 하려면?
3. 비용을 줄이는 방법 두 가지를 들어보세요.

> **힌트**:
> 1. application(앱 stdout), dataplane(EKS 컴포넌트), host(노드 OS), performance(메트릭).
> 2. Fluent Bit ConfigMap의 INPUT 섹션에 tail 플러그인 추가 (Pod 내부 파일은 emptyDir 볼륨 공유 후 sidecar로 읽거나).
> 3. (a) Log Group retention 짧게 (학습용 1일). (b) Pod 로그 레벨 INFO → WARN 으로 줄여 인입량 ↓. (c) 필요 없는 NS 제외 필터 추가.

다음: [lab-02-prometheus.md](./lab-02-prometheus.md)
