# 자가 점검 퀴즈

**Q1.** `exec format error`의 원인과, "이미지 pull은 성공했는데 왜?"에 대한 답은?

**Q2.** multi-arch manifest의 구조와, 노드가 자기 판본을 얻는 메커니즘은?

**Q3.** Graviton 마이그레이션의 안전한 5단계 순서는? 어디서 13(측정)이 개입하나요?

**Q4.** Pod 안 컨테이너가 앱+사이드카 구성일 때 arch 전환에서 확인할 범위는? 이유는?

**Q5.** device plugin이 하는 일을 "등록"의 관점에서 설명하세요 — 플러그인이 없으면 GPU 노드는 어떻게 보이나요?

**Q6.** extended resource가 CPU/메모리와 다른 두 가지 규칙과 그 이유는?

**Q7.** time-slicing과 MIG의 차이를 격리 관점에서 — 각각 어떤 워크로드에 맞나요?

**Q8.** GPU 비용 관리의 세 가지 장치(스케줄링/자동화/관측 각 1개)를 앞 모듈 번호와 함께 들라.

---

## 정답

**A1.** 이미지의 바이너리가 노드 CPU 아키텍처와 불일치(amd64 바이너리를 arm64에서 실행). 레지스트리와 kubelet의 pull은 arch를 검증하지 않으므로 다운로드는 성공하고 — **첫 exec 순간** 커널이 형식을 못 읽어 실패합니다. 그래서 증상이 ImagePullBackOff가 아니라 CrashLoopBackOff입니다.

**A2.** 태그 하나가 manifest list(표지)를 가리키고, 그 안에 arch별 이미지 다이제스트 목록(amd64/arm64…)이 있습니다. 노드의 containerd가 자기 플랫폼에 맞는 다이제스트를 골라 pull — 배포자는 태그 하나만 쓰면 됩니다. 검사는 `skopeo inspect --raw`/`docker manifest inspect`.

**A3.** ① 이미지 전수조사(사이드카까지) ② CI를 multi-arch 빌드로 ③ arm 노드 소수 투입 ④ 카나리아 + **측정**(동일 부하에서 amd vs arm의 goodput/p99/오류율 + 단가 → 순절감 계산) ⑤ 확대·selector 완화. 측정 없는 ④→⑤ 건너뛰기가 대표적 사고.

**A4.** **Pod 안 모든 컨테이너**(앱, 사이드카, init, 에이전트) — Pod는 하나의 노드에 통째로 배치되므로 컨테이너들이 같은 arch를 공유합니다. 하나라도 단일 arch면 Pod 전체가 그 arch에 묶이거나 깨집니다.

**A5.** device plugin은 노드의 장비를 발견해 kubelet에 **extended resource로 신고**합니다(`nvidia.com/gpu: N`) — 그래야 스케줄러의 자원 계산에 들어갑니다. 없으면: 드라이버가 있어도 capacity에 항목 자체가 없어 "GPU 요청 Pod는 영원히 Pending, 노드는 그냥 큰 CPU 노드"가 됩니다. 하드웨어가 아니라 등록이 스케줄링의 실체.

**A6.** ① 정수 단위만(0.5장 불가 — 기본) ② 오버커밋 불가(requests=limits 강제). 이유: CPU처럼 시분할로 나눠 쓰는 자원이 아니라 **통째로 점유하는 장비**라서 — 부분 할당·초과 약속의 의미가 없습니다(공유가 필요하면 time-slicing/MIG라는 별도 메커니즘).

**A7.** time-slicing: 장부상 분할만 — 메모리·연산 격리 없음(이웃 OOM 전파). 같은 신뢰 경계 안의 가벼운 추론·개발용. MIG: A100/H100급의 하드웨어 분할 — 조각별 메모리·SM 격리. 멀티테넌트/프로덕션 추론용. "커널 공유 = 격리 아님"(34)의 GPU 버전.

**A8.** ① 스케줄링: taint로 GPU 노드 점유 방지 + 학습 Job에 do-not-disrupt(17). ② 자동화: 큐 기반 scale-to-zero(KEDA — 15) 또는 Karpenter 수요 기반 생성/회수(17). ③ 관측: GPU 사용률 저조 알람 + 노드그룹 잔재 주기 스캔(12).
