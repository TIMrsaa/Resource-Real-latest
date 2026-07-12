# Lab 01 — 탐색(explain)과 추출(jsonpath) 훈련

## Step 0. 훈련용 리소스

```bash
kubectl create deployment trainer --image=public.ecr.aws/nginx/nginx:1.27 --replicas=3
kubectl expose deployment trainer --port=80
kubectl wait --for=condition=Available deployment/trainer
```

## Step 1. explain 5연속 — 문서 없이 살아남기

각 질문을 explain만으로 답하세요:

```bash
# Q1. Deployment 롤링 업데이트에서 maxSurge의 기본값은?
kubectl explain deployment.spec.strategy.rollingUpdate.maxSurge
# Q2. Pod에 호스트 네트워크를 쓰게 하는 필드는?
kubectl explain pod.spec | grep -i host
# Q3. probe의 종류(필드)들은?
kubectl explain pod.spec.containers.livenessProbe
# Q4. Service의 sessionAffinity에 들어갈 수 있는 값은?
kubectl explain service.spec.sessionAffinity
# Q5. (심화) HPA v2의 메트릭 타입 종류는?
kubectl explain hpa.spec.metrics --api-version=autoscaling/v2
```

✅ 답이 화면에 다 나옵니다. **인터넷 검색보다 빠르고, 클러스터 버전과 정확히 일치하는 문서**라는 것이 포인트.

## Step 2. jsonpath 단계별 훈련

```bash
# 레벨 1: 단일 값
kubectl get deploy trainer -o jsonpath='{.spec.replicas}'; echo

# 레벨 2: 배열 전개
kubectl get pods -l app=trainer -o jsonpath='{.items[*].metadata.name}'; echo

# 레벨 3: range로 표 만들기
kubectl get pods -l app=trainer \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\t"}{.status.podIP}{"\n"}{end}'

# 레벨 4: 필터 — 특정 조건만
kubectl get pods -l app=trainer \
  -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}'; echo

# 레벨 5: 실전 조합 — 모든 노드의 InternalIP
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
```

## Step 3. custom-columns와 sort-by

```bash
# 재시작 횟수 내림차순 — "문제아 찾기" 실전 쿼리
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount' \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,RESTARTS:'.status.containerStatuses[0].restartCount' | tail -5

# 이미지 인벤토리 — "우리 클러스터에 뭐가 도나"
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort | uniq -c | sort -rn
```

## Step 4. 미니 과제 (스스로)

jsonpath/columns만으로 만들어보세요 (정답은 시도 후에 만들기):
1. trainer Pod들의 "이름 / QoS 클래스" 2열 표
2. 클러스터 전체에서 requests.cpu가 없는 컨테이너를 가진 Pod 이름 목록 (힌트: jq가 더 쉽습니다)
3. 각 노드별 Pod 수 (힌트: `--field-selector spec.nodeName=` 반복 또는 jq group_by)

## 정리

trainer는 lab-02에서 계속 사용.
