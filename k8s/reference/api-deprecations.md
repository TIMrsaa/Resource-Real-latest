# API 폐기(Deprecation) 이력표 — 옛 자료를 볼 때 주의할 것들

> 인터넷의 오래된 튜토리얼을 따라 하다 `no matches for kind ...` 에러가 나면 이 표를 보라.

| 옛 API (쓰면 안 됨) | 현재 API | 제거 버전 |
|---------------------|----------|-----------|
| `extensions/v1beta1` Deployment/DaemonSet/ReplicaSet | `apps/v1` | 1.16 |
| `extensions/v1beta1`, `networking.k8s.io/v1beta1` Ingress | `networking.k8s.io/v1` | 1.22 |
| `rbac.authorization.k8s.io/v1beta1` | `rbac.authorization.k8s.io/v1` | 1.22 |
| `batch/v1beta1` CronJob | `batch/v1` | 1.25 |
| `policy/v1beta1` PodDisruptionBudget | `policy/v1` | 1.25 |
| `policy/v1beta1` **PodSecurityPolicy (PSP)** | **Pod Security Admission** (대체 개념) | 1.25 |
| `autoscaling/v2beta2` HPA | `autoscaling/v2` | 1.26 |
| `flowcontrol.apiserver.k8s.io/v1beta3` | `flowcontrol.apiserver.k8s.io/v1` | 1.32 |

## 개념 수준의 세대교체 (옛 자료 → 현재)

| 옛 개념 | 현재 (v1.36 기준) |
|---------|-------------------|
| Docker가 K8s의 런타임 (dockershim) | **containerd/CRI-O** (dockershim은 1.24에서 제거) |
| PodSecurityPolicy | **Pod Security Admission** (+ Kyverno/OPA로 보강) |
| Ingress 중심 | **Gateway API** 가 표준 (Ingress는 유지보수 모드) |
| in-tree 클라우드 볼륨 (`awsElasticBlockStore` 등) | **CSI 드라이버** (in-tree는 제거됨) |
| Helm v2 (tiller) → v3 | **Helm v4** (v3는 2026-07 지원 종료) |
| 사이드카를 일반 컨테이너로 | **네이티브 sidecar** (`initContainers` + `restartPolicy: Always`, GA) |
| cgroup v1 | **cgroup v2** (v1은 1.31부터 유지보수 모드) |

## 확인 명령

```bash
kubectl api-resources              # 현재 클러스터에서 유효한 리소스/버전
kubectl explain <kind> --api-version=<group/version>
# 다음 버전에서 깨질 리소스 미리 찾기 (오픈소스 도구)
# https://github.com/FairwindsOps/pluto
pluto detect-files -d ./manifests
```
