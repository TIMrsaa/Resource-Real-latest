# Lab 02 — Software Template과 IDP 통합 그림

> 황금 경로를 스캐폴딩하는 Software Template을 설계하고, Backstage(42)·Crossplane(41)·GitOps(14·15)가 하나의 내부 개발자 플랫폼(IDP)으로 결합되는 전체 흐름을 구성합니다. 47(플랫폼 엔지니어링)의 청사진입니다.

## 1. Software Template 설계 (황금 경로)

플랫폼 팀이 "새 마이크로서비스" 템플릿을 만듭니다. 개발자는 이름·팀만 고르면 표준 서비스가 통째로 생깁니다.

```yaml
# template.yaml (Backstage Scaffolder)
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: microservice-golden-path
  title: 새 마이크로서비스 (황금 경로)
  description: 표준 구조·CI·DB·배포가 포함된 서비스를 생성
spec:
  owner: platform-team
  type: service
  parameters:
    - title: 서비스 정보
      required: [name, owner]
      properties:
        name:
          type: string
          description: 서비스 이름
        owner:
          type: string
          description: 소유 팀
          ui:field: OwnerPicker      # 조직 Group에서 선택
        needsDatabase:
          type: boolean
          title: PostgreSQL 필요?
          default: false
  steps:
    # ① 스켈레톤 코드 가져와 파라미터 치환
    - id: fetch
      name: 스켈레톤 가져오기
      action: fetch:template
      input:
        url: ./skeleton              # 표준 구조(Dockerfile·health·구조)
        values:
          name: ${{ parameters.name }}
          owner: ${{ parameters.owner }}
    # ② GitHub 레포 생성·푸시
    - id: publish
      name: 레포 생성
      action: publish:github
      input:
        repoUrl: github.com?owner=myorg&repo=${{ parameters.name }}
        defaultBranch: main
    # ③ (조건부) Crossplane DB Claim 생성 → 41의 인프라
    - id: database
      name: 데이터베이스 프로비저닝
      if: ${{ parameters.needsDatabase }}
      action: kubernetes:apply       # 또는 커스텀 액션
      input:
        manifest: |
          apiVersion: platform.example.org/v1alpha1
          kind: AppDatabase           # 41 lab-02의 Claim!
          metadata:
            name: ${{ parameters.name }}-db
          spec:
            parameters: { size: small }
    # ④ 카탈로그 등록
    - id: register
      name: 카탈로그 등록
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: /catalog-info.yaml
  output:
    links:
      - title: 레포
        url: ${{ steps.publish.output.remoteUrl }}
```

**관찰** — 이 템플릿 하나가 5가지 일(코드 스캐폴딩·레포 생성·DB 프로비저닝·CI·카탈로그 등록)을 묶습니다. `needsDatabase`를 켜면 3단계가 **41 lab-02에서 만든 AppDatabase Claim**을 생성합니다 — Backstage(UI)가 Crossplane(API)을 호출하는 지점입니다.

## 2. 개발자 경험 (Before/After)

```
Before (황금 경로 없음):
  1. 다른 서비스 레포 복붙
  2. 이름·설정 여기저기 수정 (누락 발생)
  3. CI 파일 복사 (버전 낡음)
  4. DB는 인프라팀에 티켓 (며칠 대기)
  5. 카탈로그·문서 등록 잊음
  → 반나절~며칠, 서비스마다 미묘하게 다름 (표류)

After (Backstage 템플릿):
  1. 포털에서 "새 마이크로서비스" 클릭
  2. 이름·팀 입력, DB 체크
  3. Create → 몇 분 뒤 레포·CI·DB·카탈로그 완성
  → 몇 분, 모든 서비스가 동일한 표준 (일관성)
```

이 차이가 47의 "인지 부하를 플랫폼이 흡수"의 실체입니다 — 개발자는 **비즈니스 로직에 집중**하고, 부수적 셋업은 플랫폼이 표준화합니다.

## 3. IDP 전체 아키텍처 (41·14·15·42 결합)

```
┌─────────────────────────────────────────────────────┐
│  개발자                                              │
│    ↓ 포털에서 클릭                                    │
│  Backstage(42) ── Catalog · Templates · TechDocs     │  ← UI 층
│    ↓ 템플릿 실행                                      │
├─────────────────────────────────────────────────────┤
│  레포 생성(GitHub) + Crossplane Claim(41) + Argo App  │  ← 생성 층
│    ↓                        ↓                ↓        │
│  코드·CI              인프라 API(41)      GitOps(14·15)│
│    ↓                        ↓                ↓        │
├─────────────────────────────────────────────────────┤
│  Crossplane → 클라우드 인프라 조정                    │  ← 조정 층
│  ArgoCD/Flux → 앱 배포 조정                           │
│    ↓                                                  │
├─────────────────────────────────────────────────────┤
│  Kubernetes 런타임 (Pod 실행)                         │  ← 런타임 층
│    ↑ 상태를 Backstage k8s 플러그인이 다시 표시        │
└─────────────────────────────────────────────────────┘
   ★ 피드백 루프: 런타임 현황이 다시 포털로 → 개발자가 한 곳에서 확인
```

## 4. 각 층의 CNCF 프로젝트 (커리큘럼 종합)

```
UI:        Backstage(42)
인프라:    Crossplane(41)
배포:      ArgoCD(14)·Flux(15) + Helm(13)·Kustomize
런타임:    Kubernetes + containerd(25)
관측:      Prometheus(11)·OTel(06·12)·Grafana → Backstage 플러그인
정책:      OPA(31)·Kyverno(32) → 생성 시 가드레일
보안:      cert-manager·SPIFFE(28)·Falco(30)
→ 이 커리큘럼의 프로젝트들이 IDP 한 그림에 모입니다
```

**이것이 CNCF 파트의 종착점** — 개별 프로젝트(11~42)를 배웠고, 이제 그것들이 **플랫폼으로 조립**되는 것을 봅니다. 47(플랫폼 엔지니어링)이 이 조립의 원리를, 48(비교 가이드)이 각 선택을 다룹니다.

## 5. 정리

- Software Template = 황금 경로 스캐폴딩(코드·레포·인프라·CI·카탈로그를 한 번에)
- 템플릿 스텝이 41(Crossplane Claim)·14(Argo App)를 호출 → UI가 API를 구동
- 개발자 경험: 반나절/며칠 → 몇 분, 표류 → 일관성
- IDP 층: Backstage(UI)·Crossplane(인프라)·GitOps(조정)·K8s(런타임) + 피드백 루프
- **★ 커리큘럼의 프로젝트들(11~42)이 하나의 플랫폼으로 조립 — 47이 그 원리**
