# 학습 가이드 — Helm과 다른 철학을 가진 도구

## 철학의 차이가 전부입니다

| | Helm | Kustomize |
|---|------|-----------|
| 원본 YAML | 템플릿 (그 자체론 invalid) | **완전한 YAML** (그대로 apply 가능) |
| 변형 방법 | 값 치환 ({{ }}) | **패치 겹치기** (오버레이) |
| 추가 기능 | 패키징, 릴리스 이력, hook | 없음 (변형만) — kubectl 내장 |
| 어울리는 곳 | 배포 가능한 "제품"(차트), 외부 소프트웨어 설치 | **자기 앱의 환경 분리**, GitOps |

Helm 템플릿은 강력하지만 원본이 더 이상 YAML이 아니게 됩니다(에디터 지원/검증 약화). Kustomize는 "원본은 늘 유효한 YAML, 차이는 패치 파일로"라는 보수적 접근 — 그래서 GitOps(ArgoCD/Flux) 진영에서 사랑받습니다.

## 미리 잡아둘 멘탈모델

```
base/           ← 환경 공통의 "완전한" 리소스들 + kustomization.yaml
overlays/
  dev/          ← base를 가리키고, dev만의 패치를 얹음
  prod/         ← base를 가리키고, prod만의 패치를 얹음
```

오버레이는 base를 **수정하지 않습니다** — 겹쳐 보일 뿐. 투명 필름 비유(모듈 01 이미지 레이어)가 그대로 통합니다.

## 숨은 보석: configMapGenerator의 해시

모듈 07에서 "ConfigMap은 이름에 해시를 박아 교체하라"는 패턴을 배웠습니다 — Kustomize의 configMapGenerator가 **그걸 자동화**합니다(내용 해시 접미사 + 참조 자동 갱신). 설정 변경 → 새 이름 → Deployment template 변경 → 자동 롤링 업데이트. 이 기능 하나만으로도 배울 가치가 있습니다.

## 결론 미리: 싸움이 아니라 분업

실무 표준 조합: **외부 소프트웨어는 Helm으로 받고, 우리 회사 커스텀은 Kustomize로 얹습니다** (`helm template | kustomize build`). lab-02에서 직접 합니다.
