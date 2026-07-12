# 학습 가이드 — "기능을 아는 것"보다 "기능을 찾는 법"

## 이 모듈의 진짜 목표

카탈로그는 금방 낡습니다 (다음 마이너 버전이 6개월 뒤입니다). 그래서 개별 기능 암기보다 **기능 발굴 루틴**을 몸에 붙이는 것이 목표:

```
① 릴리스 블로그 (kubernetes.io/blog의 "Kubernetes v1.NN" 글) — 분기마다 30분 투자
② Feature Gates 전체 표 — "이런 게 있다"의 색인
   https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
③ KEP 저장소 — 기능의 "왜"와 설계 토론 (기여자 트랙 43과 연결)
   https://github.com/kubernetes/enhancements
④ kubectl explain --recursive — 내 클러스터에 실제로 있는 필드의 전수 목록
```

## "되나 안 되나" 판별 루틴

```bash
kubectl explain pod.spec.<필드>            # 필드가 있으면 서버가 압니다
kubectl version                            # 서버 마이너 버전 확인
# EKS는 feature gate를 못 만지므로: GA(기본 on) 기능만 믿어라
# Alpha/Beta는 kind(기여자 트랙)에서: kind 클러스터 설정에 featureGates 지정 가능
```

EKS 학습자의 현실: **Alpha 기능은 그림의 떡, Beta는 버전 따라 다름, GA만 즉시 실전.** 그래서 이 모듈의 lab은 GA(또는 1.36에서 기본 활성) 위주이고, Alpha급(예: 일부 DRA 확장)은 카탈로그에서 "예고편"으로만 다룹니다.

## 읽는 법

theory의 카탈로그는 사전처럼 — 처음엔 훑고, 실무에서 "어 이런 게 필요한데?" 싶을 때 돌아와 찾아라. lab은 그중 임팩트 큰 것들을 직접 만집니다.
