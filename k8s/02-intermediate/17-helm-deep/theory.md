# 이론 — Helm 차트, 템플릿, 릴리스

> **🌱 17세 눈높이 비유: 차트는 "빵 반죽 틀", values는 "주문서"다**
> 빵집(클러스터)에 빵(리소스 YAML)을 매번 손으로 빚지 않습니다. **틀(차트 템플릿)** 을 만들어두고, 주문서(values.yaml)에 "크기 5, 초코칩 추가"라고 적으면 틀이 주문대로 찍어냅니다.
> dev 주문서와 prod 주문서를 따로 두면 같은 틀로 다른 빵이 나옵니다.
> **릴리스** = "이 틀 + 이 주문서로 찍어낸 결과물 묶음"에 붙는 일련번호 — 잘못 구우면 일련번호로 직전 판을 다시 꺼냅니다(rollback).

---

## 1. 차트 구조

```
mychart/
├── Chart.yaml          # 메타데이터: 이름, version(차트), appVersion(앱)
├── values.yaml         # 기본 주문서 (사용자가 -f/-set으로 덮어씀)
├── values.schema.json  # (선택) values 검증 스키마
├── templates/
│   ├── _helpers.tpl    # 재사용 템플릿 조각 (이름 규칙, 라벨 등)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── hpa.yaml
│   ├── NOTES.txt       # install 후 출력되는 안내문
│   └── tests/          # helm test용 Pod
└── charts/             # 의존성 차트 (헬름이 받아둠)
```

### 렌더링 파이프라인

```
values.yaml ─┐
-f 파일들    ─┼─ 병합(뒤가 우선) ─▶ .Values ─▶ Go 템플릿 엔진 ─▶ YAML ─▶ K8s API
--set 키=값 ─┘                      (+.Release, .Chart 내장 객체)
```

## 2. 템플릿 문법 핵심

```yaml
# 값 참조 + 기본값
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"

# 조건
{{- if .Values.autoscaling.enabled }}
# (HPA 사용 시 replicas 미출력 — 모듈 13 pitfall의 코드화!)
{{- else }}
replicas: {{ .Values.replicaCount }}
{{- end }}

# 반복
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}

# 구조체 통째로 (들여쓰기 조절)
resources:
  {{- toYaml .Values.resources | nindent 2 }}

# helpers 조각 호출
labels:
  {{- include "mychart.labels" . | nindent 4 }}
```

문법 요령:
- `{{-` / `-}}` : 앞/뒤 공백·개행 제거 — YAML 들여쓰기 사고의 99%가 이 조절 실패
- `quote`: 문자열 보장 (라벨 값 `"1.2"` 문제 — 모듈 09 pitfall)
- `include + nindent` 콤보가 표준 (옛 `template` 함수는 파이프 불가라 비권장)

### _helpers.tpl — 이름과 라벨의 단일 진실

```yaml
{{- define "mychart.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mychart.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```

모듈 09의 표준 라벨 세트가 여기서 자동화됩니다. 63자 잘림(trunc)은 라벨 길이 제한 대응.

## 3. 릴리스 수명주기

```bash
helm install myapp ./mychart -f values-prod.yaml -n shop --create-namespace
helm upgrade myapp ./mychart --set image.tag=v2 --atomic --timeout 5m
helm rollback myapp 1
helm history myapp
helm uninstall myapp
```

- 릴리스 상태는 클러스터의 **Secret**(`sh.helm.release.v1.myapp.v1`)에 저장 — "Helm은 어디에 기억하나"의 답
- `--atomic`: upgrade 실패 시 자동 롤백 (운영 표준 플래그)
- `helm diff` 플러그인: kubectl diff의 헬름판 — 강력 추천

### Hooks — 릴리스 이벤트에 작업 끼워넣기

```yaml
metadata:
  annotations:
    "helm.sh/hook": pre-upgrade        # DB 마이그레이션 Job의 단골 자리
    "helm.sh/hook-weight": "1"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

pre-install / post-install / pre-upgrade / post-upgrade / pre-rollback / test 등. "업그레이드 전에 마이그레이션, 실패하면 업그레이드 중단"이 대표 패턴.

## 4. 의존성

```yaml
# Chart.yaml
dependencies:
- name: redis
  version: "~20.x"
  repository: oci://registry-1.docker.io/bitnamicharts
  condition: redis.enabled          # values로 켜고 끄기
```

```bash
helm dependency update     # charts/에 다운로드
```

values 전달: 부모 values.yaml의 `redis:` 키 아래가 자식에게 갑니다. OCI 레지스트리(ECR에 차트 push 가능!)가 현행 표준 배포 채널.

## 5. 소스코드에서 확인하기

- Helm 본체: https://github.com/helm/helm — `pkg/engine/engine.go`가 템플릿 렌더링, `pkg/action/upgrade.go`가 3-way merge 업그레이드 로직
- 잘 만든 차트 견본: https://github.com/bitnami/charts — 라이브러리 차트 패턴의 교과서

## 요약 카드

| 질문 | 답 |
|------|----|
| 차트/릴리스 구분? | 차트=틀(패키지), 릴리스=설치된 인스턴스(이력 있음) |
| values 우선순위? | values.yaml < -f 파일(뒤가 우선) < --set |
| 릴리스 기록 저장소? | 클러스터 내 Secret |
| 들여쓰기 사고 방지? | `helm template`으로 렌더링 먼저 + `nindent` |
| 운영 upgrade 플래그? | `--atomic --timeout` |
| DB 마이그레이션 자리? | pre-upgrade hook Job |
