# Lab 01 — 전수 마감: 아직 분류되지 않은 프로젝트를 0으로

02~09에서 분류한 것을 제외하고 **남은 CNCF 프로젝트가 무엇인지** 기계적으로 확인합니다 — 지도의 빈틈을 없애는 작업.

전제: 01 lab-01의 landscape.yml.

## Step 1. 전체 CNCF 프로젝트 목록 확보

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF' > all-projects.txt
import yaml
data = yaml.safe_load(open('landscape.yml'))
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        for it in sub.get('items', []):
            p = it.get('project')
            if p: print(f"{p}\t{it['name']}\t{cat['name']} / {sub['name']}")
EOF
wc -l all-projects.txt
cut -f1 all-projects.txt | sort | uniq -c
```

예상: graduated ~35, incubating 수십, sandbox 다수 — 총 200 안팎.

## Step 2. 지도 트랙에서 다룬 것들 제외 → 잔여 확인

```bash
python3 <<'EOF'
covered = """kubernetes volcano karmada kubeedge openkruise keda karpenter
containerd cri-o kata gvisor wasmedge
cilium coredns envoy istio linkerd contour emissary grpc antrea
rook longhorn openebs cubefs velero
prometheus thanos cortex fluentd fluent-bit jaeger opentelemetry
opa kyverno falco cert-manager spiffe spire in-toto tuf notary harbor
helm argo flux knative dapr crossplane backstage kubevirt operator
etcd nats pulsar strimzi cloudevents tikv vitess
opencost chaos-mesh litmus dragonfly wasmcloud keptn cluster-api""".split()

seen, remaining = set(), []
for line in open('all-projects.txt'):
    lvl, name, path = line.rstrip('\n').split('\t')
    key = name.lower()
    if any(c in key for c in covered): seen.add(name)
    else: remaining.append((lvl, name, path))

print(f"지도에서 명시적으로 다룬 것: {len(seen)}개")
print(f"\n=== 잔여 (직접 분류해보세요) — {len(remaining)}개 ===")
for lvl, name, path in sorted(remaining, key=lambda x: (x[0], x[1]))[:40]:
    print(f"{lvl:12s} {name:28s} {path}")
EOF
```

✅ 잔여 목록의 각 항목에 대해 물어라: **어느 지도의 어느 축에 놓이는가요?** 놓이지 않으면 새 갈래인가, 아니면 내가 그 지도를 잘못 그렸는가. (Sandbox 신생이 대부분일 것 — 지도의 가장자리는 원래 흐릿합니다.)

## Step 3. Graduated 전수 대조 — 심층 트랙의 명단 확정

```bash
grep "^graduated" all-projects.txt | cut -f2 | sort
echo "---"
echo "Part 4의 심층 모듈(11~44) 명단과 대조하고, 누락·추가를 기록하라"
echo "→ 승격된 신규 Graduated가 있으면 45(라운드업)에 편입"
```

## Step 4. 나머지 다섯 갈래 확인

```bash
python3 <<'EOF'
groups = {
 '오토스케일 (층 구분!)': [('KEDA','워크로드 — 이벤트·scale-to-zero'),('Karpenter','노드 — Pending Pod')],
 '서버리스·Wasm':        [('Knative','서빙·이벤트'),('wasmCloud','Wasm 액터'),('SpinKube/WasmEdge','Wasm 워크로드')],
 '비용(FinOps)':         [('OpenCost','네임스페이스·팀별 실비용')],
 '카오스':               [('Chaos Mesh','CRD로 장애 주입'),('LitmusChaos','실험 허브·워크플로')],
 '레지스트리·아티팩트':  [('Harbor','레지스트리+스캔+서명+정책'),('ORAS','OCI 아티팩트 — attestation의 그릇')],
}
for g, items in groups.items():
    print(f"\n[{g}]")
    for n, d in items: print(f"   {n:20s} {d}")
print("\n→ KEDA와 Karpenter는 직렬로 함께 씁니다 (Pod 증가 → Pending → 노드 생성)")
EOF
```

## Step 5. 산출물 — 전수 마감 기록

```markdown
# 지도 전수 마감 (조사일: ____)
- CNCF 프로젝트 총계: ___ (graduated ___ / incubating ___ / sandbox ___)
- 지도 트랙 커버리지: ___ / ___ 
- 잔여 미분류: ___개 — 대부분 (신생 Sandbox / 새 갈래 / 지도 수정 필요) 중 어디?
- Graduated 명단 vs 심층 모듈 명단 diff: ___
- 다음 재집계 예정일: ____ (분기 1회 — theory §3-c)
```

## 정리

landscape.yml과 all-projects.txt는 lab-02(종합 지도)에서 사용. 유지.
