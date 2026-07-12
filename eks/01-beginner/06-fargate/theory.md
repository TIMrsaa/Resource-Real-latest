# 이론 — Fargate 실행 모델, 프로파일, 제약과 요금

> **🌱 17세 눈높이 비유: 단체 숙소 vs 1인 캡슐호텔**
> 노드그룹은 **단체 숙소**입니다 — 방(노드)을 빌려 여러 명(Pod)이 나눠 씁니다. 방 관리는 내가, 시끄러운 룸메이트 문제도 내가.
> Fargate는 **캡슐호텔**입니다 — 투숙객(Pod) 한 명당 캡슐 하나가 **체크인 순간 생깁니다**. 룸메이트 없음(완전 격리), 방 관리 없음. 대신:
> - 캡슐 크기는 정해진 규격뿐 (요청한 것보다 큰 캡슐로 **반올림** — 그만큼 과금)
> - 모든 캡슐에 들러야 하는 청소부(DaemonSet)는 출입 불가
> - 내 짐을 방에 영구 보관(hostPath/EBS) 불가 — 외부 짐 보관소(EFS)만

---

## 1. 실행 모델 — Pod 하나, VM 하나

```
일반:    노드(EC2/VM) 1대 위에 Pod 여러 개 (커널 공유 — k8s 01의 그 원리)
Fargate: Pod 1개 = Firecracker 마이크로VM 1개 (커널도 전용)
         → kubectl get nodes에 Pod마다 "가상 노드"(fargate-ip-...)가 하나씩 보입니다
```

격리 관점의 의미: k8s 32에서 "컨테이너는 프로세스 격리일 뿐"이라 했던 한계가 **VM 경계로 올라갑니다** — 컨테이너 탈출에 성공해도 그 VM 안이고, 이웃 Pod이 없습니다. PCI/멀티테넌트급 격리 요건의 정답 후보.

## 2. 스케줄링 경로 — 누가 Fargate로 보내나

```
① Fargate 프로파일: "어떤 Pod가 Fargate 대상인가"의 규칙
   selectors: [{ namespace: serverless, labels: {...} }]   ← ns 필수, 라벨 선택
② Pod 생성 → EKS의 mutating webhook(k8s 23!)이 프로파일 매칭 시
   schedulerName을 fargate-scheduler로 바꿔치기
③ fargate-scheduler가 마이크로VM 프로비저닝 → 그 위에 Pod 단독 배치
```

→ k8s 25(멀티 스케줄러)에서 배운 "schedulerName이 다르면 다른 스케줄러가 줍는다"의 관리형 실사례. 매칭 안 되면 평소처럼 일반 노드로 — **같은 클러스터에서 노드그룹/Auto Mode/Fargate가 공존**합니다.

## 3. 사이징과 요금 — 반올림의 경제학

- Pod의 **requests 합**(전 컨테이너+사실상 오버헤드)을 보고, 지원되는 vCPU/메모리 조합표로 **올림**
  (예: 0.3 vCPU/600Mi 요청 → 0.5 vCPU/1GB 슬롯 — 그 슬롯 요금)
- 과금 = Pod별 (vCPU·초 + GB·초), 이미지 풀 시작부터 종료까지
- limits는 의미 약함(슬롯이 곧 한계), **requests가 곧 청구서** — k8s 09의 requests 정확화가 여기선 직접 돈입니다

손익 감각: 상시 가동 대량 Pod → EC2(노드그룹)가 싸다 / 간헐·소량·스파이크(Job, 야간 배치, 저트래픽 서비스) → Fargate가 단순+저렴할 수 있습니다. 정밀 비교는 22에서.

## 4. 제약 목록 — "노드 없음"의 청구서

| 안 되는 것 | 이유 | 대안 |
|-----------|------|------|
| DaemonSet | 설 노드가 없습니다 | 사이드카로 (로그 수집 등) |
| hostPath/hostNetwork/hostPID | 호스트가 없습니다 | — (설계 변경) |
| privileged | VM이어도 금지 | — |
| **EBS PVC** | 노드 수명=Pod 수명이라 블록 부착 부적합 | **EFS만 지원** (10) |
| GPU | 미지원 | 노드그룹/Auto Mode (19) |
| 이미지 캐시 | VM이 매번 새것 | 시작 느림(이미지 풀 매번) — 이미지 슬림화 |
| 노드 접근/커스텀 | 당연히 불가 | — |

추가 특성: 시작 지연(VM 프로비저닝+풀 ~수십 초), 로그는 **Fluent Bit 내장 설정**(aws-logging ConfigMap)으로 CloudWatch에, 보안 패치는 AWS가 투명하게(재배포 권고 이벤트).

## 5. 3자 비교 (이 모듈의 결론, lab-02에서 완성)

| 기준 | 노드그룹(05) | Auto Mode(04) | Fargate(06) |
|------|--------------|---------------|-------------|
| 노드 운영 | 내가 | AWS | 개념 없음 |
| 커스터마이즈 | 최대 | 제한 | 최소 |
| DaemonSet | O | O | **X** |
| EBS | O | O(내장) | **X (EFS만)** |
| 격리 수준 | 커널 공유 | 커널 공유 | **VM 격리** |
| 과금 | EC2 | EC2+수수료 | Pod 단위(반올림) |
| 어울림 | 특수/통제 | 표준의 기본값 | 격리 요건, 간헐 워크로드 |

## 6. 소스/도구에서 확인하기

- Fargate 문서/제약: https://docs.aws.amazon.com/eks/latest/userguide/fargate.html
- Pod 사이징 조합표: 같은 문서의 "Pod configuration"
- Firecracker (기반 기술, 오픈소스): https://firecracker-microvm.github.io/

## 요약 카드

| 질문 | 답 |
|------|----|
| 실행 모델? | Pod 1 = 마이크로VM 1 (가상 노드로 보임) |
| Fargate로 가는 경로? | 프로파일 매칭 → webhook이 schedulerName 교체 |
| 최대 제약 2개? | DaemonSet 불가, EBS 불가(EFS만) |
| 요금의 핵심? | requests가 슬롯으로 **올림** — requests=청구서 |
| 고유의 강점? | VM 격리 (멀티테넌트/규제 워크로드) |
| Auto Mode 시대의 자리? | 격리 요건 + Pod 단위 과금이 맞는 패턴 |
