# 이론 — AMG 구조, 인증, 데이터소스 IAM, as code, 권한, 판단

> **🌱 17세 눈높이 비유: 학교 상황실을 외부 전문 업체에 맡기기**
> - **자체 상황실(자체 Grafana)** = 모니터·배선·출입 관리를 우리가 — 자유롭지만 손이 감
> - **위탁 상황실(AMG)** = 업체가 시설 운영 — 우리는 화면 구성만. 특히 **출입증 연동**(학교 학생증 = Identity Center)과 **교내 시설 열쇠**(AWS 데이터소스 = IAM 롤)가 자동
> - **사용자당 요금** = 상황실 출입 인원수로 과금 — 전교생에게 열면 비쌈, 필요한 사람만
> - **화면 설계도(as code)** = 위탁이어도 설계도(Git의 JSON)는 우리가 보관 — 업체를 바꿔도 설계도로 재시공
> - **판단** = 교내 시설 위주면 위탁이 편하고, 외부 시설이 많거나 인원이 많으면 자체가 유리

---

## 1. AMG 구조와 인증

```
워크스페이스 = 관리형 Grafana 인스턴스 (버전·확장·HA를 AWS가)
과금: 활성 사용자당 (Editor/Admin > Viewer 단가) — 사용자 수가 비용 손잡이

인증 (로그인을 누가 관리하나):
  IAM Identity Center (구 SSO): AWS 계정 체계와 통합 — 표준 경로
  SAML: 기존 IdP(Okta·Azure AD 등) 연동
  ★ 로컬 계정 없음 — "기업 SSO 통합"이 기본값 (자체 Grafana에선 이게 일)

역할 매핑: Identity Center 사용자/그룹 → Admin/Editor/Viewer
```

## 2. 데이터소스 — IAM 롤 기반 배선 (키 없는 통합)

```
AMG 워크스페이스에는 IAM 롤이 연결됨 (서비스 롤)
  → 데이터소스가 이 롤로 AWS API 호출 — 키·시크릿 저장 없음!

AMP: SigV4 자동 (같은 계정이면 사실상 클릭 배선) — 14의 데이터가 화면에
CloudWatch: 롤에 CW 읽기 권한 → 로그(Logs Insights 쿼리)·메트릭 패널
X-Ray: 롤에 X-Ray 읽기 → 트레이스 화면 (17에서 데이터 공급)
크로스 계정: 역할 체인(assume role)으로 다계정 관측 집약 (조직 규모)

의미: 12의 상관 배선(데이터소스 연결)이 IAM으로 재현됩니다
  Grafana 화면 문법(변수·드릴다운·패널)은 09 그대로 — 재학습 없음
```

## 3. as code — 관리형에서의 유지법

```
sidecar(09의 CM 로드)가 없습니다 → 대안:

① Grafana API + 서비스 어카운트 토큰:
   Git의 JSON → CI(GitHub Actions 등)가 API로 push
   = GitOps의 pull이 push로 바뀐 변형 (원리는 동일: Git이 진실)
② Terraform grafana provider:
   대시보드·데이터소스·폴더·권한까지 선언 관리 (IaC 통합)
③ Grafana Operator(클러스터에서 원격 관리) 등

공통 규율 (09 그대로):
  uid 고정 (링크·알림 착지), datasource 변수화,
  UI 수정은 초안 → Git 반영, PR 리뷰
★ 관리형은 서버를 대신 운영하지 규율을 대신 지키지 않습니다
```

## 4. 권한 — 팀·폴더로 조직을 화면에

```
폴더 = 권한 경계: 팀 폴더별 Editor 권한, 공용(L1 개요)은 전사 Viewer
Identity Center 그룹 ↔ Grafana 팀 매핑 → 조직 개편이 권한에 자동 반영
관례: L1(온콜 공용) / 팀별 폴더(L2·L3) / 실험 폴더(개인) — 09의 계층과 정합
```

## 5. 판단 — 자체 vs AMG

```
              자체 Grafana                AMG
운영           서버·DB·업그레이드 직접      AWS (거의 0)
인증(SSO)      직접 구축 (부담 큼)          Identity Center 내장 ★
AWS 데이터소스  자격 증명 관리 필요           IAM 롤 자동 ★
플러그인·버전   자유                        제약 (Enterprise 플러그인 일부 제공)
비용           인프라비 (사용자 무관)        활성 사용자당 (많으면 비쌈)
멀티클라우드    자유                        가능하나 강점 아님

AMG가 맞습니다: AWS 중심(AMP·CW·X-Ray) + SSO 필요 + 소수~중간 사용자 + 운영 최소
자체가 맞습니다: 대규모 사용자(과금), 플러그인 자유, 멀티클라우드 중심, 역량 보유
이동 비용: 대시보드 JSON은 이식 쉬움 — 인증·권한·알림 채널 재구축이 실비용
→ cncf 48의 3층(기능→철학→조직 적합)으로: 결정적 축은 대개 SSO와 사용자 수
```

## 6. 소스/도구에서 확인하기

- AMG 문서: docs.aws.amazon.com/grafana — 인증·데이터소스·API
- AMG 요금: aws.amazon.com/grafana/pricing (사용자당)
- Terraform grafana provider (as code)
- 09(대시보드 규율)·12(상관 배선)·14(AMP)

## 요약 카드

| 질문 | 답 |
|------|----|
| AMG의 핵심 가치? | 운영 제로 + SSO(Identity Center) + AWS 데이터소스 IAM 자동 배선 |
| 과금 모델? | 활성 사용자당 (Viewer<Editor) — 사용자 수가 비용 손잡이 |
| 데이터소스 자격? | 워크스페이스 IAM 롤 — 키·시크릿 저장 없음 (크로스 계정은 role chain) |
| as code 유지? | sidecar 없음 → API push(CI)·Terraform — Git이 진실은 불변 |
| 권한 설계? | 폴더=경계, Identity Center 그룹↔팀 매핑 (L1 공용/팀 폴더) |
| 자체가 유리한 때? | 대규모 사용자·플러그인 자유·멀티클라우드 중심 |
| 이동 비용? | 대시보드 JSON은 가벼움 — 인증·권한·알림 채널이 실비용 |
| 09와의 관계? | 화면 문법·규율은 그대로 — 서버와 자격 관리만 넘어감 |
