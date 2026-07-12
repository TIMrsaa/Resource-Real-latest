# 이론 — ConfigMap, Secret, 주입 방식과 보안 계층

> **🌱 17세 눈높이 비유: 게임 본체와 세이브 파일**
> 게임(이미지)은 모두 같은 디스크를 사입니다. 하지만 내 키 설정, 내 진행도(설정값)는 **세이브 파일(ConfigMap)** 로 따로 저장됩니다. 그래서 게임 업데이트(이미지 교체)와 무관하게 설정이 유지되고, PC방 어느 자리(어느 환경)에 앉아도 내 세이브만 끼우면 됩니다.
> **Secret**은 그중 "계정 비밀번호 메모"다 — 그런데 주의: K8s의 기본 메모지는 **연필로 흘려 쓴 것(base64)이지 금고가 아닙니다.** 금고는 따로 마련해야 합니다.

---

## 1. ConfigMap — 평범한 설정 저장소

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: "info"                # key=value 형
  app.properties: |                # 파일 통째 형
    db.host=mydb.example.com
    db.pool=20
```

- 용량 한도 **1MiB** (etcd 항목 제한). 큰 파일/바이너리는 볼륨(모듈 08)이나 외부 저장소로.
- 민감하지 않은 것 전용: 로그 레벨, 기능 플래그, 엔드포인트 URL, 설정 파일.

## 2. 주입 방식 2가지 — 차이가 본질입니다

### 2.1 환경변수로

```yaml
spec:
  containers:
  - name: app
    envFrom:
    - configMapRef: { name: app-config }     # 전부 주입
    env:
    - name: MY_LOG_LEVEL                      # 골라서 + 이름 바꿔 주입
      valueFrom:
        configMapKeyRef: { name: app-config, key: LOG_LEVEL }
```

### 2.2 볼륨(파일)로

```yaml
spec:
  volumes:
  - name: config
    configMap: { name: app-config }
  containers:
  - name: app
    volumeMounts:
    - { name: config, mountPath: /etc/config, readOnly: true }
# → /etc/config/LOG_LEVEL, /etc/config/app.properties 파일이 생깁니다
```

### 결정적 차이: 갱신 전파

| | 환경변수 | 볼륨 마운트 |
|---|---|---|
| ConfigMap 수정 시 | **반영 안 됨** (프로세스 env는 시작 시 고정) | kubelet이 **자동 갱신** (수십 초~분) |
| 반영하려면 | Pod 재시작 (`rollout restart`) | 앱이 파일을 다시 읽으면 끝 (hot reload) |
| 적합 | 시작 시 한 번 읽는 값 | 설정 파일, 자주 바뀌는 값 |

> **💡 함정 예고**: 볼륨이라도 `subPath`로 마운트하면 갱신이 **안 됩니다** (pitfalls 4번). 그리고 갱신은 "즉시"가 아니라 kubelet sync 주기+캐시 (기본 최대 ~1분).

> **💡 갱신의 원리**: 볼륨 마운트는 심볼릭 링크 트릭(`..data` → 타임스탬프 디렉터리)으로 **원자적으로** 교체됩니다. 앱이 파일을 읽는 도중 반쯤 바뀐 내용을 볼 일은 없습니다.

## 3. Secret — 구조는 ConfigMap, 단 보호 "계층"이 다를 뿐

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-cred
type: Opaque                       # 범용. 특수형: kubernetes.io/tls, dockerconfigjson 등
data:
  password: cGFzc3cwcmQ=           # base64("passw0rd") — 암호화 아님!!
stringData:                        # 평문으로 쓰면 K8s가 base64로 변환해줌 (작성 편의)
  username: admin
```

### base64는 보안이 아닙니다

```bash
echo cGFzc3cwcmQ= | base64 -d    # → passw0rd (1초 해독)
```

base64는 "바이너리도 YAML에 넣을 수 있게 하는 표기법"이지 암호화가 아닙니다. 그럼 Secret의 실제 보호는?

### 보안 계층 (안 → 밖)

| 계층 | 내용 | 기본값 |
|------|------|--------|
| ① 노드 메모리 | Secret 볼륨은 디스크가 아닌 **tmpfs(램)** 에 마운트 | ✅ 기본 |
| ② 배포 범위 | Secret은 그것을 쓰는 Pod가 있는 노드에만 전송 | ✅ 기본 |
| ③ RBAC | `get secrets` 권한 통제 — **가장 중요** (모듈 11) | ⚠️ 직접 설계 |
| ④ 저장 시 암호화 | etcd에 암호화 저장 (EKS는 KMS 봉투 암호화 기본 제공) | ✅ EKS 기본 |
| ⑤ 외부 매니저 | AWS Secrets Manager/Vault에 두고 동기화 또는 직접 마운트 | ⚠️ 선택 (운영 권장) |

> **결론**: "Secret을 썼으니 안전"이 아니라 "③ RBAC를 조였고 ⑤ 회전(rotation) 체계가 있어야" 안전입니다. Git에 Secret YAML을 평문 커밋하는 것은 어떤 계층으로도 못 막습니다 — SOPS/SealedSecrets(cicd 파트 22).

### 자주 쓰는 특수 타입

| type | 용도 |
|------|------|
| `kubernetes.io/dockerconfigjson` | 프라이빗 레지스트리 인증 (`imagePullSecrets`) |
| `kubernetes.io/tls` | TLS 인증서+키 (Ingress/Gateway에서 참조) |
| `kubernetes.io/service-account-token` | (레거시) SA 토큰 — 현재는 단기 projected 토큰이 표준 |

## 4. immutable — 성능과 안전을 한 번에

```yaml
immutable: true     # ConfigMap/Secret 공통
```

- 수정 불가(삭제 후 재생성만). 실수 변경 방지 + **kubelet이 watch를 끊어 대규모 클러스터에서 API 부하 급감**.
- 운영 패턴: 이름에 해시를 박아(`app-config-7f3a`) 새 버전은 새 이름으로 → Deployment template이 바뀌니 자동 롤링 업데이트까지 유발 (Helm/Kustomize가 자동화 — 모듈 17, 18).

## 5. 소스코드에서 확인하기

- 볼륨 갱신(심링크 원자 교체): `pkg/volume/util/atomic_writer.go` — `..data` 트릭의 구현
- Secret이 tmpfs로 가는 곳: `pkg/volume/secret/secret.go`

## 요약 카드

| 질문 | 답 |
|------|----|
| ConfigMap 크기 한도? | 1MiB |
| 환경변수 주입의 약점? | 갱신 불가 — 재시작 필요 |
| 볼륨 주입의 강점? | 자동 갱신(원자적), 단 subPath 예외 |
| base64의 정체? | 표기법. 보안 아님 |
| Secret의 진짜 보호? | RBAC + etcd 암호화(KMS) + tmpfs + 외부 매니저 |
| immutable의 효과? | 실수 방지 + kubelet watch 부하 제거 |
