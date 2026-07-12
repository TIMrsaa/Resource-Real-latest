# 이론 — Volume, PV/PVC, StorageClass, CSI

> **🌱 17세 눈높이 비유: 학교 사물함 시스템**
> - **emptyDir** = 책상 서랍. 자리(Pod)를 옮기면 비워집니다.
> - **hostPath** = 교실 뒤 캐비닛. 그 교실(노드)에 있을 때만 쓸 수 있고, 다른 교실로 가면 끝.
> - **PVC** = "사물함 신청서". 크기와 등급만 적어 냅니다.
> - **StorageClass** = 사물함 **종류 메뉴판** (일반/대형/냉장). 메뉴판에는 "신청 들어오면 어느 업체(EBS)에 주문하는지"도 적혀 있습니다.
> - **PV** = 실제 배정된 사물함. 졸업(Pod 삭제)해도 신청을 유지하면 내 물건은 그대로입니다.

---

## 1. 임시 볼륨 — Pod와 운명을 같이

### emptyDir
- Pod 생성 시 빈 디렉터리, **Pod 삭제 시 소멸**. 컨테이너 재시작에는 살아남습니다(Pod는 그대로니까).
- `emptyDir: {medium: Memory}` 로 tmpfs(램) 가능 — 빠르지만 메모리 limit에 포함됨.

### hostPath — 위험물 취급
- **노드의 디렉터리**를 그대로 마운트. Pod가 다른 노드로 가면 다른 내용(또는 없음).
- 노드 파일시스템 접근 = 보안 구멍 (kubelet 인증서, 도커 소켓...). **일반 앱에서 금지**, 노드 에이전트(DaemonSet)/CSI 드라이버 전용. Pod Security Admission이 기본 차단합니다(모듈 32).

## 2. PV / PVC — 신청과 실물의 분리

```yaml
# 개발자가 쓰는 것: 신청서
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3
  resources:
    requests:
      storage: 1Gi
```

- **PVC**: "이만한 저장소 주세요" (네임스페이스 소속, 개발자 영역)
- **PV**: 실제 저장소를 나타내는 클러스터 리소스 (네임스페이스 없음, 인프라 영역)
- **바인딩**: PVC ↔ PV 1:1 연결. 한 번 묶이면 배타적.

### accessModes — 자주 틀리는 부분

| 모드 | 의미 | 주의 |
|------|------|------|
| ReadWriteOnce (RWO) | **한 노드**에서 읽기/쓰기 | Pod가 아니라 **노드** 단위! 같은 노드면 여러 Pod 가능. EBS가 이것 |
| ReadOnlyMany (ROX) | 여러 노드 읽기 전용 | |
| ReadWriteMany (RWX) | 여러 노드 읽기/쓰기 | EBS 불가! NFS/EFS 필요 |
| ReadWriteOncePod (RWOP) | 정확히 **한 Pod** | 더 엄격한 보장 (GA) |

> "replicas: 3인 Deployment에 EBS PVC 하나를 물렸더니 Pod 1개만 뜨고 2개는 Pending" — RWO의 의미를 모르면 영원히 미스터리인 단골 사고.

## 3. StorageClass — 동적 프로비저닝의 자판기

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com          # 누가 만드나: EBS CSI 드라이버
parameters:
  type: gp3                            # EBS 타입
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer  # ★ 중요 (아래)
allowVolumeExpansion: true               # 온라인 확장 허용
reclaimPolicy: Delete                    # PVC 삭제 시 실물도 삭제
```

흐름: PVC 생성 → StorageClass의 provisioner가 **실제 EBS 볼륨을 만들어** PV로 등록 → 바인딩. 관리자가 PV를 미리 만들어두는 정적 방식은 특수한 경우(기존 디스크 연결)에만 씁니다.

### WaitForFirstConsumer — AZ 문제의 해법

EBS는 AZ 종속입니다. `Immediate` 모드라면: PVC 생성 즉시 아무 AZ(예: 2a)에 볼륨 생성 → 그런데 스케줄러가 Pod를 2c 노드에 배정하면? → **영원히 못 붙습니다.**

`WaitForFirstConsumer`: 볼륨 생성을 **Pod가 스케줄링될 때까지 미루고**, Pod가 간 노드의 AZ에 만듭니다. 클라우드에서는 사실상 필수 설정.

### reclaimPolicy — 데이터의 마지막 운명

| 정책 | PVC 삭제 시 |
|------|------------|
| Delete | PV + **실제 EBS도 삭제** (학습/임시에 적합) |
| Retain | PV는 Released로 남고 EBS 보존 — 수동 정리 필요 (운영 DB에 적합) |

## 4. CSI — 스토리지의 OCI

옛날에는 EBS/GCE/Azure 코드가 K8s 본체에 내장(in-tree)되어 있었습니다 — 벤더 추가마다 K8s 릴리스가 필요한 구조. **CSI(Container Storage Interface)** 표준으로 전부 외부 드라이버로 분리됐고, in-tree 코드는 제거 완료. 

```
kubelet ── CSI gRPC ──▶ ebs.csi.aws.com 드라이버 Pod들
                          ├─ controller (EBS 생성/삭제/연결 — AWS API 호출)
                          └─ node DaemonSet (노드에서 mount/format)
```

EKS에서는 **관리형 애드온**으로 설치하며, EBS API를 부를 IAM 권한이 필요합니다 (lab-02에서 Pod Identity로 부여 — eks 파트 09의 예고편).

## 5. 마운트까지의 전체 체인

```
PVC 생성 → CSI controller가 EBS 생성 (AZ는 Pod 스케줄 후) → PV 바인딩
→ AttachVolume (EBS를 EC2에 연결) → kubelet: format(최초 1회) + mount
→ 컨테이너의 mountPath에 등장
```

Pending에서 멈췄다면 이 체인 어디서 끊겼는지 `kubectl describe pvc/pod` 이벤트로 추적합니다 — 모듈 02에서 배운 그 기술.

## 6. 소스코드에서 확인하기

- CSI 스펙: https://github.com/container-storage-interface/spec — gRPC 서비스 3개(Identity/Controller/Node)가 전부입니다
- EBS CSI 드라이버: https://github.com/kubernetes-sigs/aws-ebs-csi-driver — `pkg/driver/controller.go`의 `CreateVolume`이 "PVC → EBS API 호출"의 그곳

## 요약 카드

| 질문 | 답 |
|------|----|
| emptyDir의 수명? | Pod와 동일 (컨테이너 재시작에는 생존) |
| PVC와 PV의 관계? | 신청서와 실물, 1:1 바인딩 |
| RWO의 단위? | **노드** (Pod 아님) |
| EBS로 RWX? | 불가 — EFS/NFS 필요 |
| WaitForFirstConsumer 이유? | Pod의 AZ가 정해진 뒤 그 AZ에 볼륨 생성 |
| PVC 지우면 데이터는? | reclaimPolicy에 따라 (Delete=같이 삭제 / Retain=보존) |
