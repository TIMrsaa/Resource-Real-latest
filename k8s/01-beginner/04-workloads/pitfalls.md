# 흔한 함정 5선

## 1. `:latest` 태그 + apply = 배포 안 됨

template이 동일하면 트리거가 없습니다 (theory §3). 새 이미지를 푸시해도 클러스터는 모릅니다. 게다가 노드에 이미 캐시된 latest가 있으면 pull도 안 합니다(`imagePullPolicy` 기본값이 latest일 땐 Always지만, 버전 태그일 땐 IfNotPresent). **불변 태그(v1.2.3, git SHA)가 정답.**

## 2. readinessProbe 없는 롤링 업데이트

probe가 없으면 "컨테이너 시작 = Ready"로 간주 → 앱이 아직 부팅 중인데 옛 Pod를 지워버림 → 배포 때마다 수 초간 에러. "무중단 배포"는 RollingUpdate 전략이 아니라 **probe가 만듭니다.**

## 3. selector 수정 시도

`spec.selector`는 생성 후 **불변**입니다. 바꾸려고 하면 에러. 라벨 체계를 바꾸려면 Deployment를 지우고 다시 만들어야 합니다 — 처음 라벨 설계를 신중히 (관례: `app`, `app.kubernetes.io/name` 등 표준 라벨 세트).

## 4. 여러 Deployment의 selector 겹침

Deployment A와 B의 selector가 같은 라벨을 가리키면 서로의 Pod를 자기 것으로 세서 무한 생성/삭제 싸움이 납니다. 네임스페이스 안에서 selector는 사실상 고유해야 합니다. `pod-template-hash` 라벨이 자동으로 붙어 RS끼리는 충돌을 피하지만, 사용자가 만든 selector 겹침까지 막아주진 않습니다.

## 5. replicas를 YAML과 HPA가 동시에 관리

YAML에 `replicas: 3`을 적어두고 HPA도 켜면, apply할 때마다 HPA가 늘려놓은 수가 3으로 리셋됩니다(순간 Pod 대량 종료). HPA를 쓰는 Deployment는 **YAML에서 replicas 필드를 아예 제거**하는 것이 표준 (모듈 13에서 재론).

## 실무 사고 사례

> 금요일 오후 배포에서 새 버전이 ErrImagePull. 당황한 담당자가 "롤백해야지" 하며 **Deployment를 삭제**했습니다 — 옛 RS까지 연쇄 삭제(ownerReferences)되며 서비스 전면 중단. 정답은 `kubectl rollout undo` 한 줄이었습니다 (lab-02 Step 4처럼 옛 버전은 멀쩡히 살아 있었습니다). **삭제는 롤백이 아닙니다.**
