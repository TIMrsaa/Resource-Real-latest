# 학습 가이드 — "운영 지식을 코드로" 의 실체

## Operator란 결국

"이 소프트웨어를 운영하는 사람이 매일 하는 일(설치, 설정 동기화, 백업, 장애 복구)을 reconcile 루프 안에 코드로 적은 것"입니다. Prometheus Operator, Strimzi(Kafka), CloudNativePG — cncf 파트에서 만날 거물들이 전부 이 구조이고, 이 모듈에서 그 뼈대를 직접 만들어봅니다.

## kubebuilder가 대신 해주는 것 / 우리가 짜는 것

| kubebuilder/controller-runtime이 처리 | 우리가 짜는 것 |
|----------------------------------------|----------------|
| informer/캐시/workqueue (모듈 31의 그것) | **Reconcile(ctx, req) 함수 하나** |
| CRD YAML 생성 (Go 타입에서!) | API 타입 struct (spec/status 필드) |
| RBAC YAML 생성 (마커 주석에서) | 마커 한 줄 (`+kubebuilder:rbac:...`) |
| 리더 선출, 메트릭, 헬스 엔드포인트 | 비즈니스 로직 |

**"이벤트가 아니라 상태"가 제 1 원칙**: Reconcile은 "무엇이 바뀌었는지" 듣지 않습니다 — 호출되면 "현재 전체 상태를 보고 원하는 상태로 수렴"시킵니다. 같은 입력에 몇 번을 불려도 같은 결과(멱등). 이 원칙만 지키면 재시도/중복 호출/재기동이 전부 공짜로 안전해집니다.

## 개발 루프

```
make manifests && make install    # Go 타입 → CRD 생성/설치
make run                          # 컨트롤러를 "내 노트북에서" 실행 (kubeconfig로 EKS 조정!)
kubectl apply -f sample.yaml      # 다른 터미널에서 CR 생성 → 로그로 reconcile 관찰
```

컨트롤러가 클러스터 안에 있을 필요가 없다는 것(로컬 프로세스도 watch/update 가능)이 개발을 빠르게 합니다 — 배포(이미지 빌드)는 다 만든 후의 일.

## Go가 처음이라면

struct, 포인터, error 처리, defer 정도만 알면 따라옵니다. 코드를 "베껴 치며" 패턴을 익히는 것도 이 단계에선 유효한 전략 — 기여자 트랙(42)에서 본격적으로 읽기 근육을 키웁니다.
