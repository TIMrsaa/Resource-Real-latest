# 흔한 함정 5선

## 1. Secret YAML을 Git에 평문 커밋

base64는 평문입니다. 한 번 푸시된 비밀번호는 히스토리에 영원히 남습니다 — **유출로 간주하고 즉시 회전**해야 합니다. 올바른 길: SOPS/SealedSecrets로 암호화 커밋, 또는 External Secrets Operator로 Git에는 "참조"만 (cicd 파트 22).

## 2. "ConfigMap 바꿨는데 적용이 안 돼요"

3중 함정 체크리스트:
1. **환경변수 주입**이면 → 갱신 불가, `rollout restart` 필요
2. 볼륨인데 **subPath** 마운트면 → 갱신 불가 (아래 4번)
3. 볼륨+일반 마운트면 → 최대 ~1분 대기 (kubelet sync 주기), 그리고 **앱이 파일을 다시 읽는지**는 앱 책임

## 3. 1MiB 한도에 도전하기

ConfigMap에 GeoIP DB, ML 모델, 거대 JSON을 넣으려는 시도. etcd 전체가 느려지는 길입니다. 큰 데이터는 이미지 레이어, 볼륨(모듈 08), S3(initContainer로 다운로드)로.

## 4. subPath 마운트의 이중 함정

```yaml
volumeMounts:
- name: config-vol
  mountPath: /app/config.yaml
  subPath: config.yaml        # 디렉터리를 통째로 덮지 않으려고 흔히 사용
```

편리해 보이지만: ① **자동 갱신이 영원히 안 됩니다** (심링크 트릭이 적용 안 됨) ② 일부 버전에서 Pod 재시작 시 마운트 문제의 단골. 대안: 디렉터리째 마운트하고 앱 설정 경로를 바꾸거나, projected volume 사용.

## 5. 환경변수로 비밀번호 주입 후 방심

env로 넣은 Secret은 ① `kubectl describe pod`에는 안 보여도 ② 앱이 크래시 덤프/에러 페이지에 env를 찍는 순간 노출 ③ `/proc/<pid>/environ`으로 노드에서 열람 가능 ④ 자식 프로세스에 상속. 민감 값은 **파일(tmpfs) 마운트가 한 수 위**고, 최선은 앱이 외부 매니저에서 직접 가져오는 것.

## 실무 사고 사례

> 한 팀이 DB 비밀번호 회전 후 Secret을 갱신했습니다. 볼륨 마운트라 파일은 바뀌었지만 **앱이 시작 시 한 번만 읽는 구조**여서 옛 비밀번호로 재연결 시도 → 새벽에 DB가 로그인 실패 누적으로 계정 잠금 → 전 서비스 장애. 교훈: 갱신 전파는 "파일이 바뀌는 것"까지고, **그걸 다시 읽는 것은 앱의 계약**입니다. 회전 절차에 rollout restart를 명시하세요.
