# 이론 — 렌더링 파이프라인, 릴리스 상태 기계, 3-way 병합, 훅, v4

> **🌱 17세 눈높이 비유: 조립식 가구 주문**
> - **차트(Chart)** = 가구 카탈로그 한 페이지 (설계도 + 선택 가능한 옵션 목록)
> - **values** = 주문서 (색상: 화이트, 서랍: 3개)
> - **템플릿 렌더링** = 주문서를 보고 실제 조립 설명서를 인쇄 — 이때 오탈자(들여쓰기)가 나면 조립이 안 됩니다
> - **릴리스(Release)** = **주문 기록** — "이 집에 이 가구를 이 옵션으로 설치함". 이 기록이 있어야 "지난번 주문으로 되돌려줘"(롤백)가 가능합니다
> - **3-way 병합** = 지난 설명서(내가 준 것) + 현재 집 상태(누가 손댔을 수도) + 새 설명서 → 무엇을 바꿀지 결정
> - **훅(hook)** = 조립 전후에 하는 별도 작업 (배송 전 바닥 청소, 조립 후 검사)
> - **GitOps와의 긴장** = "주문 기록이 진실"(Helm) vs "카탈로그+주문서가 진실"(Git) — 둘 중 하나만 진실일 수 있습니다

---

## 1. 차트 구조와 렌더링 파이프라인

```
mychart/
├── Chart.yaml          메타데이터 (name, version, appVersion, dependencies)
├── values.yaml         기본 values (스키마: values.schema.json)
├── templates/
│   ├── deployment.yaml Go 템플릿
│   ├── _helpers.tpl    재사용 정의 (define/include)
│   ├── NOTES.txt       설치 후 안내
│   └── tests/          helm test용 (hook: test)
├── charts/             서브차트 (의존성 — 벤더링)
└── crds/               ★ 특별 취급 (템플릿 아님! 설치만, 업그레이드·삭제 안 함)
```

```
렌더링 파이프라인:
  values 병합 (기본 → -f 파일들 → --set)   ← 나중이 이김
    + 내장 객체 (.Release, .Chart, .Capabilities, .Files)
        ↓
  Go template 실행 (sprig 함수 포함)
        ↓
  YAML 파싱 → 매니페스트 오브젝트들
        ↓
  후처리: post-renderer(kustomize 등), 라벨 주입(app.kubernetes.io/managed-by=Helm)
        ↓
  릴리스 저장 + 클러스터에 적용
```

- `.Capabilities.APIVersions` — 클러스터의 API 버전에 따라 분기(호환성). 단 `helm template`은 클러스터를 모르므로 `--api-versions`로 흉내 필요
- **crds/는 함정**: 템플릿이 아니고, 설치 시에만 생성되며 업그레이드·삭제되지 않습니다(CRD 수명주기는 Helm 밖의 문제)

## 2. 릴리스 — Helm의 발명품

```
저장 위치: 릴리스 네임스페이스의 Secret (기본 드라이버)
  이름: sh.helm.release.v1.<release>.v<revision>
  내용: base64(gzip(JSON)) — 릴리스 메타 + values + 렌더링된 매니페스트 전문

revision 1, 2, 3... 이 쌓입니다 (기본 최대 10 — --history-max)
  helm history / helm rollback 이 이것을 읽습니다
```

상태 기계:

```
pending-install → deployed
pending-upgrade → deployed | failed
pending-rollback → deployed
superseded (이전 revision)
uninstalling → uninstalled

★ 중단(Ctrl-C·타임아웃)으로 pending-* 에 멈추면 다음 명령이 거부됩니다
  → "another operation is in progress" — 해결: helm rollback 또는 릴리스 Secret 정리
```

## 3. 3-way 병합 — upgrade가 하는 진짜 일

`helm upgrade`는 세 상태를 봅니다:

```
old:   이전 릴리스에 저장된 매니페스트 (Helm이 마지막으로 준 것)
live:  클러스터의 현재 오브젝트 (누가 kubectl로 고쳤을 수도)
new:   방금 렌더링한 매니페스트

패치 계산:
  old에 있고 new에 없음      → 삭제 대상
  old와 new가 다름           → new 값으로
  old에 없고 live에만 있음   → ★ 그대로 둡니다 (Helm이 모르는 것은 안 건드립니다)
```

이것이 미스터리의 답입니다:

```
kubectl로 replicas를 3→5 로 바꿈 (Helm의 old에는 3, new에도 3)
  → old==new 이므로 Helm은 "변경 없음"으로 보고 live(5)를 건드리지 않는다 ⚠️
  → 그런데 values에서 replicas를 3→4로 바꾸면 old(3)≠new(4) → 4로 덮어씀
★ "helm이 내 수동 변경을 되돌린다/안 되돌린다"가 상황에 따라 다른 이유
  (--force 는 이 병합을 건너뛰고 replace — 위험)
```

Helm v4는 **서버사이드 apply**(필드 소유권 기반)로 이 영역을 개선하는 방향입니다(k8s의 field manager가 병합을 판정).

## 4. 템플릿 엔진의 대가

```yaml
# 흔한 3대 사고
data:
  config: {{ .Values.config }}                # ❌ 여러 줄이면 YAML 깨짐
  config: |
{{ toYaml .Values.config | indent 4 }}        # ✅ (indent) — 첫 줄에 개행 없음 주의
  config: {{ toYaml .Values.config | nindent 4 }}   # ✅ (nindent = 개행 + indent)

  port: {{ .Values.port }}                    # 문자열 "8080"이 오면 타입 불일치
  port: {{ .Values.port | int }}              # ✅
  name: {{ .Values.name | quote }}            # ✅ "true"·"123"이 bool·int로 해석되는 것 방지
  tag: {{ .Values.tag | default .Chart.AppVersion }}
```

방어 도구:

```bash
helm lint mychart/                     # 정적 검사
helm template mychart/ --debug         # 렌더링 결과 확인 (클러스터 없이)
helm install --dry-run --debug         # 서버 검증 포함 (실제 API 서버가 스키마 확인)
values.schema.json                     # values의 JSON Schema — 잘못된 입력을 사전 차단
helm unittest / conftest               # 렌더링 결과에 정책 검사 (cicd 24)
```

## 5. 훅(hooks) — 순서 제어와 그 위험

```yaml
metadata:
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install     # pre/post × install/upgrade/rollback/delete
    "helm.sh/hook-weight": "-5"                 # 작을수록 먼저
    "helm.sh/hook-delete-policy": hook-succeeded # before-hook-creation | hook-succeeded | hook-failed
```

```
용도: DB 마이그레이션 Job(cicd 11), CRD 선행 설치, 사전 검증
위험:
  ① 훅 리소스는 릴리스의 일부가 아닙니다 → helm uninstall 시 남을 수 있습니다(delete-policy 필수)
  ② 훅 실패 = 업그레이드 실패, 그러나 이미 실행된 부작용(마이그레이션)은 롤백 안 됨
  ③ 훅은 순서를 강제하지만 '멱등'을 보장하지 않습니다 → 재시도 안전하게 설계
대응: cicd 14의 sync wave와 같은 사고 — 순서는 도구가, 멱등성은 우리가
```

`helm test`는 `hook: test` 리소스를 실행하는 것 — 설치 검증용.

## 6. Helm과 GitOps의 긴장 (16·17의 예고)

```
[ArgoCD 방식] helm template 으로 렌더링만, 릴리스 Secret 없음
  → Git이 유일한 진실. helm history/rollback 사용 불가(대신 Git revert)
  → 훅은 ArgoCD의 sync hook으로 매핑(일부 제약)

[Flux 방식] HelmRelease CR → helm-controller가 실제 helm 릴리스를 만듭니다
  → 릴리스 상태 기계 유지(history·rollback 가능). Git은 "무엇을 설치할지"의 선언
  → 값 변경은 Git으로, 릴리스 관리는 컨트롤러가

[CI 렌더 방식] CI가 helm template 결과를 Git에 커밋 (08의 rendered manifests)
  → diff가 정직, 감사 우수. 차트 업그레이드가 PR로 보입니다
```

## 7. v3 → v4 요점

```
유지: 릴리스 Secret, 3-way 병합의 정신 모델, 훅, 차트 구조
변화: 서버사이드 apply 지향(필드 소유권), SDK/플러그인 개편(WASM), 일부 명령·기본값 정리
운영: v3는 2026-11 보안픽스 종료(루트 버전표) → v4 기준으로 학습·이전
주의: 차트 호환성(apiVersion: v2 차트는 대체로 그대로), 플러그인 생태계는 재확인
```

## 8. 소스/도구에서 확인하기

- Helm 문서: https://helm.sh/docs — chart template guide, hooks, storage backend
- sprig 함수: http://masterminds.github.io/sprig/
- 릴리스 저장: `kubectl get secret -l owner=helm`
- 08 복습: Helm vs Kustomize의 자리

## 요약 카드

| 질문 | 답 |
|------|----|
| Helm의 발명품? | 템플릿이 아니라 **릴리스** — K8s에 없는 "설치된 앱"의 개념 |
| 릴리스는 어디에? | 네임스페이스의 Secret (`sh.helm.release.v1.<name>.v<rev>`) — gzip JSON |
| upgrade의 실체? | old(저장)·live(클러스터)·new(렌더) 3-way 병합 |
| 수동 변경이 살아남는 이유? | old==new면 Helm은 "변경 없음"으로 보고 live를 안 건드립니다 |
| 템플릿 3대 함정? | 들여쓰기(nindent), 타입(int/quote), 여러 줄(toYaml) |
| crds/ 디렉터리? | 템플릿 아님 — 설치만, 업그레이드·삭제 안 함 |
| 훅의 위험? | 릴리스 밖 리소스(정리 정책), 실패 시 부작용 롤백 안 됨, 멱등성은 우리 몫 |
| GitOps와의 긴장? | ArgoCD=템플릿만(Git이 진실) / Flux=릴리스 유지 / CI 렌더=정직한 diff |
