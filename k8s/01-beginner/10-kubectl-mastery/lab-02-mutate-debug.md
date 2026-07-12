# Lab 02 — 안전한 변경(diff/patch)과 debug

## Step 1. diff — 적용 전 리허설

```bash
kubectl get deploy trainer -o yaml > /tmp/trainer.yaml
sed -i 's/replicas: 3/replicas: 5/' /tmp/trainer.yaml
kubectl diff -f /tmp/trainer.yaml | head -20
```

예상 출력 (git diff 형식):
```
-  replicas: 3
+  replicas: 5
```

✅ **클러스터는 아직 안 바뀌었습니다.** "이 YAML 적용하면 뭐가 바뀌지?"를 0 리스크로 확인 — 운영 배포 전 습관 1순위.

```bash
# 서버 리허설 (admission/검증까지)
kubectl apply -f /tmp/trainer.yaml --dry-run=server
```

## Step 2. patch 3형식 실습

```bash
# strategic merge — 컨테이너 리스트에서 "이름 매칭"으로 병합해줌 (K8s 지능)
kubectl patch deploy trainer -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","imagePullPolicy":"IfNotPresent"}]}}}}'

# JSON patch — 배열 인덱스 정밀 수술
kubectl patch deploy trainer --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"MODE","value":"lab"}]}]'

kubectl get deploy trainer -o jsonpath='{.spec.template.spec.containers[0].env}'; echo
```

> 💡 strategic merge가 컨테이너 배열을 "통째 교체"하지 않고 이름으로 병합하는 것 — `kubectl explain` 문서의 `patchMergeKey` 메타데이터 덕분입니다. JSON merge(`--type=merge`)였다면 배열이 통째로 바뀝니다. 자동화 스크립트에서 형식 선택이 중요한 이유.

## Step 3. kubectl debug ① — 셸 없는 컨테이너에 침투

```bash
# distroless 흉내: 셸이 없는 정적 이미지
kubectl run no-shell --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- netexec --http-port=8080
kubectl wait --for=condition=Ready pod/no-shell

kubectl exec no-shell -it -- sh
```

예상: 실행 파일이 없거나 매우 제한적 — 일반적인 distroless라면 `exec` 자체가 실패합니다.

```bash
# 디버그 컨테이너 주입 (같은 Pod의 namespace에 합류)
kubectl debug -it no-shell --image=public.ecr.aws/docker/library/busybox:stable --target=no-shell -- sh
```

디버그 셸 안에서:
```sh
ps                          # ← target 컨테이너의 프로세스가 보입니다! (PID ns 공유)
wget -qO- localhost:8080/hostname   # ← NET ns 공유로 localhost 접근
exit
```

✅ **모듈 03의 namespace 이론이 디버깅 무기가 되는 순간.** ephemeral container는 Pod spec의 `ephemeralContainers` 필드에 기록되며 재시작되지 않는 일회용입니다:

```bash
kubectl get pod no-shell -o jsonpath='{.spec.ephemeralContainers[*].name}'; echo
```

## Step 4. kubectl debug ② — 사본으로 실험

```bash
# 원본은 건드리지 않고, 명령만 셸로 바꾼 사본 생성
kubectl debug no-shell -it --copy-to=no-shell-lab --container=no-shell \
  --image=public.ecr.aws/docker/library/busybox:stable -- sh
# (조사 후 exit)
kubectl delete pod no-shell-lab
```

운영 Pod에 손대지 않고 "같은 설정에서 이것저것 해보기" — 안전한 실험 패턴.

## Step 5. 이벤트와 로그의 마지막 정리

```bash
kubectl events --for=pod/no-shell           # 특정 객체의 이벤트만 (신형 events 명령)
kubectl logs deploy/trainer --tail=5        # Deployment 이름으로도 로그 가능 (Pod 하나 골라줌)
kubectl logs -l app=trainer --prefix --tail=2   # 라벨로 여러 Pod 로그 + 접두사
```

## Step 6. 종합 루틴 점검 (반사신경 테스트)

아래를 보지 않고 칠 수 있으면 초급 졸업:

```
안 뜨는 Pod → kubectl describe pod X → Events
죽는 Pod   → kubectl logs X --previous
막힌 Service → kubectl get endpointslices
필드 모름   → kubectl explain
적용 전     → kubectl diff -f
셸 없음     → kubectl debug --target
```

## 정리

```bash
kubectl delete deploy trainer; kubectl delete svc trainer
kubectl delete pod no-shell --ignore-not-found
rm -f /tmp/trainer.yaml
```
