# 학습 가이드 — 관측성 없는 운영은 "감"입니다

## 지금까지 쌓인 부채

k8s 38의 진단 루틴은 **사후 대응**이었습니다 — describe/logs는 장애가 난 뒤의 도구입니다. 그리고 이 파트에서 반복된 말들:

- "ipamd 메트릭을 대시보드에" (07)
- "Degraded 알림을 모니터링에" (k8s 39)
- "Pending 적체 알림" (k8s 37), "노드 헬스" (eks 03)...

전부 "관측성이 있다면"이라는 가정이었습니다. 이 모듈이 그 가정을 현실로 만듭니다 — **Auto Mode(04)처럼 노드 접근이 사라지는 환경에선 관측성이 유일한 눈**이라는 점에서 더 미룰 수 없습니다.

## 두 생태계, 이 모듈의 선택

```
AWS 네이티브:  Container Insights + CloudWatch Logs/Alarms (+X-Ray/ADOT)
              설치 한 줄, 통합 IAM, 콘솔 일원화 — 대신 쿼리/대시보드 자유도와 비용 구조가 AWS식
CNCF 표준:    Prometheus + Grafana + Loki/Tempo (관리형: AMP/AMG)
              사실상 업계 표준, 강력한 쿼리(PromQL) — 운영 부담(또는 관리형 요금)
```

실무는 흔히 혼용(메트릭은 Prometheus, 로그는 CloudWatch 등)입니다. 이 모듈은 **AWS 네이티브로 기본기**를 깔고, Prometheus 생태계는 cncf 파트에서 제대로 — 거기서 15(custom metrics HPA)와도 만납니다.

## 미리 경고: 관측성 비용

CloudWatch는 **수집량(GB) 과금**입니다 — 디버그 로그를 전 Pod에서 쏟으면 관측성 비용이 워크로드 비용을 넘는 사고가 실존합니다. "무엇을 수집할지"의 통제가 lab-02의 한 축인 이유.
