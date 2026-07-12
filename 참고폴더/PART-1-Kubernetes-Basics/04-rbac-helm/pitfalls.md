# 흔한 함정 5선 — 04. RBAC & Helm

## 1. `default` SA에 너무 많은 권한 부여

**증상**: SA 명시 안 한 Pod 도 클러스터 전체를 조작.

**원인**: 옛 가이드/예제 따라 `cluster-admin` 을 default SA에 묶어버림.

**해결**: 각 워크로드는 자기 전용 SA + 최소 권한. `default` SA에는 추가 권한 부여 금지.

```bash
# 현재 default SA의 권한 점검
kubectl get rolebinding,clusterrolebinding -A \
  -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}: {.subjects}{"\n"}{end}' \
  | grep 'default'
```

---

## 2. Helm release 이름과 fullname 충돌

**증상**: `helm install order-service ./charts/order-service` 했는데 리소스 이름이 `order-service-order-service` 같이 이상함.

**원인**: `_helpers.tpl` 의 fullname 로직이 release 이름과 chart 이름이 다를 때 둘을 결합.

```
{{- if contains $name .Release.Name }}
{{- .Release.Name }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name }}
```

**해결**:
- release 이름과 chart 이름을 같게 (`helm install order-service ...`)
- 또는 `fullnameOverride: order-service` 를 values.yaml 에 명시

---

## 3. `helm upgrade` 시 immutable 필드 변경 에러

**증상**:
```
Error: UPGRADE FAILED: cannot patch "demo-order-service" with kind Deployment:
Deployment.apps "demo-order-service" is invalid: spec.selector: Invalid value: ...: field is immutable
```

**원인**: Deployment의 `selector` 는 한 번 만들면 변경 불가. 차트의 selectorLabels 함수를 수정하면 새 selector를 만들려고 하므로 충돌.

**해결**:
- helm uninstall 후 재설치
- 또는 selectorLabels 는 절대 변경하지 않는다 (`app.kubernetes.io/name` + `app.kubernetes.io/instance` 권장 표준)

---

## 4. RBAC가 적용되지 않는 듯한 착각

**증상**: Role을 만들고 RoleBinding 으로 SA를 묶었는데도 `Forbidden` 응답.

**원인 후보**:
- subjects의 `namespace:` 명시 누락 (다른 NS의 SA로 해석)
- `apiGroup`, `kind`, `name` 오타
- ClusterRole 이름과 Role 이름이 같아 헷갈림

**진단**:
```bash
kubectl describe rolebinding <name>
kubectl auth can-i ... --as=system:serviceaccount:<ns>:<sa>
```

`describe` 의 Subjects 와 RoleRef 가 정확한지 확인.

---

## 5. `metrics-server` 미설치로 HPA 가 항상 `<unknown>`

**증상**:
```
NAME              REFERENCE                  TARGETS       MINPODS  MAXPODS  REPLICAS
order-service     Deployment/order-service   <unknown>/50% 2        8        2
```

**원인**: HPA는 metrics-server 의 데이터를 사용. 기본 EKS는 metrics-server 미설치.

**해결**:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 일부 EKS 환경에서 추가 패치 필요 (kubelet 인증서)
kubectl patch deploy metrics-server -n kube-system --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}
]'
```

검증:
```bash
kubectl top nodes
kubectl top pods -A
```

`top` 이 잘 동작하면 HPA 도 데이터를 받습니다.
