# Lab 02 — Triggers와 "언제 Tekton인가"

Tekton의 이벤트 트리거를 구성하고(로우레벨의 실체), Tekton이 정당한 맥락을 판단합니다.

전제: lab-01의 Tekton과 tektonlab ns.

## Step 1. Triggers 설치

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
kubectl -n tekton-pipelines rollout status deploy/tekton-triggers-controller --timeout=120s
```

## Step 2. 트리거 조립 — Actions의 `on: push`를 손으로

GitHub Actions는 `on: push` 한 줄이면 되는 것을, Tekton은 명시적으로 조립합니다(theory §4):

```bash
cat <<'EOF' | kubectl apply -n tektonlab -f -
# ① TriggerTemplate: 무엇을 생성할지 (PipelineRun)
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata: { name: ci-template }
spec:
  params:
    - name: git-sha
  resourcetemplates:
    - apiVersion: tekton.dev/v1
      kind: PipelineRun
      metadata: { generateName: ci-triggered- }
      spec:
        pipelineRef: { name: ci }
        workspaces: [{ name: shared, emptyDir: {} }]
---
# ② TriggerBinding: webhook 페이로드에서 값 추출
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata: { name: ci-binding }
spec:
  params:
    - name: git-sha
      value: $(body.head_commit.id)
---
# ③ EventListener: webhook 수신 Pod
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata: { name: ci-listener }
spec:
  triggers:
    - bindings: [{ ref: ci-binding }]
      template: { ref: ci-template }
EOF
sleep 20
kubectl -n tektonlab get eventlistener,pods | grep -i listener
```

✅ **세 리소스를 조립**해야 "push하면 실행"이 됩니다(EventListener=수신, Binding=값 추출, Template=생성). Actions의 `on: push` 내장과 대조 — 로우레벨의 대가이자 유연성.

## Step 3. 트리거 발화 (webhook 시뮬레이션)

```bash
# EventListener Pod에 직접 이벤트 전송 (실제로는 GitHub webhook)
kubectl -n tektonlab port-forward svc/el-ci-listener 8080:8080 &
PF=$!
sleep 3
curl -s -X POST http://localhost:8080 \
  -H 'Content-Type: application/json' \
  -d '{"head_commit":{"id":"abc123def456"}}' | head -c 200; echo
kill $PF 2>/dev/null

sleep 15
kubectl -n tektonlab get pipelineruns | grep triggered
```

예상: `ci-triggered-xxxxx` PipelineRun이 자동 생성됨. ✅ **이벤트가 파이프라인을 생성**했습니다 — GitHub webhook을 el-listener에 연결하면 실제 CI가 됩니다.

## Step 4. Tekton에 K8s의 모든 도구가 적용됨 (강점)

CI가 Pod라서 얻는 것 — 다른 CI가 못 하는 것:

```bash
cat <<'EOF'
# Tekton CI에 적용 가능한 K8s 도구 (CI가 Pod니까)
- 리소스 제한: Task의 컨테이너에 requests/limits (k8s 06)
- 노드 선택: nodeSelector/affinity로 특정 노드에 (arm 빌드는 arm 노드 — eks 19)
- 스케일: Karpenter가 CI 부하로 노드 생성 (eks 17)
- 격리: NetworkPolicy로 CI Pod egress 제한 (eks 18, 08의 러너 보안)
- 보안: PSA/보안 컨텍스트 (eks 25, 08의 dind 대안 = kaniko)
- 시크릿: k8s Secret/External Secrets (14의 경계)
→ CI 실행 환경이 완전히 K8s = 클러스터 운영 지식이 그대로 CI에
EOF
```

✅ 이것이 Tekton의 진짜 힘 — CI가 별도 세계(SaaS)가 아니라 **클러스터의 일부**라, k8s/eks 파트에서 배운 모든 것이 CI에 적용됩니다.

## Step 5. 언제 Tekton인가 — 판단 워크시트 (산출물)

```markdown
# Tekton 채택 판단
## 정당한 신호
- [ ] 멀티클라우드/온프레/에어갭 — SaaS CI 못 씀
- [ ] CI 플랫폼을 직접 구축(플랫폼 팀이 개발자에게 CI 제공)
- [ ] 클러스터가 이미 인프라 중심, CI도 통합하고 싶음
- [ ] CI에 K8s 도구(노드 선택·격리·스케일)를 깊이 적용해야
- [ ] OpenShift 등 Tekton 기반 제품을 이미 씀

## 반대 신호 (SaaS CI가 나음)
- [ ] 빠른 시작·개발자 경험 우선
- [ ] 팀이 작고 표준 워크플로
- [ ] UI·마켓플레이스·생태계 필요
- [ ] CI 시스템을 조립·운영할 여력 없음

## 판단
정당 신호 다수 → Tekton (또는 그 위 플랫폼)
반대 신호 다수 → GitHub Actions/GitLab (대부분의 경우)

## 정직한 결론
Tekton은 로우레벨 빌딩 블록 — "CI를 조립하는 부품"입니다.
대부분은 완성품(SaaS)이 맞고, Tekton은 플랫폼을 짓는 사람의 도구.
"K8s 네이티브니까 무조건 좋다"는 조립 비용을 무시한 함정.
```

## Step 6. 세 CI 실행 모델 총정리 (파트 조망)

```markdown
# CI 실행 모델 스펙트럼 (이 파트에서 만난 것)
| 모델 | 예 | 실행 위치 | 이식성 | 시작 비용 |
|------|----|----------|--------|----------|
| SaaS | GitHub Actions, GitLab.com | 벤더 인프라 | 낮음(종속) | 낮음 |
| 관리형 오케스트레이션 | AWS Code 시리즈 | AWS | AWS 내 | 중간 |
| 셀프호스팅 상태형 | Jenkins | 우리 controller | 높음 | 높음(운영) |
| K8s 네이티브 | Tekton | 클러스터(Pod) | 높음(클러스터만) | 높음(조립) |

→ 선택은 이식성·시작비용·운영여력·팀문화의 함수 (12의 프레임)
```

## Step 7. 고급 진도

```markdown
16 → Tekton: K8s 네이티브 CI, 판단 기준                    [ ]
→ 17(Progressive Delivery): 11의 카나리 + 14의 GitOps = 자동 롤백 배포
→ 18(커스텀 액션), 19(BuildKit 심층), 20(모노레포)
```

## 정리

```bash
bash cleanup.sh
```
