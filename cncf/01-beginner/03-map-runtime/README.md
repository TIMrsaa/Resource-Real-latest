# 03 — 지도: 컨테이너 런타임 — kubelet 아래의 세계

> `kubectl run` 뒤에서 실제로 프로세스를 만드는 것은 누구인가요? 답은 한 층이 아니라 **체인**입니다: kubelet → CRI 런타임(containerd/CRI-O) → shim → OCI 런타임(runc/crun) → 리눅스 커널. 이 지도는 그 체인의 전 구성원과, 격리 스펙트럼의 변주들(gVisor의 유저스페이스 커널, Kata의 마이크로VM, Firecracker), 그리고 다음 세대 후보(Wasm 런타임)까지 훑습니다 — k8s 파트에서 "컨테이너는 커널 기능(namespace·cgroup)"임을 배웠다면, 이 모듈은 그 지식 위에 생태계 지도를 얹습니다.

## 학습 목표

1. 런타임 2층 구조(CRI 레벨 vs OCI 레벨)와 OCI 3대 명세(runtime/image/distribution)를 그립니다
2. containerd와 CRI-O의 자리(범용 vs K8s 전용)와 Docker·dockershim의 역사를 정리합니다
3. 격리 스펙트럼 — 공유 커널(runc) → 유저스페이스 커널(gVisor) → 마이크로VM(Kata/Firecracker) — 의 트레이드오프를 압니다
4. kind 노드에서 kubelet→containerd→shim→runc 체인을 프로세스 트리로 직접 관찰합니다
5. Wasm 런타임(WasmEdge 등)이 컨테이너의 어떤 한계를 겨냥하는지 압니다

## 선행: 01(범례), k8s 초급(컨테이너 원리·CRI), eks 19(런타임과 아치) · 도구: kind, kubectl, docker
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 목록·성숙도 집계
3. [lab-02-runtime-chain.md](./lab-02-runtime-chain.md) — 체인 해부: 프로세스 트리·OCI 번들 실물
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
