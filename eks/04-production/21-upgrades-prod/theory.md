# 이론 — 버전 정책, insights 워크플로, 플릿 전략의 산수

> **🌱 17세 눈높이 비유: 지하철 시스템의 세대교체**
> 운행을 멈추지 않고 지하철을 업그레이드합니다:
> - **신호 시스템(CP)** = 한 번 올리면 못 되돌립니다 — 착공 전 안전 심사(insights)가 전부
> - **열차(노드)** = 구형·신형이 한동안 **혼재 운행**해도 됩니다(skew의 여유) — 교체 방식이 여럿: 한 량씩 순차 교체(롤링), **새 차량기지를 통째로 준비해 노선을 넘기기**(Blue/Green), 정비 주기마다 자연 교체(Karpenter drift)
> - **승객 안내(PDB·drain)** = "이 칸 내리세요"를 예의 바르게 — 러시아워(이벤트 캘린더)는 피해서
> - **월 정기권 인상(연장 지원 요금)** = 교체를 미루는 노선에는 요금이 붙습니다 — 미루기는 공짜가 아닙니다

---

## 1. 버전 정책 — 문서 한 장이 미루기를 막습니다

```
EKS 수명주기: 마이너 출시 → 표준 지원 ~14개월 → 연장 지원 ~12개월(시간당 요금 6배급 할증)
             → 연장 종료 시 강제 자동 업그레이드 (우리 일정이 아닌 AWS의 일정으로!)
```

권장 정책(팀 문서로 박제할 것): **"항상 최신-1을 유지하고, 분기마다 한 번 올린다"** — 최신은 초기 회귀를 피하고, 최신-2 이하로 밀리면 연장 요금과 겹침 업그레이드가 시작됩니다. 정책이 문서로 없으면 업그레이드는 늘 "다음 분기에"가 됩니다.

## 2. insights — preflight의 자동화된 절반

```bash
aws eks list-insights --cluster-name C --filter categories=UPGRADE_READINESS
aws eks describe-insight --id ... # → recommendation + 근거 리소스까지
```

점검 항목의 성격: 폐기 API 실호출(감사 로그 기반 — 어떤 클라이언트가, 마지막 호출 시각까지), kubelet 버전 skew, 애드온 호환성 등. **ERROR = 게이트 폐쇄**가 기계적 규칙이고, WARNING은 사유를 계획서에 적고 수용 여부를 결정합니다. insights가 못 보는 것도 명확히: 아직 배포 안 된 매니페스트(Pluto의 몫 — 35), 서드파티 컨트롤러의 목표 버전 지원 여부(릴리스 노트의 몫).

## 3. 업그레이드 표면 4종 — 순서는 35, 명령은 여기

```
G(게이트): insights ERROR 0 + Pluto 0 + PDB 점검 + 백업(36) + 용량 여유 확인
① CP:      aws eks update-cluster-version --kubernetes-version 1.37   (비가역, 20~40분, API 무중단)
② 애드온:   대상 버전 default로 — vpc-cni → coredns → kube-proxy (11의 절차)
③ 노드:     플릿 전략별 (§4) — kubelet이 CP를 따라잡는 단계
④ 워크로드: 새 기능/폐기 API 대응 매니페스트 정리 (평시 부채 관리의 영역)
```

①과 ③ 사이의 여유(skew 3마이너)가 프로덕션의 숨통입니다 — CP는 화요일에, 노드는 목~금에 나눠 밟는 식의 분할 실행이 표준이 됩니다.

## 4. 노드 플릿 전략 — 다섯 표면의 각론

### ① 관리형 롤링 (기본값)

```bash
aws eks update-nodegroup-version --nodegroup-name workers \
  # updateConfig: maxUnavailable(또는 %) — 동시 교체 폭
```

EKS가 surge 노드 추가 → cordon+drain(PDB 존중) → 종료를 자동 반복. **시간 산수**: 노드당 drain 시간(Pod 수·PDB 빡빡함에 비례, 대략 2~10분) × 노드 수 ÷ 동시성. 100대·동시 10%면 대략 몇 시간 급 — 계획서에 이 추정이 있어야 "왜 아직도 돌아요?"가 안 나옵니다.

### ② Blue/Green 노드그룹 (lab-02)

```
새 NG(green, 새 버전) 생성 → 검증 → 구 NG(blue) cordon → drain(이주) → blue 삭제
```

값: **롤백이 즉시**(blue를 지우기 전까지) + 새 노드의 사전 검증 가능. 비용: 이주 기간 동안 2배 용량. 대형 점프·위험 변경(AMI 계열 교체, 19의 arch 전환)에 적합.

### ③ Karpenter drift (17의 배당)

EC2NodeClass의 `amiSelectorTerms: [{alias: al2023@latest}]`라면 — CP 업그레이드 후 새 AMI가 latest가 되는 순간 기존 노드들이 **drift**(선언과 실물 불일치)로 판정되고, disruption budgets의 속도로 자동 교체됩니다. 업그레이드가 "이벤트"가 아니라 **상시 순환의 한 파도**가 되는 것 — 단 budgets 없이는 한꺼번에 출렁이니 반드시 폭 제한.

### ④ Fargate / ⑤ Auto Mode

Fargate: 노드가 없으니 **Pod 재배포가 곧 업그레이드**(rollout restart로 새 버전 기반에 재기동). Auto Mode: 노드 순환을 AWS가 수행 — 우리의 일은 PDB와 do-not-disrupt를 바르게 걸어두는 것뿐(어디서나 같은 결론입니다).

## 5. 대규모의 추가 변수

- **용량 여유**: drain 중 Pod들이 옮겨갈 자리 — 13의 무릎 기준 여유율로 surge 크기를 정합니다 (여유 없이 drain하면 Pending 적체가 업그레이드를 멈춥니다)
- **이벤트 캘린더 대조**: 트래픽 피크·마감일과 겹치지 않게 — budgets/updateConfig로 "야간만" 같은 창 설정
- **PDB 전수 점검의 자동화**: disruptionsAllowed=0 스캔(35 lab-01)을 preflight 스크립트에 — 사람이 까먹는 항목 1순위
- **관측 스택 우선 검증**: 업그레이드 직후 첫 확인은 앱이 아니라 **눈**(12) — 35의 사고 사례를 절차로 반영

## 6. 소스/도구에서 확인하기

- EKS 버전 수명주기·연장 요금: AWS 문서 "Amazon EKS Kubernetes versions"
- insights API: `aws eks list-insights / describe-insight`
- Karpenter drift: karpenter.sh docs "Drift"
- eksctl 업그레이드 절차: `eksctl upgrade cluster` (CP) — CloudFormation 기반(02)

## 요약 카드

| 질문 | 답 |
|------|----|
| 버전 정책의 기본형? | 최신-1 유지, 분기 1회 — 문서로 박제 |
| insights의 사각? | 미배포 매니페스트(Pluto), 서드파티 지원 여부(릴리스 노트) |
| 분할 실행의 근거? | skew 3마이너 — CP와 노드를 다른 날에 |
| 플릿 5전략? | 롤링/Blue-Green/Karpenter drift/Fargate 재배포/Auto Mode 위임 |
| Blue/Green의 값과 비용? | 즉시 롤백·사전 검증 ↔ 이주 기간 2배 용량 |
| 대규모 산수? | 노드당 drain 시간 × 대수 ÷ 동시성 + 용량 여유(13) |
