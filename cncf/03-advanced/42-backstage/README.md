# 42 — Backstage: 개발자 포털, 흩어진 것을 한곳으로

> 41(Crossplane)이 셀프서비스 인프라의 **백엔드 API**였다면, Backstage는 그 위의 **개발자 포털(UI)**입니다. 마이크로서비스가 수백 개로 늘면 "이 서비스는 누가 만들었고, 어디에 배포됐고, 문서는 어디 있고, 어떻게 새 서비스를 만드나요?"가 미궁이 됩니다. Backstage(스포티파이가 만들어 CNCF에 기증)는 이 흩어진 것을 하나의 포털로 모읍니다 — Software Catalog(서비스 목록), Software Templates(황금 경로로 새 서비스 생성), TechDocs(코드 옆 문서), 플러그인(CI·모니터링·쿠버네티스 통합). 이 모듈은 Backstage의 세 기둥과 카탈로그 모델(Entity·관계), 그리고 41·47과 함께 완성되는 "내부 개발자 플랫폼(IDP)"의 전체 그림을 세웁니다. 플랫폼 엔지니어링 트랙의 사용자 접점.

## 학습 목표

1. 개발자 포털이 푸는 문제(마이크로서비스 규모의 인지 부하·발견성)를 압니다
2. Backstage의 세 기둥(Catalog·Templates·TechDocs)과 플러그인 모델을 압니다
3. Software Catalog의 Entity 모델(Component·API·System·Resource·관계)을 압니다
4. Software Template로 "황금 경로"를 스캐폴딩하는 방식(41 Crossplane과 연결)을 압니다
5. Backstage(UI)·Crossplane(인프라 API)·GitOps(14·15)가 IDP로 결합되는 그림(47)을 압니다

## 선행: 41(Crossplane — 셀프서비스 백엔드), 14·15(GitOps), 24(마이크로서비스 규모) · 도구: Node.js(개념 이해), kind(선택)
## 비용: 없음 (개념 중심 — Backstage는 Node 앱, 실습은 카탈로그 YAML·템플릿 이해)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-catalog-and-entities.md](./lab-01-catalog-and-entities.md) — Software Catalog, Entity 모델
3. [lab-02-templates-and-idp.md](./lab-02-templates-and-idp.md) — Software Template, IDP 통합 그림
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
