# 자가 점검 퀴즈

**Q1.** Pod 생성 시 kubelet의 첫 CRI 호출과 그 안에서 일어나는 일 2가지는?

**Q2.** crictl이 노드 디버깅에서 신뢰할 수 있는 근본 이유는?

**Q3.** crictl로 컨테이너를 지웠더니 곧 새 컨테이너가 떴습니다. 메커니즘을 설명하세요. (관여 부품 2개)

**Q4.** QoS 3클래스의 결정 기준과 eviction 순서는?

**Q5.** OOMKilled와 Evicted의 차이 4가지(집행자/이유/단위/대응)는?

**Q6.** static Pod의 진실 원본은 어디이며, kubeadm 클러스터에서 어떤 닭-달걀 문제를 푸는가요?

**Q7.** `kubectl exec`가 컨테이너 셸에 닿기까지의 경로는?

**Q8.** "PLEG is not healthy" 로그의 의미와 의심 지점은?

---

## 정답

**A1.** **RunPodSandbox** — ① pause 컨테이너 생성으로 Pod의 namespace 세트 확보 ② **CNI ADD 호출**로 Pod IP 부여/네트워크 연결.

**A2.** kubelet이 쓰는 것과 **동일한 CRI gRPC 소켓**으로 런타임에 질의하므로 — kubelet이 보는 세상(sandbox, 컨테이너, 이미지)을 그대로 봅니다.

**A3.** **PLEG**가 런타임에서 컨테이너 소멸을 감지해 syncLoop에 알림 → **SyncPod**가 "선언 상태(컨테이너 1개)와 현실(0개)"의 차이를 보고 CreateContainer/StartContainer로 재생성. kubelet 자신이 조정 루프라는 증거.

**A4.** 기준: requests/limits 조합 — 모두 같으면 Guaranteed, 일부라도 requests<limits면 Burstable, 둘 다 없으면 BestEffort. eviction 순서: **BestEffort → Burstable(요청 대비 초과 사용 큰 순) → Guaranteed.**

**A5.** OOMKilled: **커널**이 / **컨테이너의 limits 초과** 때문에 / **컨테이너** 단위로 처형 / 대응은 limits·누수 점검. Evicted: **kubelet**이 / **노드 자원 부족** 때문에 / **Pod** 단위로 축출 / 대응은 requests 정직화·노드 용량.

**A6.** 노드의 **manifest 파일**(staticPodPath). API 서버의 것은 mirror(조회용). kubeadm에서 **apiserver/etcd 자체를 static Pod로** 띄움으로써 "API 서버를 등록할 API 서버가 없는" 부트스트랩 문제를 풉니다.

**A7.** kubectl → API 서버(RBAC: pods/exec 검사) → 해당 노드 **kubelet(10250)** → CRI ExecSync → 런타임이 컨테이너 내 프로세스 실행. (그래서 노드 SSH 없이 되고, API 감사 로그에 남습니다)

**A8.** 런타임 상태 조회(relist/이벤트)가 임계 시간을 초과 — 컨테이너 과다/런타임(containerd) 응답 지연/디스크 IO 병목 의심. 방치 시 노드가 NotReady로 전환됩니다.
