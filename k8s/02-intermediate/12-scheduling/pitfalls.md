# 흔한 함정 5선

## 1. toleration만 주고 "전용 노드" 완성으로 착각

lab-01 Step 4의 그 장면. toleration은 입장권일 뿐 — GPU Pod가 일반 노드에 가서 GPU를 못 찾고 죽거나, 비싼 GPU 노드가 놀게 됩니다. **taint + toleration + nodeAffinity 3종 세트**가 공식.

## 2. requiredAffinity 남발 → 새벽 Pending 사태

"같은 zone에 있는 캐시 노드 필수" 같은 required 조건은 노드 구성이 바뀌는 순간(스케일인, Spot 회수) 신규 Pod 전원 Pending을 만듭니다. 진짜 불변 조건(아키텍처, 라이선스, 컴플라이언스)만 required로, 성능 선호는 preferred로.

## 3. podAntiAffinity required + replicas > 노드 수

"전부 다른 노드에"(hostname anti-affinity required)인데 replicas 5, 노드 3대면 2개는 영원히 Pending. 노드 수와 결합된 제약임을 잊기 쉽습니다 — topologySpread(maxSkew)로 바꾸면 "최대한 고르게"로 유연해집니다.

## 4. hostname spread만 걸고 AZ는 안 거는 경우

노드 단위로 잘 퍼져 있어도 그 노드들이 전부 같은 AZ일 수 있습니다(특히 ASG가 한 AZ에 몰릴 때). 고가용성 목적이면 **zone 기준 spread가 1순위**, hostname은 보조.

## 5. preemption을 모든 워크로드에 허용

배치 작업에 높은 priority를 주면 서로 선점하는 카오스가 됩니다. 계층 설계: 시스템(내장) > 핵심 서비스 > 기본 > 배치(`preemptionPolicy: Never`). 그리고 PriorityClass 없는 Pod의 기본값은 0 — 핵심 서비스에 명시적으로 부여하지 않으면 보호받지 못합니다.

## 실무 사고 사례

> 신규 서비스가 출시 직후 트래픽 폭증으로 스케일아웃 — 그런데 모든 replicas가 같은 AZ에 있었고(spread 미설정 + 그 AZ에만 여유 노드), 다음날 해당 AZ 장애로 서비스 전체가 5분간 다운. 같은 클러스터에서 spread를 설정한 옆 팀 서비스는 1/3만 잃고 버텼습니다. 교훈: **`topologySpreadConstraints`(zone, maxSkew=1)는 운영 서비스의 기본 탑재 장비입니다.** Deployment 템플릿/Helm 차트 공통부에 박아두라.
