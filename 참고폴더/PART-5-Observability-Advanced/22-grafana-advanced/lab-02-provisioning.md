# Lab 02 — Provisioning (코드로 대시보드 관리)

> **🌱 Provisioning 이 뭔가? 왜 쓰나?**
> Grafana UI 에서 대시보드 만들면 → DB 에 저장 → **재배포/이사 시 손실 위험**.
> Provisioning = 대시보드/Datasource/Alert 를 **YAML/JSON 파일** 로 정의 → Grafana 가 시작 시 자동 로드.
>
> = "GitOps 친화적", "환경 (dev/prod) 간 동일", "코드 리뷰 가능".
>
> **kube-prometheus-stack 의 sidecar 패턴**:
> ```
>   ConfigMap (label: grafana_dashboard=1)
>     ↓ Grafana Pod 의 sidecar 가 watch
>     ↓ 새 ConfigMap 발견 → Grafana API 호출 → 자동 import
>   Grafana UI 에 즉시 노출 (재시작 불필요)
> ```

## 1. kube-prometheus-stack 의 dashboard sidecar

이미 떠 있는 Grafana Pod 에는 sidecar 컨테이너가 있어, ConfigMap 에 `grafana_dashboard: "1"` 라벨을 자동 import 합니다.

```bash
kubectl get cm -n monitoring -l grafana_dashboard=1 | head
```

→ 기본으로 다수의 대시보드가 ConfigMap 으로 등록되어 있음.

> **🧠 sidecar 컨테이너의 정체**
> Grafana Pod 안에 2개 컨테이너:
> ```
>   grafana-sc-dashboard  ← K8s API watch (ConfigMap)
>   grafana               ← 본체
> ```
> 두 컨테이너는 같은 Pod 내 파일 시스템 공유 (emptyDir volume).
> sidecar 가 ConfigMap 의 .json 을 디스크에 쓰면 → Grafana 의 file provisioner 가 자동 로드.
>
> **장점**: Grafana 재시작 X, ConfigMap 변경만으로 즉시 반영.
> **함정**: ConfigMap label 누락 = 영원히 import 안 됨 (에러 안 남음).

## 2. 우리 대시보드 ConfigMap 적용

```bash
kubectl apply -f manifests/dashboard-msa.yaml
```

## 3. Grafana 에서 자동 import 확인

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=20
```

기대:
```
... POST request sent to http://localhost:3000/api/admin/provisioning/dashboards/reload (200, OK)
... Working on configmap monitoring/dashboard-msa-red
... File in configmap monitoring/dashboard-msa-red ADDED
```

Grafana UI → Dashboards → 검색 "MSA RED" → 대시보드 보임.

> **🧠 디버깅 — sidecar 로그가 1순위**
> 대시보드 안 보이면:
> 1. `kubectl logs ... -c grafana-sc-dashboard` → ADDED 로그 있는지
> 2. ADDED 있는데 UI 안 보임 → Grafana 본체 로그 (`-c grafana`) → JSON parse error?
> 3. 로그 자체 없음 → ConfigMap label `grafana_dashboard=1` 빠졌거나 namespace 다름
>
> sidecar 가 항상 첫 의심 지점.

## 4. 대시보드 수정 → 재배포

ConfigMap 의 JSON 을 수정:
```bash
kubectl edit cm -n monitoring dashboard-msa-red
# panels 추가 / 수정
```

→ sidecar 가 자동 reload (수십 초 내).

> **🧠 UI 에서 수정한 내용은 어디로?**
> Grafana UI 에서 패널 수정 → 임시로 메모리 (저장 버튼 누르면 Grafana 내장 DB).
> **provisioning 으로 들어온 대시보드는 UI 에서 "Save" 비활성** — DB 가 source of truth 가 아니라 ConfigMap 이.
>
> → UI 에서 실험만 하고, JSON Model 복사 → ConfigMap 에 반영 → 코드 리뷰 → apply.
> 이 흐름이 "GitOps 호환".

## 5. 대시보드를 git 으로 관리하는 패턴

권장 구조:
```
manifests/
├── dashboards/
│   ├── msa-red.json
│   └── cluster-overview.json
└── dashboards-cm.yaml      # ConfigMap (data 가 위 .json 들)
```

ConfigMap 만드는 법:
```bash
kubectl create configmap dashboards -n monitoring \
  --from-file=manifests/dashboards/ \
  --dry-run=client -o yaml \
  | yq '.metadata.labels.grafana_dashboard = "1"' \
  > manifests/dashboards-cm.yaml
```

또는 Helm 차트의 `dashboards` values 활용 (kube-prometheus-stack 자체가 지원).

> **🧠 `--from-file=<dir>` 의 동작**
> 디렉토리 내 모든 파일을 ConfigMap data 의 키-값으로 변환.
> - 파일명 = data 키 (`msa-red.json`)
> - 파일 내용 = 값
>
> 한 ConfigMap 에 여러 대시보드 가능 — 단, ConfigMap 크기 한도 (~1MB) 주의.

## 6. Datasource Provisioning

위 sidecar 와 비슷한 방식으로 datasource 도:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: extra-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: CloudWatch
        type: cloudwatch
        jsonData:
          authType: default
          defaultRegion: ap-northeast-2
```

> **🧠 라벨 종류별 sidecar**
> kube-prometheus-stack 은 두 종류 sidecar:
> - `grafana_dashboard=1` — 대시보드 import
> - `grafana_datasource=1` — datasource 등록
>
> AWS CloudWatch datasource 는 `authType: default` → IRSA 로 설정된 IAM Role 자동 사용.
> Grafana Pod 의 ServiceAccount 에 CloudWatch 읽기 권한 부여 필요.

## 7. Dashboard JSON 의 핵심 필드

```json
{
  "title": "...",
  "uid": "msa-red",          ← 영구 ID (대시보드 URL의 영구 부분)
  "tags": [...],
  "templating": {
    "list": [variables...]
  },
  "panels": [
    {
      "id": 1,
      "type": "timeseries",  // 또는 stat, gauge, table, ...
      "gridPos": {"x":0, "y":0, "w":12, "h":8},
      "targets": [{ "expr": "PromQL", "legendFormat": "{{label}}" }],
      "fieldConfig": {"defaults": {"unit": "...", "thresholds": ...}}
    }
  ]
}
```

> **🧠 JSON 핵심 필드 의미**
> | 필드 | 의미 | 변경 시 영향 |
> |-----|------|------------|
> | `uid` | 대시보드 영구 ID | URL 깨짐, 알람 링크 깨짐 (절대 변경 X) |
> | `id` | 패널 내부 ID | 한 대시보드 안에서 unique. repeat panel 의 base |
> | `gridPos` | x/y/w/h 위치 | UI 에서 드래그로 변경 |
> | `targets[].expr` | PromQL | 가장 자주 수정 |
> | `legendFormat` | 범례 표시 | `{{namespace}} / {{pod}}` 같은 템플릿 |
> | `fieldConfig.unit` | 단위 (s, ms, bytes, percentunit) | 시각화 의미 |
>
> **GitOps 팁**: JSON 의 `version`, `iteration` 같은 메타 필드는 Grafana 가 매번 변경 → diff 노이즈. `jq` 로 제거 후 commit.

## 8. 정리

```bash
kubectl delete -f manifests/dashboard-msa.yaml
```

## 학습 확인

1. `grafana_dashboard: "1"` 라벨이 없는 ConfigMap 은 어떻게 되는가?
2. ConfigMap 의 JSON 파일이 1MB 초과면? (K8s ConfigMap 한계)
3. provisioning vs UI 직접 만들기 의 트레이드오프?

> **힌트**:
> 1. sidecar 가 무시 — Grafana 에 import 안 됨. label 조건 매칭 필수.
> 2. ConfigMap 자체 apply 실패 (etcd 객체 크기 한도 1MiB). 분할 ConfigMap 또는 PVC 사용.
> 3. provisioning = 코드화 + 환경 동기화 + 리뷰 가능, 단 JSON 수정 번거로움. UI = 빠른 prototyping, 단 손실/일관성 위험. 운영은 provisioning, 실험은 UI.

다음: [lab-03-alerting.md](./lab-03-alerting.md)
