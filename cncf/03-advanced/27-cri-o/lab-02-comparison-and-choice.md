# Lab 02 — containerd와 직접 대비, 그리고 선택 기준

26과 27을 나란히 놓아 두 철학을 정리하고, "우리 플랫폼의 런타임을 안다"는 실무 감각을 만듭니다.

전제: lab-01의 개념 이해.

## Step 1. 공통점 확인 — 둘 다 CRI 명세를 구현

```bash
cat <<'EOF'
=== containerd(26)와 CRI-O(27)의 공통점 ===
① 둘 다 CRI 명세 구현 → kubelet은 어느 쪽이든 같은 방식으로 대화
② 둘 다 OCI 런타임(runc/crun/kata/runsc)을 호출 → 03의 격리 스펙트럼 동일
③ 둘 다 OCI 이미지(image-spec)를 사용 → 빌드 도구와 무관(cicd 19)
④ 둘 다 crictl로 CRI 레벨 디버깅 가능
⑤ 둘 다 CNCF Graduated

★ 즉 "무엇을 하느냐"는 같습니다 (CRI 런타임) — "어떻게, 얼마나"가 다릅니다
EOF
```

## Step 2. 차이 정리 — 두 철학

```bash
cat <<'EOF'
| 축 | containerd (26) | CRI-O (27) |
|----|-----------------|------------|
| 범위 | 범용 (K8s·Docker·nerdctl·확장) | K8s 전용 (CRI만) |
| 철학 | "무엇이든 컨테이너를" | "K8s가 필요한 것만" |
| 버저닝 | 독립 (호환성 매트릭스) | K8s 정렬 (1.30↔1.30) |
| 구조 | 자체 구현(콘텐츠·스냅샷·shim v2) | containers/ 조립 + conmon |
| 저장 | 자체 콘텐츠 저장소·스냅샷터 | containers/storage(공유) |
| 기본 런타임 | runc | crun(경량) |
| 생태계 | CNCF·Docker 계보, nerdctl | Red Hat containers/, Podman 형제 |
| 확장 | runwasi·stargz·nerdctl·BuildKit | (K8s 전용이라 확장 표면 좁음) |
| 대표 채택 | EKS·GKE·AKS·kind | OpenShift |

★ 25(Linkerd)의 반복: 범위를 좁히는 것도 설계
  containerd = 스위스 army knife (범용, 확장)
  CRI-O = 전문점 (K8s만, 정렬, 조립)
EOF
```

## Step 3. 선택 결정 트리

```bash
cat <<'EOF'
=== 런타임 선택 (현실) ===

Q1. 관리형 K8s를 쓰나요?
  EKS/GKE/AKS → containerd (선택의 여지 없음)
  OpenShift   → CRI-O (선택의 여지 없음)
  → 대부분 여기서 끝납니다 (플랫폼이 정함)

Q2. 자체 구축(kubeadm 등)이라 직접 고른다면?
  범용성 필요? (노드에서 Docker 호환 도구, 다양한 워크로드, 넓은 생태계)
    Yes → containerd
  K8s 전용 + 표면적 최소 + Red Hat 생태계 + K8s 정렬 버저닝?
    Yes → CRI-O
  성능? 둘 다 우수 — 특정 워크로드에서 실측 (막연한 "더 빠름"은 근거 없음)

★ 실무 가치: "어느 게 낫나"가 아니라
  "우리 플랫폼의 런타임이 무엇이고, 그 특성(버저닝·저장·도구)이 무엇인가"
EOF
```

## Step 4. 우리 플랫폼의 런타임 알기 — 실무 체크

```bash
# 어느 클러스터든 런타임 확인
kubectl get nodes -o wide 2>/dev/null | awk '{print $1, $NF}' | head -5 || \
  kubectl get node -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' 2>/dev/null

echo ""
echo "=== 노드의 CONTAINER-RUNTIME 컬럼 ==="
kubectl get nodes -o custom-columns=NAME:.metadata.name,RUNTIME:.status.nodeInfo.containerRuntimeVersion 2>/dev/null

cat <<'EOF'
→ containerd://1.7.x 또는 cri-o://1.30.x
  이것이 우리가 알아야 할 런타임과 그 버전

플랫폼별 진단 도구 차이:
  containerd: crictl(CRI) + ctr -n k8s.io(네이티브)
  CRI-O:      crictl(CRI) + crio-status + containers/ 도구
  → crictl은 공통, 그 아래가 다릅니다
EOF
```

## Step 5. OpenShift 관점 — CRI-O를 쓴다면

```bash
cat <<'EOF'
=== CRI-O(OpenShift) 운영에서 알아야 할 것 ===
① 버저닝: 클러스터 업그레이드 시 CRI-O도 함께 (별도 관리 불필요)
② 이미지 정책: policy.json 서명 검증이 클러스터 이미지 정책으로 통합 (21)
③ 저장: /var/lib/containers/storage (containerd의 /var/lib/containerd와 다른 위치)
   → 디스크 진단(26의 방법)이 이 경로로
④ conmon: 컨테이너 모니터 (shim 대응) — CRI-O 재시작에도 컨테이너 생존
⑤ 형제 도구: 노드에서 crictl 외에 crio, Podman 계열 사용 가능

★ 26의 containerd 지식이 대부분 전이됩니다 (CRI 명세가 같으므로)
  다른 것은 저장 경로·네이티브 도구·버저닝 정책
EOF
```

## Step 6. 두 모듈의 종합 — 런타임 층 완성

```bash
cat <<'EOF'
=== 03의 런타임 지도 → 26·27로 완성 ===

03(지도): CRI 레벨(containerd/CRI-O) vs OCI 레벨(runc/crun/gVisor/kata)
  ↓ 심층
26(containerd): 범용 CRI 런타임의 내부 (플러그인·shim·확장)
27(CRI-O):      K8s 전용 CRI 런타임의 철학 (조립·정렬·미니멀)

배운 것:
  ① CRI 레벨은 kubelet과 대화, OCI 레벨은 실제 프로세스 생성
  ② containerd·CRI-O는 같은 일(CRI)을 다른 철학으로
  ③ "범위를 좁히는 것도 설계" (25의 메시, 27의 런타임에서 반복)
  ④ 진단은 층으로 (kubectl → crictl → 네이티브 → 커널)
  ⑤ 대부분 플랫폼이 정하니 "우리 것을 알라"
EOF
```

## Step 7. 산출물

```markdown
# 런타임 선택·운영 카드 (26+27 종합)
- 공통: 둘 다 CRI 구현, OCI 런타임 호출, crictl 디버깅, Graduated
- 차이: 범용(containerd) vs K8s전용(CRI-O), 독립 vs K8s정렬 버저닝
- 선택: 대개 플랫폼이 정함 (EKS=containerd, OpenShift=CRI-O)
- 실무: "우리 런타임이 무엇이고 그 특성(저장경로·도구·버저닝)이 무엇인가"
- 진단: crictl 공통 / containerd는 ctr -n k8s.io / CRI-O는 crio-status·containers/
- 교훈: 범위를 좁히는 것도 설계 (25의 반복)
```

## 정리

```bash
bash cleanup.sh
```
