# Lab 01 — KEDA 설치

> **🌱 KEDA 가 뭐고 왜 쓰는가?**
> "Kubernetes Event-Driven Autoscaling" — K8s 기본 HPA를 확장해서 **이벤트 기반 스케일링** 가능하게.
>
> **HPA 로 안 되는 것**:
> - SQS 큐 길이 = 1000 → Pod 늘리고 싶음 (HPA는 CPU/메모리만 봄)
> - 큐 비면 Pod 0 으로 (HPA는 0까지 못 내림, 최소 1)
> - Kafka consumer lag 기반 스케일
> - 크론 시간대만 Pod 띄우기
>
> KEDA는 60+ 트리거(scaler) 지원 + scale-to-zero 가능.
>
> **동작 방식 (이게 클릭되는 게 중요)**:
> ```
>   ScaledObject (사용자 작성)
>     ↓ KEDA Operator가 보고
>   HPA + ExternalMetric 자동 생성
>     ↓ HPA가 메트릭 평가
>   metrics-apiserver(=KEDA Pod)에 메트릭 요청
>     ↓ KEDA가 SQS/Kafka/Prometheus 등 외부 조회
>   메트릭 값 반환 → HPA가 desired replicas 계산
> ```
> = KEDA는 HPA를 대체 안 함. HPA를 똑똑하게 만드는 어댑터.

## 1. Helm 설치

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# 사용 가능한 버전 확인 후 사용 (예: 2.16.x). `helm search repo kedacore/keda -l | head` 으로 조회.
KEDA_VERSION=$(helm search repo kedacore/keda --version '>=2.16,<3.0' -o json | jq -r '.[0].version')

helm install keda kedacore/keda \
  --namespace keda --create-namespace \
  --version "${KEDA_VERSION}" \
  --set podIdentity.aws.irsa.enabled=true \
  --wait
```

> **`podIdentity.aws.irsa.enabled=true`**: KEDA가 SQS 등 AWS 트리거 사용 시 IRSA 인증 활성화.
> 트리거의 `authenticationRef` 에서 `podIdentity.provider: aws` 사용 가능해짐.

## 2. 검증

```bash
kubectl get pods -n keda
```

기대:
```
NAME                                                   READY   STATUS
keda-admission-webhooks-xxx                            1/1     Running
keda-operator-xxx                                      1/1     Running
keda-operator-metrics-apiserver-xxx                    1/1     Running
```

> **🧠 Pod 3개의 역할**
> | Pod | 역할 |
> |-----|------|
> | `keda-operator` | ScaledObject CRD watch + HPA 생성/관리 + 외부 메트릭 폴링 |
> | `keda-operator-metrics-apiserver` | K8s External Metrics API 구현체 (HPA가 여기에 메트릭 쿼리) |
> | `keda-admission-webhooks` | ScaledObject validation (잘못된 spec 거부) |
>
> **분리 이유**: metrics-apiserver는 K8s API extension이라 안정성 중요 → operator 죽어도 메트릭 응답 유지.

## 3. CRD 확인

```bash
kubectl get crd | grep keda
```

기대:
```
clustertriggerauthentications.keda.sh
scaledjobs.keda.sh
scaledobjects.keda.sh
triggerauthentications.keda.sh
```

> **🧠 CRD 4개 의미**
> | CRD | 무엇? |
> |-----|------|
> | `ScaledObject` | Deployment/StatefulSet을 스케일링 (long-running 워크로드) |
> | `ScaledJob` | Job을 스케일링 (batch 작업, 메시지당 새 Pod) |
> | `TriggerAuthentication` | 인증 정보 (NS-scoped) |
> | `ClusterTriggerAuthentication` | 인증 정보 (cluster-scoped, 여러 NS 공유) |
>
> ScaledObject vs ScaledJob:
> - ScaledObject: Pod이 메시지 여러 개 처리 (long-running)
> - ScaledJob: 메시지 1개 = Pod 1개 (= 시작/종료 명확). 큐 길이만큼 Job 폭증

## 4. 로그 확인

```bash
kubectl logs -n keda -l app=keda-operator --tail=20
```

## 5. KEDA 메트릭 API 등록 확인

KEDA 가 K8s 의 external metrics API 에 등록되어 HPA 가 사용 가능:
```bash
kubectl get apiservices | grep external.metrics
```

기대:
```
v1beta1.external.metrics.k8s.io   keda/keda-operator-metrics-apiserver  True
```

> **🧠 APIService 객체란?**
> K8s API에 외부 서버를 "확장"으로 연결.
> "external.metrics.k8s.io API 호출 → KEDA의 metrics-apiserver Pod로 라우팅" 등록.
> HPA가 `external` 타입 메트릭 쿼리 시 → K8s API → KEDA → 외부 시스템 → 값 반환.
>
> `True` = KEDA Pod이 정상 응답. `False` 면 KEDA 죽었거나 API 매핑 깨짐.

## 6. 학습 확인 질문

1. KEDA 가 만든 metrics-server (apiservice) 의 역할은?
2. Helm 설치 시 `podIdentity.aws.irsa.enabled=true` 옵션은 무엇을 가능하게 하는가?
3. KEDA Operator 와 metrics-apiserver 가 분리된 이유는?

> **힌트**:
> 1. HPA가 외부 메트릭(SQS 큐 길이 등)을 쿼리할 수 있게 해주는 K8s API extension. KEDA가 외부 시스템을 폴링해 값 반환.
> 2. AWS 트리거(SQS 등)의 인증을 IRSA로 가능하게. TriggerAuthentication에 `podIdentity: {provider: aws}` 사용 가능.
> 3. metrics-apiserver는 K8s API extension으로 안정성 중요. Operator 죽어도 HPA가 메트릭 못 받으면 즉시 잘못된 결정 → 분리해서 격리.

다음: [lab-02-cpu-scaler.md](./lab-02-cpu-scaler.md)
