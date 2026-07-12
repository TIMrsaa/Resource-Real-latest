# 흔한 함정 5선 — 01. 핵심 개념

## 1. `ImagePullBackOff` / `ErrImagePull`

**증상**:
```
NAME           READY   STATUS             RESTARTS   AGE
my-pod         0/1     ImagePullBackOff   0          1m
```

**원인 후보**:
- 이미지 이름 오타 (가장 흔함)
- 사설 레지스트리 인증 누락 (ECR이면 노드 IAM Role에 `AmazonEC2ContainerRegistryReadOnly` 필요)
- 태그가 존재하지 않음 (`:latest` 외 정확한 태그 사용했는지)

**진단**:
```bash
kubectl describe pod <pod> | grep -A5 Events
```

`Failed to pull image` 라인의 정확한 에러 메시지 확인. ECR이면 노드 IAM Role 점검:
```bash
aws iam list-attached-role-policies --role-name <노드-인스턴스-역할>
```

---

## 2. `CrashLoopBackOff`

**증상**: Pod가 계속 재시작됨.

**원인 후보**:
- 컨테이너 시작 즉시 종료 (커맨드 잘못 / 환경변수 누락 / config 파일 미존재)
- liveness probe 실패 (probe 설정이 너무 빡빡)
- OOM (메모리 limit 초과로 컨테이너 강제 종료)

**진단**:
```bash
kubectl logs <pod>                     # 마지막 로그
kubectl logs <pod> --previous          # 죽기 직전 로그
kubectl describe pod <pod> | grep -A2 'State\|Last State\|Reason\|Exit Code'
```

`Exit Code 137` → OOMKilled 가능성. `Exit Code 1` → 앱 자체 에러.

---

## 3. `Pending` 상태에서 안 떠짐

**증상**: 몇 분이 지나도 Pod가 계속 `Pending`.

**원인 후보**:
- 노드 부족 (CPU/메모리 자원 모자람)
- nodeSelector / affinity / taint 매칭 노드 없음
- PVC 바인딩 대기 (StorageClass 문제)

**진단**:
```bash
kubectl describe pod <pod> | grep -A10 Events
# "FailedScheduling" 메시지의 이유 확인

kubectl describe nodes | grep -A5 'Allocated resources'
```

해결 방향:
- requests를 줄이거나, 노드를 추가 (Karpenter가 있으면 자동)
- nodeSelector / tolerations 검토

---

## 4. ReplicaSet이 Pod를 계속 만들었다 지웠다 함

**증상**: ReplicaSet의 Events에 `Created pod` 와 `Killed pod` 가 반복.

**원인 후보**:
- selector와 Pod 라벨 불일치 → ReplicaSet이 자기 Pod를 못 알아봄
- 다른 ReplicaSet/Deployment의 selector와 겹침 → 한 Pod를 두 컨트롤러가 다투어 관리

**진단**:
```bash
kubectl get rs <rs> -o yaml | yq '.spec.selector'
kubectl get pods --show-labels
```

`spec.selector.matchLabels` 가 Pod의 `metadata.labels` 에 모두 포함되는지 확인.

> **불변 필드 주의**: 일단 Deployment를 만든 뒤에는 `selector` 변경 불가. 라벨링 실수했다면 Deployment를 삭제하고 다시 만들어야 함.

---

## 5. 매니페스트 적용했는데 변경이 반영 안 됨

**증상**: `kubectl apply` 후 `kubectl get` 보면 그대로 같음.

**원인 후보**:
- 잘못된 NS에 적용 (`kubectl apply` 가 default NS로 들어감, 정작 보고 있는 건 다른 NS)
- 컨텍스트가 다른 클러스터를 가리킴
- 매니페스트 변경 부분이 **immutable field** (예: Service의 `clusterIP`, Deployment의 `selector`)

**진단**:
```bash
kubectl config current-context
kubectl get pods -A | grep <앱>             # 어느 NS에 떠 있는지
kubectl apply -f manifest.yaml --dry-run=server -o yaml | diff - <(kubectl get -f manifest.yaml -o yaml)
```

immutable 에러는 명시적 메시지가 나옵니다:
```
The Deployment "web" is invalid: spec.selector: Invalid value: ...: field is immutable
```

이 경우 삭제 후 재생성 필요.
