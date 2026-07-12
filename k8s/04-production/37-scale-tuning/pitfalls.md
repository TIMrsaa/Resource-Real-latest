# 흔한 함정 5선

## 1. 폴링 LIST 루프 — 클러스터 살인 1순위

`while true; kubectl get pods -A; sleep 5` 류의 스크립트/사이드카/운영봇. 작을 땐 티가 안 나다가 객체 수가 늘면 API 서버 메모리를 출렁이게 하고 APF 429를 받기 시작합니다. **변경을 알고 싶으면 watch(informer)** — LIST는 시작할 때 한 번입니다(모듈 31). 범인 색출: APF 메트릭에서 어느 FlowSchema 큐가 차는지 → 감사 로그(모듈 21)로 user/agent 추적.

## 2. 완료 객체 시체 방치

Evicted/Completed Pod, 끝난 Job, 옛 ReplicaSet이 수만 개 — etcd를 채우고 모든 LIST를 느리게 합니다. 방어 장치를 처음부터: Job `ttlSecondsAfterFinished`(모듈 20), Deployment `revisionHistoryLimit`, CronJob history limit, Failed Pod 정기 청소. "지워지는 것"은 저절로 안 지워집니다.

## 3. 한 객체에 모두가 watch — hot object

전 노드 DaemonSet이 같은 ConfigMap을 마운트+구독하는데 그 CM을 1분마다 갱신하는 설계 — 갱신 1건 × 노드 수만큼 watch 전송이 증폭됩니다(theory §2). 자주 바뀌는 데이터는 K8s 객체가 아니라 **데이터 평면**(S3, 설정 서비스)에. K8s 객체는 "가끔 바뀌는 선언"용입니다.

## 4. 대량 생성을 한 방에

신규 환경 프로비저닝 스크립트가 ns 200개 × 리소스 50개를 일제 투하 — 스케줄러 적체 + 컨트롤러 폭주 + (EKS면) ENI/IP 할당 폭주(모듈 27)까지 삼중 충돌. 대량 작업은 **배치로 끊어서**(예: 500개 단위 + 대기), 그리고 가능하면 GitOps 도구의 동기화 물결(wave)에 태워 점진 투입.

## 5. "노드를 늘리면 빨라진다"는 착각

API가 느려서 노드를 늘렸습니다 — 노드가 늘수록 kubelet watch/하트비트가 늘어 **control plane 부하는 오히려 증가**합니다. 병목이 어느 층인지(theory §6 분업표) 먼저 진단하세요: etcd 객체 수인가, expensive LIST인가, 스케줄러 처리량인가. 층을 모르고 만지는 스케일링은 불에 부채질일 수 있습니다.

## 실무 사고 사례

> 평화롭던 800노드 클러스터가 어느 월요일부터 kubectl이 간헐적으로 30초씩 걸렸습니다. 노드 증설(→악화), CoreDNS 증설(무관)을 거쳐 APF 메트릭을 본 뒤에야: 금요일에 배포된 사내 "비용 리포트 봇"이 **30초마다 전체 리소스 8종을 full LIST** 하고 있었습니다. 객체 60만 개 직렬화가 반복되며 API 서버 메모리가 출렁였고, global-default 큐에 일반 사용자들의 kubectl이 같이 갇혔던 것. informer 기반으로 재작성 후 정상화. 교훈: ① 증상(전원 느림)과 범인(클라이언트 하나)은 따로 있다 ② APF 메트릭/감사 로그가 범인 색출 도구 ③ 사내 도구도 클라이언트 매너 리뷰 대상.
