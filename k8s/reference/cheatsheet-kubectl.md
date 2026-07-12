# kubectl 치트시트 (v1.36 기준)

## 기본 조회
```bash
kubectl get pods                          # 현재 네임스페이스 Pod 목록
kubectl get pods -A                       # 모든 네임스페이스
kubectl get pods -o wide                  # 노드/IP 포함
kubectl get pods -w                       # 실시간 감시 (watch)
kubectl get pods --show-labels            # 라벨 표시
kubectl get pods -l app=web,tier!=db      # 라벨 셀렉터
kubectl get pods --field-selector status.phase=Running
kubectl get events --sort-by=.lastTimestamp   # 최근 이벤트 (디버깅 1순위)
```

## 상세/문서
```bash
kubectl describe pod <name>               # 이벤트 포함 상세 (디버깅 2순위)
kubectl explain deployment.spec.strategy  # 필드 문서 즉석 조회
kubectl explain pod.spec --recursive      # 전체 필드 트리
kubectl api-resources                     # 모든 리소스 종류 + 축약어
kubectl api-versions                      # 사용 가능한 API 버전
```

## 출력 가공
```bash
kubectl get pods -o yaml                  # 전체 YAML
kubectl get pods -o json | jq '.items[].metadata.name'
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
kubectl get pods --sort-by=.metadata.creationTimestamp
```

## 생성/변경
```bash
kubectl apply -f app.yaml                 # 선언적 적용 (표준)
kubectl apply -f dir/ -R                  # 디렉터리 재귀 적용
kubectl diff -f app.yaml                  # 적용 전 차이 미리보기
kubectl apply --server-side -f app.yaml   # Server-Side Apply
kubectl create deployment web --image=nginx --dry-run=client -o yaml  # YAML 뼈대 생성
kubectl set image deployment/web web=nginx:1.27
kubectl scale deployment web --replicas=5
kubectl patch deployment web -p '{"spec":{"replicas":3}}'
kubectl edit deployment web               # 에디터로 직접 수정
kubectl label pod <name> env=prod         # 라벨 추가 (제거: env-)
kubectl annotate pod <name> note="test"
```

## 롤아웃
```bash
kubectl rollout status deployment/web
kubectl rollout history deployment/web
kubectl rollout undo deployment/web                 # 롤백
kubectl rollout undo deployment/web --to-revision=2
kubectl rollout restart deployment/web              # 재시작 (이미지 재pull)
kubectl rollout pause/resume deployment/web
```

## 디버깅
```bash
kubectl logs <pod>                        # 로그
kubectl logs <pod> -c <container> -f --tail=100
kubectl logs <pod> --previous             # 죽기 전 컨테이너 로그 (CrashLoop 필수)
kubectl exec -it <pod> -- sh              # 셸 진입
kubectl debug <pod> -it --image=busybox --target=<container>  # 임시(ephemeral) 컨테이너 주입
kubectl debug node/<node> -it --image=busybox                  # 노드 디버깅
kubectl port-forward svc/web 8080:80      # 로컬→클러스터 포트 연결
kubectl cp <pod>:/path ./local            # 파일 복사
kubectl top pods / kubectl top nodes      # 리소스 사용량 (metrics-server 필요)
kubectl auth can-i delete pods --as=dev-user   # 권한 확인
```

## 컨텍스트/네임스페이스
```bash
kubectl config get-contexts
kubectl config use-context <ctx>
kubectl config set-context --current --namespace=dev
```

## 자주 쓰는 조합
```bash
# 안 뜨는 Pod 원인 한 번에
kubectl get pod <p> -o wide && kubectl describe pod <p> | tail -20 && kubectl logs <p> --previous --tail=20

# 모든 리소스 한눈에
kubectl get all,cm,secret,ing,pvc -n <ns>

# 강제 삭제 (Terminating에 갇혔을 때 — 원인 파악 후 최후수단)
kubectl delete pod <p> --grace-period=0 --force
```
