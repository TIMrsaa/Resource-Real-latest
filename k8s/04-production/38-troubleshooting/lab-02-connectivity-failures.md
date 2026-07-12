# Lab 02 — 연결/플랫폼 장애 5선

> lab-01의 dr-lab ns + web Deployment(수리된 상태)에서 계속.

## 시나리오 6. DNS — "이름만" 안 풀립니다

재현(안전하게): CoreDNS를 끄는 대신, **dnsPolicy가 깨진 Pod**로 같은 증상을 만듭니다:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: baddns
  namespace: dr-lab
  labels: { run: baddns }
spec:
  dnsPolicy: "None"                          # 클러스터 DNS를 버리고
  dnsConfig:
    nameservers: ["10.255.255.1"]            # 죽은 네임서버를 지정 (고장 재현)
  containers:
    - name: baddns
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
EOF
kubectl exec baddns -n dr-lab -- wget -qO- -T3 http://web 2>&1 | tail -1        # bad address
SVC_IP=$(kubectl get svc web -n dr-lab -o jsonpath='{.spec.clusterIP}')
kubectl exec baddns -n dr-lab -- wget -qO- -T3 http://$SVC_IP/hostname          # IP로는 됨!
```

루틴 추적:
```bash
kubectl exec baddns -n dr-lab -- nslookup web 2>&1 | tail -2      # 실패 — DNS 확정
kubectl exec baddns -n dr-lab -- cat /etc/resolv.conf             # nameserver가 엉뚱한 곳
```

✅ **교훈**: "IP로는 되고 이름만 안 됨" = 100% DNS. 분기: resolv.conf가 정상(10.100.0.10)인데 안 되면 CoreDNS 쪽(`kubectl -n kube-system get pods -l k8s-app=kube-dns`, 모듈 16), resolv.conf 자체가 이상하면 Pod의 dnsPolicy/dnsConfig.

## 시나리오 7. Service 연결 불가 — 셀렉터 불일치

```bash
# 운영자가 Service를 "고친다"며 셀렉터에 오타
kubectl patch svc web -n dr-lab -p '{"spec":{"selector":{"app":"webb"}}}'
kubectl run probe -n dr-lab --rm -it --restart=Never --image=public.ecr.aws/docker/library/busybox:stable \
  -- wget -qO- -T3 http://web/hostname 2>&1 | tail -1     # timeout
```

루틴 추적 (분기점 명령 먼저):
```bash
kubectl get endpoints web -n dr-lab                        # <none> → Service 쪽 문제
kubectl get svc web -n dr-lab -o jsonpath='{.spec.selector}'; echo
kubectl get pods -n dr-lab -l app=web --show-labels        # 라벨은 app=web — 불일치 발견
```

수리 + 검증:
```bash
kubectl patch svc web -n dr-lab -p '{"spec":{"selector":{"app":"web"}}}'
kubectl get endpoints web -n dr-lab                        # 복구
```

✅ **교훈**: endpoints `<none>`의 2대 원인 — ① 셀렉터-라벨 불일치(지금) ② 전원 NotReady(lab-01 시나리오 5). 셀렉터는 **오타가 에러가 아니라 침묵**이 되는 필드입니다 — 배포 후 endpoints 확인을 루틴에.

## 시나리오 8. NetworkPolicy — IP로도 안 됩니다

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: lockdown, namespace: dr-lab }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: [Ingress]
  ingress:
  - from: [{ podSelector: { matchLabels: { role: client } } }]
EOF
kubectl run probe -n dr-lab --rm -it --restart=Never --image=public.ecr.aws/docker/library/busybox:stable \
  -- sh -c "wget -qO- -T3 http://web/hostname || echo BLOCKED"
```

루틴 추적:
```bash
kubectl get endpoints web -n dr-lab          # 차 있음 → Service 정상, 경로 문제
kubectl exec -n dr-lab deploy/web -- true && echo "Pod 살아있음"
kubectl get netpol -n dr-lab                 # ← lockdown 발견
kubectl describe netpol lockdown -n dr-lab | grep -A3 From
```

수리(차단이 의도가 아니라면 라벨 충족):
```bash
kubectl run probe -n dr-lab --rm -it --restart=Never --labels=role=client \
  --image=public.ecr.aws/docker/library/busybox:stable -- wget -qO- -T3 http://web/hostname
```

✅ **교훈**: endpoints가 **차 있는데** 안 되면 경로 수사: NetworkPolicy → 포트 → (EKS) SG. "어제까지 됐는데" 류는 최근 추가된 netpol부터 — `kubectl get netpol -A --sort-by=.metadata.creationTimestamp`.

## 시나리오 9. PVC Pending

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: dr-lab }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-typo        # 없는 StorageClass
  resources: { requests: { storage: 1Gi } }
EOF
kubectl get pvc -n dr-lab           # Pending
```

루틴 추적:
```bash
kubectl describe pvc data -n dr-lab | tail -3
# → storageclass.storage.k8s.io "gp3-typo" not found
kubectl get storageclass            # 진짜 이름 확인
```

✅ **교훈**: PVC Pending의 3대 원인 — ① SC 이름 오타/부재(지금) ② WaitForFirstConsumer인데 **Pod가 아직 없음**(정상 대기! 모듈 08) ③ 용량/한도. describe 한 방이 셋을 가릅니다.

```bash
kubectl delete pvc data -n dr-lab
```

## 시나리오 10. 노드 이상 — 직접 깨지 않고 읽는 법

공유 클러스터의 노드를 진짜 깨지 않고, **진단 루틴**만 정확히:

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
# ① Conditions — 노드의 활력 징후 5종
kubectl describe node $NODE | grep -A8 "Conditions:"
# Ready=True 외에 MemoryPressure/DiskPressure/PIDPressure=False 가 정상
# ② 노드 이벤트 (kubelet의 호소)
kubectl get events --field-selector involvedObject.name=$NODE --sort-by=.lastTimestamp | tail -5
# ③ kubelet까지 내려가기 (모듈 26의 도구)
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable -- \
  chroot /host sh -c 'systemctl is-active kubelet; df -h / | tail -1'
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
```

✅ **교훈**: NotReady의 수사선 — Conditions(어떤 압박?) → 이벤트 → 노드 안(kubelet 살았나, 디스크 찼나). DiskPressure는 이미지/로그 청소(GC), NotReady+NetworkUnavailable은 CNI(모듈 27)가 다음 용의자.

## 마무리 — 진단 카드 완성

theory §4의 카드에 오늘의 실측(걸린 시간, 막힌 곳)을 채워 자기 버전으로 — 운영 위키의 첫 페이지에 둘 물건입니다.

```bash
bash cleanup.sh
```
