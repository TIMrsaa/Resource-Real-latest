# 자가 점검 퀴즈

**Q1.** kube-prometheus-stack의 구성 요소와 Operator 패턴이 주는 효과는?

**Q2.** ServiceMonitor의 매칭 3연쇄는? 어긋나면 어떻게 되고, 어떻게 감지하나요?

**Q3.** 익스포터 3대장의 관점 구분과 질문→소스 매핑 예시 셋은?

**Q4.** relabelings와 metricRelabelings의 차이는? drop이 "저장 전"이라는 것이 왜 중요한가?

**Q5.** sampleLimit은 무엇을 보호하나요? 03의 사고와 연결하세요.

**Q6.** recording rule의 두 가지 가치와 명명 관례는?

**Q7.** retention을 늘리는 것이 장기 저장의 답이 아닌 이유와 올바른 아키텍처는?

**Q8.** "알림이 침묵한" 사고의 원인과 recording rule 중심 재편의 내용은?

---

## 정답

**A1.** 구성: Prometheus Operator(CRD 감시·설정 생성의 두뇌), Prometheus 서버(StatefulSet), Alertmanager(10), Grafana(09), node-exporter(DS), kube-state-metrics, 기본 ServiceMonitor들(컨트롤 플레인·kubelet 자동 수집), 기본 PrometheusRule들. Operator 패턴의 효과: 수동 scrape_configs 편집 대신 CRD(ServiceMonitor 등)로 선언하면 Operator가 설정을 생성·적용합니다 — 수집 등록이 **셀프서비스**가 되어(앱 팀이 자기 ns에 SM 배포 → 자동 수집) 중앙 설정 파일 병목이 사라집니다(cncf 08의 오퍼레이터 + 47의 셀프서비스 정신).

**A2.** ① Prometheus.spec.serviceMonitorSelector ↔ ServiceMonitor의 라벨(관례: release=<릴리스명>), ② ServiceMonitor.spec.selector ↔ Service의 라벨, ③ endpoints.port(포트 **이름**) ↔ Service.ports[].name. 하나라도 어긋나면 **에러·이벤트 없이 조용히** 타깃에서 빠집니다(lab-01에서 체험). 감지: 타깃 목록 확인 + `up{job=...}` 존재 확인 + `absent(up{job=...})` 알림으로 "조용한 미수집"을 시끄럽게 만들고, 신규 서비스 온보딩 체크리스트에 타깃 등록 확인을 포함합니다.

**A3.** node-exporter(DaemonSet) — "기계"의 관점: 노드 OS의 CPU·메모리·디스크·네트워크. kube-state-metrics(KSM) — "K8s 오브젝트 상태"의 관점: API의 상태를 메트릭으로 번역(phase·replicas·restarts — 사용량이 아님!). cAdvisor(kubelet 내장) — "컨테이너 사용량"의 관점: container_cpu/memory. 매핑 예: "Pending Pod 몇 개?"→KSM(kube_pod_status_phase), "그 Pod가 OOM 직전인가요?"→cAdvisor(working_set vs limits, 조인), "노드 디스크 언제 차나요?"→node-exporter(predict_linear).

**A4.** relabelings는 스크레이프 **전** 타깃 수준 조작(대상 필터·타깃 라벨 추가·rename)이고, metricRelabelings는 스크레이프 **후 저장 전** 메트릭 수준 조작(drop/keep으로 메트릭 폐기, labeldrop으로 라벨 제거)입니다. "저장 전"이 중요한 이유: 카디널리티 비용(메모리·저장)은 TSDB에 들어가는 순간 발생하므로, 들어가기 전에 잘라야 예방이 됩니다 — 저장 후 admin API 삭제는 이미 비용을 치른 뒤의 응급처치일 뿐입니다(03 사고에서 롤백해도 기존 시계열이 부담으로 남았던 이유). 06의 로그 grep 필터와 같은 "소스 수문" 사상입니다.

**A5.** sampleLimit은 타깃당 샘플 수 상한으로, 초과하는 타깃의 스크레이프를 **통째로 실패**시켜(up=0) 그 타깃의 폭발이 전체 TSDB로 유입되는 것을 차단합니다 — 폭발 반경을 타깃 하나로 자르는 안전벨트입니다. 03의 사고(테넌트 라벨 8,000개로 시계열 폭발 → Prometheus OOM 루프 → 관측 전면 장애)에서, sampleLimit이 있었다면 문제의 앱 타깃만 수집 실패(알림 발생)하고 Prometheus 본체와 다른 서비스의 관측은 살아남았을 것입니다. "사고는 막지 못해도 반경을 줄입니다."

**A6.** 가치 ①: 성능 — 비싼 쿼리(histogram_quantile 등)를 주기 계산해 저장하므로 대시보드·알림이 가벼운 조회만 합니다(계산 1회, 소비 N회). 가치 ②: **정의의 단일화** — 조직의 에러율·p99가 하나의 시계열로 존재해 모두가 같은 정의를 소비합니다(팀마다 쿼리가 갈라지는 것을 방지 — 사고 사례의 핵심 교훈). 명명 관례: `level:metric:operations`(예: service:http_error_ratio:rate5m) — 집계 수준·원본 메트릭·연산이 이름에서 읽힙니다. 주의: rule도 시계열을 만들므로 소비되는 것만 정의합니다.

**A7.** 단일 Prometheus는 로컬 디스크 기반 단일 노드라 장기(수개월~년)·대규모 보존에서 디스크·메모리·블록 관리가 감당되지 않습니다(cncf 11의 벽 — 확장 한계). 올바른 아키텍처는 역할 분담: 로컬 Prometheus는 짧은 보존(며칠~몇 주)의 "뜨거운" 조회·알림용으로 두고, 장기·대규모는 remote_write로 외부에 위임합니다 — 관리형 AMP(14)나 Thanos/Mimir(24, 오브젝트 스토리지 기반 장기 저장·글로벌 쿼리). retention은 설정값 문제가 아니라 아키텍처 문제입니다.

**A8.** 원인: "에러율"이라는 같은 이름이 팀·대시보드·알림마다 다른 수식이었습니다 — 분모 차이(전체 vs 2xx+5xx), 창 차이(1m vs 15m), 집계 수준 차이(인스턴스별 알림은 Pod 교체로 시계열 리셋되어 불안정). 장애가 4xx 급증형이라 알림의 정의로는 임계 미달 → 침묵. 재편: ① 표준 SLI를 recording rule로 단 하나만 정의(GitOps 관리)하고 대시보드·알림은 그 시계열만 소비, ② level:metric:op 명명 관례와 rule PR 리뷰, ③ rule 주석으로 분모·분자 포함 범위를 명문화, ④ 알림은 반드시 서비스 수준 집계(sum by service) 위에. 교훈: recording rule의 진짜 가치는 정의의 단일화이며, 쿼리 복붙은 정의의 분기입니다.
