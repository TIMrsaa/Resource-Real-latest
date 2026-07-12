# Lab 02 — 지연 로딩 결합, AI 워크로드, 그리고 도입 판단

P2P와 지연 로딩의 결합, AI 워크로드에서의 가치, 그리고 "언제 필요한가"의 판단을 정리합니다.

전제: lab-01의 개념 이해.

## Step 1. 지연 로딩과 P2P의 결합 (26의 stargz)

```bash
cat <<'EOF'
=== 두 최적화의 결합 (theory §4, 26) ===
26의 지연 로딩 (stargz/nydus):
  이미지 전체를 안 받고 필요한 부분만 lazy pull
  → 큰 이미지도 필요한 것만 받아 빨리 시작 (18의 콜드스타트)

Dragonfly + Nydus (자매 프로젝트):
  Nydus = 이미지 포맷(지연 로딩) + P2P 배포
  → "필요한 조각만" + "그 조각을 P2P로"

두 축의 결합:
  지연 로딩: 받을 '양'을 줄입니다 (필요한 것만)
  P2P: 받는 '경로'를 분산합니다 (노드끼리)
  → 큰 이미지를, 필요한 만큼만, 분산된 경로로

효과 (특히 AI):
  8GB 이미지 → 실제 시작에 필요한 500MB만 (지연 로딩)
  그 500MB도 레지스트리 아닌 노드끼리 (P2P)
  → 콜드스타트 극적 단축 + 레지스트리 부하 최소
EOF
```

## Step 2. AI 워크로드 — Dragonfly가 뜨는 이유

```bash
cat <<'EOF'
=== AI 시대의 인프라 (theory §5) ===
AI 워크로드의 특성:
  거대 이미지: CUDA + PyTorch/TF + 모델 = 수 GB~수십 GB
  대량 동시: 분산 학습 = 수천 노드가 동시에 같은 이미지
  → star 토폴로지로는 학습 시작 전에 레지스트리가 무너집니다

Dragonfly의 확장:
  이미지뿐 아니라 AI 모델·데이터셋 배포로
  → "대용량 파일의 P2P 배포"가 본질
  → 학습 데이터셋(수 TB)도 노드끼리 분산

AI 인프라의 조각들 (여러 모듈 연결):
  02 Volcano: AI 학습 잡 스케줄 (갱 스케줄링)
  02 Karpenter: GPU 노드 프로비저닝
  35 Dragonfly: 이미지·모델·데이터 배포
  18 KEDA: 추론 워크로드 스케일
  → AI 워크로드가 CNCF 생태계의 여러 조각을 요구
  → Dragonfly의 2026 Graduated 배경
EOF
```

## Step 3. 도입 판단 — 규모의 임계

```bash
cat <<'EOF'
=== P2P가 필요한 임계 (theory §6) ===
판단 공식: 노드 수 × 이미지 크기 × 동시성 vs 레지스트리 용량

P2P 불필요 (오버엔지니어링):
  노드 수십 개, 이미지 수백 MB
  → 레지스트리(34)로 충분
  → dfdaemon·scheduler 운영이 이득보다 큼

P2P가 빛나는 곳:
  ✅ 대규모 클러스터 (수백~수천 노드)
  ✅ 대형 이미지 (AI, 큰 앱)
  ✅ 동시 배포 폭발 (오토스케일, 대규모 롤아웃)
  ✅ 엣지·다중 지역 (레지스트리에서 먼 노드)
  ✅ 제한된 레지스트리 대역

측정으로 판단:
  "배포 시 이미지 pull이 병목인가요?"
  - pull 시간 메트릭 (containerd pull duration)
  - 레지스트리 대역·연결 사용률
  - 오토스케일 시 노드 Ready까지 시간(18) 중 pull 비중
  → 넘었으면 P2P, 아니면 오버엔지니어링
EOF
```

## Step 4. 대가 — 정직하게

```bash
cat <<'EOF'
=== Dragonfly 도입의 대가 (theory §6) ===
① 운영 인프라 추가:
   Manager·Scheduler·Seed Peer·dfdaemon(모든 노드)
   → 또 하나의 중요 인프라 (그것이 죽으면 pull 경로 영향)

② P2P 네트워크 복잡도:
   노드 간 통신, 방화벽·네트워크 정책과의 상호작용
   조각 스케줄링·피어 관리

③ 작은 규모에선 이득 없음:
   star로 충분한 규모에 P2P는 순수 오버헤드

④ 디버깅:
   "이미지가 안 온다"가 레지스트리? Seed Peer? P2P? dfdaemon?
   → 진단 층이 하나 늘어남 (26의 진단 체인에 추가)

★ 대부분의 조직은 필요 없습니다:
  Dragonfly는 '스케일의 벽을 만난' 조직의 도구
  그 벽을 안 만났으면 도입하지 마세요 (10의 판단 원칙)
EOF
```

## Step 5. 03 트랙 종합 — Graduated 심층의 마무리

```bash
cat <<'EOF'
=== 03-advanced 트랙(22~35) 종합 ===
네트워크: 22 Cilium(eBPF), 23 Envoy(xDS), 24 Istio, 25 Linkerd
런타임: 26 containerd, 27 CRI-O
워크로드: 28 KubeVirt(VM), 29 Dapr(앱 관심사)
보안: 30 Falco(탐지), 31 OPA(정책), 32 Kyverno, 33 SPIFFE(신원)
저장·배포: 34 Harbor(레지스트리), 35 Dragonfly(P2P)

반복된 주제:
  ① 층 구분 (CRI/OCI, L4/L7, 예방/탐지/강제, 범용/전용)
  ② 신원의 통일 (SPIFFE로 수렴, 공유 시크릿의 종말)
  ③ 정책의 다층 (빌드→레지스트리→admission→런타임)
  ④ 스케일의 벽 (카디널리티, etcd, P2P)
  ⑤ "범위를 좁히는 것도 설계" (CRI-O, Linkerd)
  ⑥ 추상의 대가 (KubeVirt, Dapr — 새 신뢰 지점)
EOF
```

## Step 6. 산출물

```markdown
# Dragonfly 판단 카드
## 결합
- 지연 로딩(26 nydus): 받을 양↓ + P2P: 받을 경로 분산
- AI 대형 이미지·모델·데이터셋의 콜드스타트·병목 해결

## AI 배경
- 거대 이미지 × 대량 동시 노드 → P2P가 빛나는 곳
- AI 인프라 조각: 02(Volcano/Karpenter) + 35(Dragonfly) + 18(KEDA)

## 도입 판단
- 임계: 노드×크기×동시성 vs 레지스트리 용량
- 측정: pull 시간·레지스트리 대역·노드 Ready 시간의 pull 비중
- 필요: 대규모·대형이미지·동시폭발·엣지
- 불필요: 작은 규모 (오버엔지니어링)
- "스케일의 벽을 만났으면 도입, 아니면 하지 마라"
```

## 정리

```bash
bash cleanup.sh
```
