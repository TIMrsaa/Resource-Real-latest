# Lab 02 — 제약 부딪히기와 3자 결정표 (초급 졸업 산출물)

## Step 1. DaemonSet은 오지 않습니다

```bash
kubectl get pods -n kube-system -o wide | grep -E "aws-node|kube-proxy" | grep fargate || echo "Fargate 노드엔 없음"
```

✅ 클러스터 전체 DaemonSet(aws-node 등)이 Fargate "노드"엔 **하나도 없습니다** — 설 자리(진짜 노드)가 없으므로. 노드 에이전트형 도구(보안/모니터링)는 전부 사이드카로 전환해야 한다는 뜻.

## Step 2. EBS는 거절당합니다

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: ebs-try, namespace: serverless }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3          # k8s 08의 EBS 클래스
  resources: { requests: { storage: 1Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: ebs-pod, namespace: serverless }
spec:
  volumes: [{ name: d, persistentVolumeClaim: { claimName: ebs-try } }]
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sleep, "600"]
    volumeMounts: [{ name: d, mountPath: /data }]
EOF
sleep 30; kubectl describe pod ebs-pod -n serverless | tail -4
```

예상: Pending — 이벤트에 Fargate/볼륨 비호환 사유.

✅ **블록 스토리지(EBS)는 Fargate와 평생 평행선** — 상태 워크로드(k8s 19)는 EFS(공유 파일 — 10)로 가거나, 애초에 Fargate가 아닌 곳으로. 이 한 방이 "DB를 Fargate에?"라는 질문의 답입니다.

```bash
kubectl delete pod ebs-pod -n serverless; kubectl delete pvc ebs-try -n serverless
```

## Step 3. 호스트 의존도 거절당합니다

```bash
kubectl apply -f - 2>&1 <<'EOF' | tail -1
apiVersion: v1
kind: Pod
metadata:
  name: host-try
  namespace: serverless
  labels: { run: host-try }
spec:
  hostNetwork: true                # ← Fargate가 지원 안 하는 요구 (거부 확인용)
  containers:
    - name: host-try
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "60"]
EOF
```

✅ hostNetwork/hostPath/privileged 계열은 스케줄 거부 — "호스트가 없다"의 자연 귀결이자, 보안 관점에선 **k8s 32에서 위험하다고 배운 것들이 원천 봉쇄된 환경**이라는 뜻 (Fargate가 규제 워크로드에 강한 이유의 다른 면).

## Step 4. 격리의 증명 — 커널이 다릅니다

```bash
# Fargate Pod와 일반 노드 Pod의 커널 부팅 시각/uname 비교
kubectl exec -n serverless deploy/capsule -- uname -r
kubectl run normal-probe --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- sleep 60
kubectl wait --for=condition=Ready pod/normal-probe --timeout=60s
kubectl exec normal-probe -- uname -r
kubectl exec normal-probe -- sh -c 'cat /proc/uptime'      # 노드 커널의 uptime (깁니다)
kubectl exec -n serverless deploy/capsule -- sh -c 'cat /proc/uptime'   # Pod 수명과 비슷 (짧습니다!)
```

✅ Fargate Pod의 `/proc/uptime`이 Pod 나이와 비슷하다 = **이 커널은 이 Pod를 위해 태어났습니다** — k8s 01의 "컨테이너는 커널을 공유한다"가 Fargate에선 거짓이 되는 순간. VM 격리의 직접 증거.

## Step 5. 3자 결정표 완성 (초급 졸업 산출물)

워크로드 6종을 배치해보세요 (정답은 아래):

```markdown
# 컴퓨팅 결정표 — 우리 클러스터
| 워크로드 | 노드그룹 / Auto Mode / Fargate | 근거 |
|----------|-------------------------------|------|
| ① 표준 웹 API (상시, 중규모) | | |
| ② PostgreSQL (EBS, 고정 자원) | | |
| ③ 야간 정산 배치 (하루 2시간) | | |
| ④ 테넌트별 코드 실행 (보안 격리 절실) | | |
| ⑤ GPU 추론 서버 | | |
| ⑥ 노드 보안 에이전트 (DaemonSet) | | |
```

권장 답:
- ① **Auto Mode** (표준의 기본값 — 04) 또는 노드그룹
- ② **노드그룹**(EBS+고정 — Fargate 불가, 19의 StatefulSet 풀) / Auto Mode도 가능
- ③ **Fargate** (간헐 — Pod 단위 과금의 승리) 또는 Auto Mode+Spot
- ④ **Fargate** (VM 격리가 결정타)
- ⑤ **노드그룹** (GPU — Fargate 불가, Auto Mode는 지원 범위 확인 — 19)
- ⑥ **노드그룹/Auto Mode에만 존재 가능** — Fargate엔 못 간다는 사실 자체가 답

## 정리

```bash
bash cleanup.sh
```

**초급 트랙(01~06) 수료** — 다음은 중급: VPC CNI의 IP 경제학(07)부터.
