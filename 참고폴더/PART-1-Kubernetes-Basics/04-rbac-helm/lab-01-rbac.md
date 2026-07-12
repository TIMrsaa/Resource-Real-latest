# Lab 01 — RBAC 으로 제한된 SA 만들기

## 학습 확인 포인트

- [ ] ServiceAccount 가 자체 토큰을 가지고 있음을 확인했다
- [ ] Role/RoleBinding 으로 권한이 부여되는 흐름을 봤다
- [ ] 권한 없는 행동을 시도했을 때 `Forbidden` 응답을 받아봤다

> **🌱 핵심 개념 미리보기**
> - **ServiceAccount (SA)**: Pod이 K8s API를 호출할 때 쓰는 신원. 사용자(IAM) 가 아니라 워크로드용.
> - **Role / ClusterRole**: 권한 묶음 정의 (어떤 리소스에 어떤 verb 허용?). Role은 NS 한정, ClusterRole은 전체.
> - **RoleBinding / ClusterRoleBinding**: Role을 SA/User/Group 에게 연결하는 객체.
> - **Forbidden**: 권한 부족 시 K8s가 반환하는 에러. 보안의 기본 — 명시적으로 부여한 것만 허용.
> - **EKS의 추가 한 단계**: IAM 사용자/역할 → K8s 신원 매핑이 추가로 필요 (aws-auth ConfigMap or Access Entries).

## 1. RBAC 리소스 적용

```bash
kubectl apply -f manifests/rbac.yaml
kubectl get sa,role,rolebinding,pod
```

## 2. 권한 점검 (`auth can-i`)

```bash
SA="system:serviceaccount:default:pod-reader-sa"
kubectl auth can-i list pods --as=$SA              # yes
kubectl auth can-i get pods --as=$SA               # yes
kubectl auth can-i delete pods --as=$SA            # no
kubectl auth can-i list deployments --as=$SA       # no
kubectl auth can-i list pods -n kube-system --as=$SA  # no (다른 NS)
```

> **🧠 SA의 정식 이름은 `system:serviceaccount:<ns>:<sa>`**
> K8s 내부에선 SA를 이런 username 형태로 다룸 → `--as=` 로 흉내낼 때도 이 형식 필수.
> Group은 `system:serviceaccounts` (모든 SA), `system:serviceaccounts:<ns>` (특정 NS의 모든 SA) 자동 부여.
> 운영 디버깅: "이 Pod이 X 행동 가능?" 궁금하면 `kubectl auth can-i ... --as=system:serviceaccount:<ns>:<sa>` 로 즉시 확인.

## 3. Pod 안에서 직접 API 호출

`rbac-test` Pod는 `pod-reader-sa` 로 떠 있습니다. kubectl 컨테이너 안에서 직접 호출:

```bash
kubectl exec -it rbac-test -- sh

# 안에서 — Pod의 자동 마운트된 토큰을 kubectl이 사용
kubectl get pods                              # 성공
kubectl logs rbac-test                        # 성공 (자기 로그)
kubectl get deployments                       # 실패: Forbidden
kubectl get pods -n kube-system               # 실패: Forbidden
kubectl delete pod rbac-test                  # 실패: Forbidden

exit
```

## 4. Pod 내부의 토큰 위치

```bash
kubectl exec -it rbac-test -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

기대:
```
ca.crt
namespace
token
```

`token` 이 SA의 JWT. 자동으로 마운트되어 in-cluster K8s API 호출 시 사용됩니다.

> EKS 1.24+ 에서는 토큰이 **bound token** 으로 자동 갱신 (옛날엔 Secret으로 영구 토큰).

> **🧠 bound token이 뭐가 좋은가**
> 옛날 SA token은 Secret에 영구 저장 → 유출 시 영구 위험.
> bound token은 **시간(기본 1시간) + Pod UID + audience** 에 묶인 JWT. Pod 죽으면 무효화 + 자동 갱신 (kubelet이 처리).
> 운영 의미: Secret에 저장된 SA token 노출돼도 영향 작아짐 + 토큰 회전이 자동.

## 5. 권한 추가하기 (실험)

`pod-reader` Role을 수정해 `delete` 추가:

```bash
kubectl edit role pod-reader
# rules.verbs 에 "delete" 추가
```

다시 시도:
```bash
kubectl exec -it rbac-test -- kubectl delete pod rbac-test
```

기대: 자기 자신을 지움. (Pod이 사라지므로 다음 명령은 새 Pod 생성 필요)

## 6. ClusterRole 시나리오

```bash
kubectl auth can-i list nodes --as=$SA      # no (cluster-scoped, ClusterRole 필요)

# ClusterRole + ClusterRoleBinding 추가 (학습용)
kubectl create clusterrole node-reader --verb=get,list --resource=nodes
kubectl create clusterrolebinding pod-reader-sa-node-reader \
  --clusterrole=node-reader \
  --serviceaccount=default:pod-reader-sa

kubectl auth can-i list nodes --as=$SA      # yes
```

> **🧠 Role vs ClusterRole 선택 기준**
> - **Node, PersistentVolume, Namespace, ClusterRole 자체** 같은 cluster-scoped 리소스 → ClusterRole 필수.
> - **Pod, Service, Deployment 등 NS 안 리소스** → Role 권장 (NS 한정 = 최소 권한).
> - **NS 안 리소스인데 모든 NS 에 적용하고 싶을 때** → ClusterRole + ClusterRoleBinding (예: 모니터링 SA가 모든 NS Pod 읽기).
> 보안 원칙: 가능한 한 Role 부터 시도, 정말 필요할 때만 ClusterRole.

## 7. 정리

```bash
kubectl delete -f manifests/rbac.yaml
kubectl delete clusterrole node-reader --ignore-not-found
kubectl delete clusterrolebinding pod-reader-sa-node-reader --ignore-not-found
```

## 학습 확인 질문

1. `kubectl auth can-i ... --as=<user>` 에서 `<user>` 부분에 ServiceAccount를 지정하는 형식은?
2. RoleBinding 으로 ClusterRole 을 참조할 수 있는가? 가능하면 어떤 효과?
3. EKS에서 IAM 사용자/역할이 K8s API 권한을 갖게 되는 추가 단계는? (ConfigMap aws-auth 또는 EKS Access Entries)

다음: [lab-02-helm-chart.md](./lab-02-helm-chart.md)
