# 흔한 함정 5선

## 1. CRD 스키마를 대충 (검증 없는 free-form)

`x-kubernetes-preserve-unknown-fields: true`로 다 받는 CRD — 오타가 조용히 무시되고(`replcas: 3`), 사용자 실수가 컨트롤러 버그처럼 보입니다. 스키마 검증 + CEL은 CRD의 절반입니다. `kubectl explain`이 비어 있는 CRD는 미완성품.

## 2. storage 버전 변경을 가볍게

v1beta1로 저장된 객체들이 etcd에 남은 채 storage를 v1로 바꾸면, 옛 객체는 읽힐 때마다 변환이 필요합니다. 버전 승격 절차(served 추가 → conversion 준비 → storage 전환 → 기존 객체 재저장(storage migration) → 옛 버전 제거)를 건너뛰면 업그레이드 때 터집니다.

## 3. ownerReference를 이름으로만 생각

GC는 **uid**로 결합합니다. 부모를 지웠다 같은 이름으로 재생성하면 uid가 달라져 — 옛 자식들은 "죽은 부모의 자식"으로 GC 대상이 됩니다. "부모 재생성했더니 자식들이 사라졌어요"의 정체. 또한 ownerReference는 **같은 ns**(또는 클러스터 스코프 부모)만 가능 — ns를 넘는 참조는 GC가 즉시 고아 판정합니다.

## 4. finalizer 넣고 제거 로직을 안 짠 컨트롤러

finalizer 추가는 한 줄이지만, 그걸 제거하는 reconcile 경로(deletionTimestamp 감지 → 정리 → 제거)가 없으면 그 리소스는 **영원히 안 지워집니다.** 컨트롤러가 죽은 채 배포 중단되면 전 객체가 Terminating 좀비. finalizer는 "제거 코드와 한 쌍"으로만 추가하세요.

## 5. SSA와 client apply 혼용

같은 객체에 어떤 도구는 `apply`(클라이언트), 어떤 도구는 `apply --server-side` — managedFields가 꼬여 예측 불가능한 병합이 됩니다. 팀/도구 차원에서 한쪽으로 통일 (신규는 SSA 권장, GitOps 도구들도 SSA로 이동 완료).

## 실무 사고 사례

> 플랫폼팀이 CRD 컨트롤러를 새 버전으로 교체하며 옛 컨트롤러를 먼저 삭제했습니다. 옛 컨트롤러의 finalizer(`old.platform.io/cleanup`)를 단 커스텀 리소스 수백 개가 남아 있었고, 사용자들이 리소스를 지우자 전부 Terminating 적체 — 새 컨트롤러는 그 finalizer를 몰랐습니다. ns 삭제까지 연쇄로 막히며 CI 환경 정리가 전사적으로 중단. 복구: 새 컨트롤러에 "옛 finalizer도 제거" 마이그레이션 코드를 긴급 추가. 교훈: **컨트롤러 교체 = finalizer 인수인계 계획 포함.** 죽은 주인의 finalizer는 영원한 족쇄입니다.
