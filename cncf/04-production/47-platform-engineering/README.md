# 47 — 플랫폼 엔지니어링: 플랫폼을 제품으로

> 46에서 레퍼런스 플랫폼(층·의존·조립)을 세웠습니다. 하지만 그 플랫폼을 **누가 어떻게 쓰나**? 개발자가 매번 YAML·kubectl·클라우드 콘솔을 직접 다뤄야 한다면 46의 정교한 플랫폼도 인지 부하만 늘립니다. 플랫폼 엔지니어링은 이 문제를 풉니다 — 플랫폼 팀이 인프라 복잡성을 흡수하고, 개발자에게 **셀프서비스 황금 경로**를 제공하며, 플랫폼을 "내부 고객(개발자)을 위한 제품"으로 운영합니다. 이 모듈은 41(Crossplane 인프라 API)·42(Backstage 포털)·46(레퍼런스 플랫폼)을 하나의 **내부 개발자 플랫폼(IDP)**으로 통합하고, 그보다 더 중요한 **"제품으로서의 플랫폼(platform as a product)"** 이라는 사고방식 — Team Topologies, 인지 부하, 황금 경로, 플랫폼의 성숙도 측정 — 을 다룹니다. 도구가 아니라 조직·문화의 이야기입니다.

## 학습 목표

1. 플랫폼 엔지니어링이 푸는 문제(개발자 인지 부하, 셀프서비스)를 압니다
2. IDP를 41(Crossplane)·42(Backstage)·46(레퍼런스 플랫폼)으로 통합하는 그림을 압니다
3. "제품으로서의 플랫폼" 사고(Team Topologies·황금 경로·내부 고객)를 압니다
4. 황금 경로가 강제가 아니라 매력이어야 하는 이유(pave not fence)를 압니다
5. 플랫폼의 성숙도·성공을 측정하는 법(채택률·DORA·개발자 만족)을 압니다

## 선행: 41(Crossplane), 42(Backstage), 46(레퍼런스 플랫폼) — 필수 종합, cicd 26(DORA) · 도구: 개념 중심
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-golden-path-design.md](./lab-01-golden-path-design.md) — 황금 경로 설계, IDP 통합
3. [lab-02-platform-as-product.md](./lab-02-platform-as-product.md) — 제품 사고, 성숙도 측정
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
