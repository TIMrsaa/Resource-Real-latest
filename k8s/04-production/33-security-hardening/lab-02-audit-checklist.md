# Lab 02 — 내 클러스터 셀프 감사 (체크리스트 실행)

> theory §4의 체크리스트를 실제 명령으로 — 각 항목을 실행하고 결과를 기록하세요. **이 lab의 산출물 = 우리 클러스터의 첫 감사 보고서.**

## ① 권한 감사 (모듈 11의 재실행)

```bash
# cluster-admin을 가진 모든 주체
kubectl get clusterrolebindings -o json | python3 -c "
import json,sys
for b in json.load(sys.stdin)['items']:
    if b['roleRef']['name']=='cluster-admin':
        for s in b.get('subjects',[]) or []:
            print(f\"{b['metadata']['name']:40} {s['kind']:15} {s.get('name')}\")"

# 와일드카드 verbs/resources를 가진 Role (위험 신호)
kubectl get clusterroles -o json | python3 -c "
import json,sys
for r in json.load(sys.stdin)['items']:
    for rule in r.get('rules',[]) or []:
        if '*' in rule.get('verbs',[]) and '*' in rule.get('resources',[]):
            print(r['metadata']['name']); break" | grep -v "^system:" | head

# secrets를 읽을 수 있는 SA 목록 (까다로운 질문 — can-i 역방향)
kubectl auth can-i list secrets -A --as=system:serviceaccount:default:default && echo "위험!" || echo "default SA OK"
```

기록할 것: cluster-admin 주체 수(목표: 최소), 와일드카드 커스텀 Role 수(목표: 0).

## ② 워크로드 보안 상태 (모듈 32의 재실행)

```bash
# PSA 라벨 없는 ns
kubectl get ns -o json | python3 -c "
import json,sys
for n in json.load(sys.stdin)['items']:
    l=n['metadata'].get('labels',{})
    if 'pod-security.kubernetes.io/enforce' not in l:
        print(n['metadata']['name'])" | grep -vE "^kube-|^default$" || echo "전부 적용됨"

# 운영 중인 privileged / root 컨테이너 수색
kubectl get pods -A -o json | python3 -c "
import json,sys
for p in json.load(sys.stdin)['items']:
    for c in p['spec']['containers']:
        sc=c.get('securityContext') or {}
        if sc.get('privileged'): print('PRIVILEGED:', p['metadata']['namespace'], p['metadata']['name'])"
```

## ③ 네트워크 (모듈 15의 재실행)

```bash
# NetworkPolicy가 하나도 없는 ns = 전부 개방
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  count=$(kubectl get networkpolicy -n $ns --no-headers 2>/dev/null | wc -l)
  [ "$count" -eq 0 ] && echo "개방됨: $ns"
done | grep -vE "kube-" 
```

## ④ 시크릿/인증서 위생

```bash
# 웹훅 인증서 만료 (모듈 23의 시한폭탄 점검)
for wh in $(kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o name); do
  echo "$wh: caBundle 점검 대상"
done
# Git에 평문 시크릿이 있는지는 cicd 파트의 gitleaks로 — 여기선 항목만 기록

# 감사 로그 활성 여부 (모듈 21)
aws eks describe-cluster --name k8s-study --region ap-northeast-2 \
  --query 'cluster.logging.clusterLogging[?enabled==`true`].types' --output text
```

## ⑤ 버전/지원 수명

```bash
kubectl version | grep Server
aws eks describe-cluster --name k8s-study --region ap-northeast-2 --query 'cluster.version'
# 표준 지원 종료일 대비 잔여 기간을 기록 (14개월 규칙 — 루트 README 버전표)
```

## ⑥ 보고서 작성 (산출물 양식)

```markdown
# 클러스터 보안 감사 — 2026-06-12
| 영역 | 발견 | 심각도 | 조치 | 기한 |
|------|------|--------|------|------|
| RBAC | cluster-admin 2건 | M | 1건 회수, 1건 문서화 | 6/20 |
| PSA  | ns 3개 미적용     | H | warn부터 적용         | 6/15 |
| ...  |                   |   |                       |      |
다음 감사: 2026-09 (분기)
```

✅ **숫자와 기한이 있는 보고서**가 감사의 완성형입니다 — "대체로 양호" 류의 문장은 다음 분기에 아무것도 바꾸지 못합니다.

## 정리

생성 리소스 없음. 보고서를 reference/ 폴더 등에 보관.
