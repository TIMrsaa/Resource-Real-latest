# kubectl 치트시트

## 컨텍스트 / 네임스페이스

```bash
kubectl config get-contexts                              # 컨텍스트 목록
kubectl config use-context <name>                        # 컨텍스트 전환
kubectl config current-context                           # 현재 컨텍스트
kubectl config set-context --current --namespace=<ns>    # 기본 NS 변경
kubectl get ns                                           # 네임스페이스 목록
```

## 리소스 조회 (get)

```bash
kubectl get pods                                         # 현재 NS Pod
kubectl get pods -A                                      # 전체 NS
kubectl get pods -n kube-system                          # 특정 NS
kubectl get pods -o wide                                 # 노드/IP 추가 정보
kubectl get pods -o yaml                                 # 전체 YAML
kubectl get pods -l app=nginx                            # 라벨 셀렉터
kubectl get pods --field-selector status.phase=Running
kubectl get pods --watch                                 # 실시간 변화
kubectl get all                                          # Deployment/Service/Pod 등 일괄
```

## 상세 정보 (describe / explain)

```bash
kubectl describe pod <name>                              # 이벤트 + 상태
kubectl describe node <name>
kubectl explain pod                                      # 스키마 설명
kubectl explain pod.spec.containers.resources --recursive
```

## 로그 / 셸 / 포워드

```bash
kubectl logs <pod>                                       # 로그
kubectl logs <pod> -c <container>                        # 멀티 컨테이너
kubectl logs <pod> -f                                    # follow
kubectl logs <pod> --previous                            # 이전 인스턴스
kubectl logs -l app=nginx --all-containers --tail=50

kubectl exec -it <pod> -- sh                             # 셸 진입
kubectl exec <pod> -- ls /etc

kubectl port-forward pod/<pod> 8080:80                   # 로컬 포트로 포워드
kubectl port-forward svc/<svc> 8080:80
```

## 적용 / 삭제

```bash
kubectl apply -f manifest.yaml
kubectl apply -f ./manifests/                            # 디렉토리
kubectl apply -k ./overlays/dev                          # kustomize
kubectl delete -f manifest.yaml
kubectl delete pod <name> --grace-period=0 --force       # 강제 삭제
```

## Deployment 운영

```bash
kubectl rollout status deploy/<name>
kubectl rollout history deploy/<name>
kubectl rollout undo deploy/<name>                       # 롤백
kubectl rollout restart deploy/<name>                    # Pod 재시작
kubectl scale deploy/<name> --replicas=5
kubectl set image deploy/<name> <ctr>=<image>:<tag>
```

## 디버깅

```bash
kubectl get events --sort-by='.lastTimestamp'
kubectl get events --field-selector involvedObject.name=<pod>
kubectl top pods                                         # CPU/Mem (metrics-server 필요)
kubectl top nodes
kubectl debug node/<node> -it --image=ubuntu             # 노드 진단
kubectl debug -it <pod> --image=busybox --target=<ctr>   # ephemeral container
```

## JSON path 출력

```bash
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu
```

## 자원 사용 (top)

```bash
kubectl top pod -A --sort-by=memory
kubectl top node --sort-by=cpu
```

## 기타 유용한 명령

```bash
kubectl get pod <name> -o yaml | yq '.spec.containers[0].image'
kubectl run dbg --rm -it --image=alpine -- sh            # 임시 디버그 Pod
kubectl auth can-i list pods                             # RBAC 점검
kubectl api-resources                                    # 사용 가능한 리소스 목록
kubectl version --output=yaml
```

## alias 추천

```bash
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
alias kn='kubectl config set-context --current --namespace'
```
