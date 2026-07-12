# 이론 — kubectl의 구조와 핵심 메커니즘

> **🌱 17세 눈높이 비유: kubectl은 "만능 리모컨"입니다**
> TV(API 서버)에 명령을 보내는 리모컨일 뿐, TV 안에서 일하는 건 아닙니다(모듈 02에서 확인). 리모컨 버튼을 다 외울 필요 없습니다 — **"설명 보기" 버튼(explain)** 과 **"미리 보기" 버튼(diff/dry-run)** 위치만 알면 됩니다.

---

## 1. 모든 명령의 공통 해부

```
kubectl <동사> <리소스>[/<이름>] [플래그]
        get    pods/web        -n dev -o yaml
```

- 동사: get/describe/create/apply/delete/patch/edit/logs/exec...
- 리소스: `api-resources`의 NAME 또는 SHORTNAMES (po, svc, deploy, rs, ds, cm, ns...)
- 모든 것은 결국 HTTP 호출 (`-v=8`로 확인 가능)

## 2. explain — 내장 API 문서

```bash
kubectl explain deployment.spec.strategy          # 필드 설명 + 타입
kubectl explain pod.spec.containers.resources --recursive   # 하위 트리 전체
kubectl explain ingress --api-version=networking.k8s.io/v1  # 버전 지정
```

> **💡 CRD에도 통합니다**: 모듈 06의 HTTPRoute도 `kubectl explain httproute.spec.rules` 로 문서가 나옵니다 — annotation(문서 없음)과의 차이를 만든 그 기능.

## 3. 출력 가공 3종

```bash
# ① jsonpath — 스크립트용 추출
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'
kubectl get pod web -o jsonpath='{.status.containerStatuses[?(@.name=="app")].restartCount}'

# ② custom-columns — 사람용 표
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP

# ③ sort-by
kubectl get pods -A --sort-by=.metadata.creationTimestamp
kubectl get events --sort-by=.lastTimestamp
```

jq를 쓸 수 있다면 `-o json | jq`가 더 강력합니다. jsonpath는 "jq가 없는 환경(시험!)"에서도 되는 것이 가치.

## 4. 변경 명령의 위계

| 명령 | 성격 | 용도 |
|------|------|------|
| `create` | 명령형 생성 (있으면 에러) | 일회성 |
| `apply` | **선언형** — 차이만 반영, 반복 실행 안전(멱등) | 표준. Git의 YAML과 세트 |
| `edit` | 에디터로 라이브 수정 | 긴급 대응 (Git과 어긋남 주의) |
| `patch` | 일부만 수정 (스크립트 친화) | 자동화, 한 필드 수정 |
| `replace` | 통째 교체 | 드묾 |

### apply의 멱등성이 중요한 이유

`apply -f`는 1번 실행이나 100번 실행이나 결과가 같습니다 → CI/CD 파이프라인이 안심하고 반복 실행 (cicd 파트의 기초 체력).

### 적용 전 확인 2종

```bash
kubectl diff -f new.yaml          # 클러스터 현재 상태와의 차이 (적용 없이!)
kubectl apply -f new.yaml --dry-run=server   # 서버 검증까지 통과하는지 (admission 포함)
```

> `--dry-run=client`(문법만) vs `--dry-run=server`(서버의 검증/웹훅/기본값 주입까지) — server가 진짜 리허설입니다.

### patch 3형식 (헷갈림 주의)

```bash
# strategic merge (기본): K8s가 리스트 병합 규칙을 앎
kubectl patch deploy web -p '{"spec":{"replicas":5}}'
# JSON merge: 단순 덮어쓰기
kubectl patch deploy web --type=merge -p '{"metadata":{"labels":{"x":"y"}}}'
# JSON patch: 경로 기반 정밀 수술 (배열 인덱스 지정 가능)
kubectl patch deploy web --type=json -p='[{"op":"replace","path":"/spec/replicas","value":3}]'
```

## 5. 명령형 제너레이터 — YAML 타이핑 절약

```bash
kubectl create deployment web --image=nginx --replicas=3 --dry-run=client -o yaml > web.yaml
kubectl create service clusterip web --tcp=80:8080 --dry-run=client -o yaml
kubectl create job batch --image=busybox --dry-run=client -o yaml -- echo hi
```

빈 화면에서 YAML을 손으로 치지 마세요 — 뼈대를 생성해 고치는 것이 표준 워크플로 (CKA 시간 절약 1순위 스킬).

## 6. kubectl debug — 3가지 모드

```bash
# ① ephemeral container: distroless처럼 셸 없는 컨테이너에 디버그 컨테이너 주입
kubectl debug -it <pod> --image=busybox --target=<container>
# ② Pod 복제: 원본 건드리지 않고 사본으로 실험
kubectl debug <pod> -it --copy-to=debug-copy --container=app -- sh
# ③ 노드 디버깅: 노드 파일시스템을 /host로 마운트한 Pod (모듈 03에서 사용)
kubectl debug node/<node> -it --image=busybox
```

①이 결정적인 이유: 운영 이미지는 보안상 셸/도구를 빼는 추세(distroless) → `exec`가 불가능 → 디버그 컨테이너를 **같은 Pod의 namespace에** 임시 합류시켜 조사합니다. (모듈 03의 "Pod = namespace 공유"가 이렇게 재등장)

## 7. kubeconfig — 멀티 클러스터의 열쇠고리

```bash
kubectl config get-contexts            # 컨텍스트 = 클러스터+사용자+기본ns 묶음
kubectl config use-context <name>
kubectl config set-context --current --namespace=dev
KUBECONFIG=~/.kube/config:~/other.yaml kubectl config view --flatten   # 파일 병합
```

EKS는 `aws eks update-kubeconfig`가 컨텍스트를 등록합니다. 토큰은 IAM 자격증명으로 매번 생성(exec 플러그인) — "아침마다 Unauthorized"는 SSO 세션 만료입니다.

## 요약 카드

| 질문 | 답 |
|------|----|
| 필드 문서 즉석 조회? | `kubectl explain kind.path [--recursive]` |
| 적용 전 차이 확인? | `kubectl diff -f` / `--dry-run=server` |
| 반복 실행해도 안전한 명령? | `apply` (멱등) |
| 셸 없는 컨테이너 조사? | `kubectl debug --target=` (ephemeral container) |
| YAML 뼈대 생성? | `create ... --dry-run=client -o yaml` |
