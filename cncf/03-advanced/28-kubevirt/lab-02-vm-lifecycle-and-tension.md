# Lab 02 — VM 수명주기와 K8s 모델과의 긴장

VM을 켜고 끄고 상태를 확인하며, K8s의 무상태 전제와 VM의 상태성이 어디서 부딪히는지 봅니다.

전제: lab-01의 클러스터(kind: kubevirt), testvm.

## Step 1. VM 수명주기 — Deployment와 다릅니다

```bash
echo "=== VM 상태 ==="
kubectl get vm testvm
kubectl get vmi testvm 2>/dev/null

echo ""
echo "=== running: false로 VM 끄기 (Deployment의 scale 0 같지만 다릅니다) ==="
virtctl stop testvm 2>/dev/null || kubectl patch vm testvm --type merge -p '{"spec":{"running":false}}'
sleep 15
kubectl get vm testvm
kubectl get vmi testvm 2>/dev/null || echo "→ VMI 사라짐 (VM은 정의로 남아있음)"

cat <<'EOF'
차이 (theory §3):
  Deployment replicas=0: Pod 사라짐, 정의 유지 → 다시 켜면 새 Pod (무상태)
  VirtualMachine running=false: VMI 사라짐, VM 정의 유지 → 다시 켜면...
    containerDisk면: 초기화된 상태 (무상태 이미지)
    PVC면: 이전 디스크 상태 유지 (상태 보존) ★
EOF
```

## Step 2. 상태의 무게 — containerDisk vs PVC

```bash
cat <<'EOF'
=== 스토리지가 상태를 정합니다 (theory §4) ===

[containerDisk] — 무상태 (컨테이너처럼)
  이미지에 담긴 디스크, 재시작 시 초기화
  용도: 골든 이미지, 임시 VM, 테스트
  → 우리 testvm이 이것 (재시작하면 초기 상태)

[PVC/DataVolume] — 상태 보존 (진짜 VM처럼)
  영속 디스크, VM을 꺼도 디스크 유지
  용도: 실제 워크로드 (레거시 앱의 데이터)
  → 05의 블록 스토리지(RWO)가 자연스러움

DataVolume (CDI):
  기존 VM 디스크(qcow2)·ISO·클라우드 이미지를 PVC로 import
  clone: 골든 이미지에서 VM 복제 (VM 팜의 프로비저닝)

★ 실제 KubeVirt 운영의 핵심이 스토리지 (09·05의 스테이트풀 판단 극대화)
EOF
```

## Step 3. 노드 드레인 = 라이브 마이그레이션 (k8s 35의 확대)

```bash
cat <<'EOF'
=== 컨테이너와 VM의 결정적 차이 (theory §5) ===

[컨테이너] 노드 드레인(k8s 35):
  Pod evict → 다른 노드에 새 Pod 생성 (상태 없으니 저렴)

[VM] 노드 드레인:
  VM을 죽이면 메모리·상태 손실 → 라이브 마이그레이션 필요
  실행 중 VM의 메모리를 다른 노드로 복사 (반복 dirty page)
  → 마지막에 짧게 멈추고 전환 (downtime 최소화)

요구:
  공유 스토리지(RWX PVC) 또는 스토리지 마이그레이션
  노드 간 네트워크 대역 (메모리 크면 오래 걸림)
  마이그레이션 정책 (VirtualMachineInstanceMigration)

★ k8s 35의 노드 업그레이드가 VM에게는 마이그레이션 오케스트레이션
  PodDisruptionBudget + 마이그레이션 (09의 StatefulSet 교훈의 확대판)
EOF

# 라이브 마이그레이션 CRD 확인
kubectl get crd | grep -i migration | head -2
```

## Step 4. 긴장의 목록 — K8s 전제 vs VM 성질

```bash
cat <<'EOF'
=== K8s 전제 vs VM 성질 (theory, guide) ===
| K8s 전제 | VM 성질 | KubeVirt의 완화 |
|----------|---------|-----------------|
| 무상태 | 상태 있음 | PVC/DataVolume, 스냅샷 |
| 재생성 저렴 | 재생성 비쌈(부팅) | running on/off, 라이브 마이그레이션 |
| 수명 짧음 | 수명 김(몇 달) | VM 정의 영속 |
| Pod 이동 자유 | 이동=마이그레이션 | VMIMigration |
| 수평 확장 | 수직 확장 흔함 | CPU/메모리 hotplug(일부) |
| 헬스체크=재시작 | 재시작=상태 재구성 | liveness 신중히 |

★ KubeVirt는 이 긴장을 완화하지만 없애지 못합니다
  VM은 근본적으로 스테이트풀 → 컨테이너 습관을 그대로 적용하면 사고
EOF
```

## Step 5. 판단 — 언제 KubeVirt를, 언제 아닌가

```bash
cat <<'EOF'
=== 결정 트리 (theory §7) ===

이 워크로드를 컨테이너화할 수 있나요?
  Yes → 컨테이너화하세요 (재작성 비용 < 장기 VM 운영 비용인 경우 대부분)
  ↓ No (레거시·특수 OS·커널 모듈·하드웨어·완전격리)

컨테이너와 VM을 하나의 K8s API로 통합 관리하고 싶나요?
  Yes + K8s·가상화 양쪽 운영 역량 있음 → KubeVirt
  No (대규모 VM 팜, 전용 하이퍼바이저가 성숙) → vSphere 등 유지

★ KubeVirt는 종종 '다리'다:
  레거시를 KubeVirt로 K8s에 올림 → 점진적으로 컨테이너화 → VM 제거
  "목적지가 아니라 마이그레이션 경로"인 경우가 많습니다 (guide)

대가 (정직하게):
  복잡도 2배 (K8s + 가상화 지식)
  스토리지·백업·마이그레이션이 핵심 운영 부담
  중첩 가상화 or 베어메탈 필요
EOF
```

## Step 6. 08의 사다리에서의 자리 재확인

```bash
cat <<'EOF'
=== 08의 5단 주민 재정리 ===
Knative     → 워크로드(서빙) 위의 추상 (스케일 투 제로)
Dapr        → 앱 코드(런타임) 위의 추상 (사이드카 API — 29)
Crossplane  → 클라우드 인프라 위의 추상 (41)
Backstage   → 조직 위의 추상 (42)
KubeVirt    → VM 위의 추상 ← 이 모듈

공통점: 전부 "K8s 위에 무언가를 얹는다"
KubeVirt의 특이점: 얹는 것이 "컨테이너 네이티브가 아닌 것(VM)"
  → 08의 추상 누수가 여기서 심합니다 (VM 문제 = K8s + 가상화 둘 다 디버깅)
EOF
```

## Step 7. 산출물

```markdown
# KubeVirt 판단 카드
## 언제
- 컨테이너화 불가(레거시·특수OS·커널·하드웨어·완전격리)
- 컨테이너+VM 통합 관리 원함 + 양쪽 운영 역량
- 종종 '다리': 레거시→KubeVirt→점진 컨테이너화

## 언제 아닌가
- 컨테이너화 가능한데 편의로 VM (재작성이 대개 이득)
- 대규모 VM 팜 (전용 하이퍼바이저)
- K8s·가상화 양쪽 역량 부족 (복잡도 2배)

## 운영 핵심 (긴장 완화)
- 스토리지: PVC/DataVolume(상태), 블록 RWO (05·09)
- 노드 드레인 = 라이브 마이그레이션 (k8s 35 확대), PDB 필요
- 백업: VM 스냅샷 + 디스크 백업 (k8s 36)
- 컨테이너 습관(무상태·재생성) 금지 — VM은 스테이트풀
```

## 정리

```bash
bash cleanup.sh
```
