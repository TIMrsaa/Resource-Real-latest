# Lab 01 — HPA 부하 실험: 식이 맞는지 검증합니다

## Step 0. 파이프라인 확인

```bash
kubectl top nodes
```

예상: 노드별 CPU/메모리 사용량 표. 에러가 나면 metrics-server 미설치 — `kubectl get deploy -n kube-system metrics-server` 확인.

## Step 1. 대상 앱 + HPA 배포

```bash
# CPU를 실제로 태우는 PHP 데모 앱 (공식 HPA 튜토리얼 이미지)
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
  labels: { app: php-apache }
spec:
  replicas: 1
  selector:
    matchLabels: { app: php-apache }
  template:
    metadata:
      labels: { app: php-apache }
    spec:
      containers:
        - name: hpa-example
          image: registry.k8s.io/hpa-example
          ports:
            - containerPort: 80
          resources:
            requests: { cpu: 200m }    # ★ 이게 없으면 HPA가 %를 계산 못 합니다 (pitfalls 1)
            limits: { cpu: 500m }
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
spec:
  selector: { app: php-apache }
  ports:
    - port: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
EOF
kubectl get hpa php-apache
```

예상 출력 (1~2분 후):
```
NAME         REFERENCE               TARGETS        MINPODS  MAXPODS  REPLICAS
php-apache   Deployment/php-apache   cpu: 0%/50%    1        10       1
```

> TARGETS가 `<unknown>/50%`로 계속 머물면: requests 누락 또는 metrics-server 문제 — pitfalls 1번.

## Step 2. 부하 발생

터미널 1 (감시):
```bash
kubectl get hpa php-apache -w
```

터미널 2 (부하 — 무한 wget 루프):
```bash
kubectl run load-gen --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://php-apache >/dev/null; done'
```

터미널 1 예상 출력 (시간순):
```
php-apache   cpu: 0%/50%     1
php-apache   cpu: 248%/50%   1        ← 부하 감지 (이용률 = 사용량/requests 라 100% 초과 가능!)
php-apache   cpu: 248%/50%   5        ← ceil(1×248/50)=5. 식 그대로!
php-apache   cpu: 65%/50%    5
php-apache   cpu: 48%/50%    7        ← 추가 보정
php-apache   cpu: 35%/50%    7        ← 목표 부근에서 안정
```

✅ **검증 포인트 2개**: ① 248% — 이용률 분모가 limits가 아니라 **requests**라는 증거(200m 기준 ~500m 사용) ② 1→5 점프가 정확히 `ceil(1×248/50)` — 이론의 식이 실측과 일치.

```bash
kubectl get events --sort-by=.lastTimestamp | grep -i horizontalpodautoscaler | tail -3
# → New size: 5; reason: cpu resource utilization above target
```

## Step 3. 부하 중단 → 감축의 "느림" 관찰

```bash
kubectl delete pod load-gen
date    # 중단 시각 기록
kubectl get hpa php-apache -w
```

예상: CPU는 수십 초 내 0%로 떨어지지만 REPLICAS는 **약 5분간 유지**되다가 줄어듭니다.

✅ scaleDown 안정화 창(기본 300s)의 실증. "왜 바로 안 줄어요?"는 버그가 아니라 설계입니다.

## Step 4. 식으로 예측하고 맞히기 (셀프 체크)

목표를 25%로 바꾸면 안정 상태 replicas는 몇이 될까요? 먼저 계산하고 실행:

```bash
kubectl patch hpa php-apache --type=merge -p '{"spec":{"metrics":[{"type":"Resource","resource":{"name":"cpu","target":{"type":"Utilization","averageUtilization":25}}}]}}'
# 부하 재시작 후 관찰
kubectl run load-gen --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://php-apache >/dev/null; done'
```

(예측: 총 CPU 수요 ~500m는 동일하므로 replicas ≈ 500m/(200m×25%) = 10 → max에 걸림)

```bash
kubectl delete pod load-gen
```

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| TARGETS `<unknown>` | requests 누락 / metrics-server 다운 / Pod 기동 직후(1~2분 대기) |
| 늘었는데 일부 Pending | 노드 용량 부족 — 3층(노드 스케일링)의 영역. maxReplicas 조정 또는 노드 증설 |
| 출렁임(올렸다 내렸습니다) | 허용 오차 부근 + 짧은 부하 — behavior로 제어 (lab-02) |

## 정리

php-apache는 lab-02에서 계속 사용.
