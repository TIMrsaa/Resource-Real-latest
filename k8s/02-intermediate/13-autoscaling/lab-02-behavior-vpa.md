# Lab 02 — behavior 튜닝과 VPA 권고 모드

## Step 1. behavior로 "감축 속도 제한" 걸기

시나리오: 콜드스타트가 비싼 앱이라 감축을 매우 보수적으로 — "10분 안정화 + 분당 1개씩만".

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: php-apache }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: php-apache }
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource: { name: cpu, target: { type: Utilization, averageUtilization: 50 } }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies: [{ type: Percent, value: 100, periodSeconds: 15 }]
    scaleDown:
      stabilizationWindowSeconds: 600          # 10분
      policies: [{ type: Pods, value: 1, periodSeconds: 60 }]   # 분당 1개
EOF
```

부하를 1~2분 줘서 5개 이상으로 늘린 뒤 끊고, `kubectl get hpa -w`로 감축 곡선을 관찰하세요:

```bash
kubectl run load-gen --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://php-apache >/dev/null; done'
sleep 120 && kubectl delete pod load-gen
kubectl get hpa php-apache -w
```

예상: 10분 대기 후 **7→6→5→...** 처럼 분당 1개씩 계단형 감축. lab-01의 기본 동작(5분 후 한 번에)과 비교.

✅ behavior는 "스케일링의 성격"을 코드로 적는 곳입니다. 워크로드마다 다르게: 배치 워커는 공격적 감축, 유저 대면 API는 보수적 감축.

## Step 2. VPA 설치 (권고 모드)

```bash
git clone --depth 1 https://github.com/kubernetes/autoscaler.git /tmp/autoscaler
cd /tmp/autoscaler/vertical-pod-autoscaler && ./hack/vpa-up.sh
kubectl get pods -n kube-system | grep vpa
```

예상: vpa-recommender / vpa-updater / vpa-admission-controller 3개 Running.

## Step 3. 권고값 받아보기

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: { name: php-apache-vpa }
spec:
  targetRef: { apiVersion: apps/v1, kind: Deployment, name: php-apache }
  updatePolicy: { updateMode: "Off" }       # 권고만!
EOF

# 부하를 2~3분 주고 (recommender가 데이터를 모으도록)
kubectl run load-gen --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://php-apache >/dev/null; done'
sleep 180
kubectl describe vpa php-apache-vpa | grep -A 12 "Recommendation"
kubectl delete pod load-gen
```

예상 출력 (발췌):
```
Recommendation:
  Container Recommendations:
    Container Name:  hpa-example
    Lower Bound:   Cpu: 130m  Memory: 26Mi
    Target:        Cpu: 487m  Memory: 26Mi     ← "requests를 이 정도로 잡아라"
    Upper Bound:   Cpu: 1     Memory: 50Mi
```

✅ 우리가 임의로 잡은 200m 대비 **실측 기반 권고**가 나왔습니다. 운영에서의 쓰임: 분기마다 VPA(Off) 권고로 전 서비스 requests를 재조정(rightsizing) → 노드 비용 직결 (모듈 37, eks 파트 22).

> ⚠️ updateMode를 Auto로 바꾸면 권고 적용을 위해 Pod를 재시작합니다. 그리고 이 Deployment에는 CPU HPA가 걸려 있으므로 **CPU VPA Auto와 동시 사용 금지** — 핸들 두 개 문제(theory §3).

## Step 4. 미니 설계 과제 (스스로)

다음 워크로드의 (HPA/VPA/behavior) 설계를 적어보세요:
1. 아침 9시에 트래픽이 10배 뛰는 사내 포털 — (힌트: HPA만으론 9시 스파이크를 못 받습니다 → 예약 스케일링/KEDA cron 병용)
2. 큐를 소비하는 야간 배치 워커 — (힌트: CPU가 아니라 **큐 길이**가 신호. KEDA. 감축은 공격적으로, 0까지)
3. 메모리 누수가 있는 레거시 — (힌트: 메모리 HPA는 오답. limit+재시작은 임시방편, VPA Off로 추세 관찰)

## 정리

```bash
bash cleanup.sh
```
