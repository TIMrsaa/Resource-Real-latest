# Lab 02 — 부하 중 배포로 무중단 검증 (에러 0 만들기)

> **방법론**: 클라이언트로 초당 수십 요청을 계속 보내면서 롤링 업데이트를 수행하고, 에러 수를 셉니다. "무중단"을 주장이 아니라 측정으로.

## Step 0. 부하 클라이언트 준비

```bash
# 1초에 약 20회 호출하며 실패만 출력하는 루프
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: loader
  labels: { run: loader }
spec:
  containers:
    - name: loader
      image: public.ecr.aws/docker/library/busybox:stable
      command:
        - sh
        - -c
        - |
          i=0; fail=0
          while true; do
            i=$((i+1))
            wget -q -T 2 -O- http://probe-demo/hostname >/dev/null 2>&1 || { fail=$((fail+1)); echo "FAIL #$fail (req $i)"; }
            [ $((i % 200)) -eq 0 ] && echo "progress: $i reqs, $fail fails"
            sleep 0.05
          done
EOF
kubectl wait --for=condition=Ready pod/loader
kubectl logs loader -f &      # 백그라운드로 로그 감시
```

## Step 1. 대조군 — 보호장치 없는 배포

probe-demo에서 readiness를 제거하고 preStop 없이 재배포해봅니다:

```bash
kubectl patch deploy probe-demo --type=json -p='[{"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}]'
kubectl rollout restart deploy/probe-demo && kubectl rollout status deploy/probe-demo
sleep 5
```

예상 loader 로그: `FAIL #N ...` 이 몇 건 찍힙니다 — ① 새 Pod가 준비 전에 트래픽 수신 ② 옛 Pod 종료 레이스.

## Step 2. 실험군 — 풀 세트 장착

```bash
kubectl patch deploy probe-demo --type=json -p='[
 {"op":"add","path":"/spec/template/spec/containers/0/readinessProbe","value":{"httpGet":{"path":"/healthz","port":8080},"periodSeconds":2}},
 {"op":"add","path":"/spec/template/spec/containers/0/lifecycle","value":{"preStop":{"exec":{"command":["sh","-c","sleep 5"]}}}},
 {"op":"add","path":"/spec/template/spec/terminationGracePeriodSeconds","value":30},
 {"op":"replace","path":"/spec/strategy","value":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}]'
kubectl rollout status deploy/probe-demo
```

> agnhost의 netexec은 SIGTERM을 받으면 정상 종료(drain)합니다 — 앱 측 요건은 이미 충족. 자기 앱이라면 SIGTERM 핸들러가 이 역할.

## Step 3. 부하 중 재배포 — 측정

```bash
# loader 로그 카운터 리셋 대신 기준점 기록
kubectl logs loader --tail=1
kubectl rollout restart deploy/probe-demo && kubectl rollout status deploy/probe-demo
sleep 10
kubectl logs loader --tail=3
```

예상 출력:
```
progress: 3400 reqs, 4 fails     ← Step 1에서 난 실패 그대로 (증가 없음)
progress: 3600 reqs, 4 fails     ← 배포를 거쳤는데 fail 카운트 동결!
```

✅ **에러 0 배포 달성.** 작동한 조각들: readiness(새 Pod 준비 후 명단 등재) + maxUnavailable=0(정원 유지) + preStop sleep(명단 제거 전파 대기) + SIGTERM drain(진행 중 요청 완료).

## Step 4. 조각 하나씩 빼보기 (선택 심화)

각각 제거하고 재배포하며 어떤 종류의 실패가 다시 생기는지 관찰하면, 각 조각의 역할이 신체 감각으로 남습니다:

| 빼는 것 | 다시 생기는 실패 |
|---------|-----------------|
| readiness | 배포 초반 연속 실패 (준비 안 된 Pod) |
| preStop sleep | 배포 후반 간헐 connection refused (레이스) |
| maxUnavailable=0 | 용량 부족 순간의 타임아웃 |

## Step 5. 내 앱 체크리스트 (가져갈 것)

```
[ ] readinessProbe — 의존성 포함 "지금 처리 가능?" 엔드포인트
[ ] livenessProbe — 재시작으로 풀리는 것만, 의존성 제외, 보수적 threshold
[ ] (느린 기동) startupProbe
[ ] 앱: SIGTERM → 신규 거부 + drain + 종료
[ ] preStop: sleep 5~15 (LB 전파 시간; ALB/NLB는 deregistration delay 고려)
[ ] terminationGracePeriodSeconds ≥ preStop + 최장 요청 처리 시간
[ ] strategy: maxUnavailable=0 (유저 대면)
```

## 정리

```bash
bash cleanup.sh
```
