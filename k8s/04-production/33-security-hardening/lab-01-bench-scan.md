# Lab 01 — kube-bench와 trivy 실전

## Step 1. kube-bench를 Job으로 실행 (EKS 프로파일)

```bash
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-eks.yaml
kubectl wait --for=condition=complete job/kube-bench --timeout=120s
kubectl logs job/kube-bench | head -40
```

예상 출력 (발췌):
```
[INFO] 3 Worker Node Security Configuration
[PASS] 3.1.1 Ensure that the kubeconfig file permissions are set to 644 or more restrictive
[FAIL] 3.2.x ...
== Summary total ==
xx checks PASS / x checks FAIL / xx checks WARN
```

✅ EKS 프로파일이라 control plane 항목은 없고 **노드/정책 항목**만 — 책임 분계의 실물.

## Step 2. FAIL 항목 해석 훈련

```bash
kubectl logs job/kube-bench | grep -B1 -A3 "FAIL" | head -30
```

각 FAIL에 대해 3택 결정을 적어보세요 (산출물):

| 항목 | 결정 | 근거 |
|------|------|------|
| (예) 3.2.1 anonymous-auth | 수정 | kubelet 설정 — 노드그룹 launch template로 |
| (예) 5.1.1 cluster-admin 사용 | 수용+문서화 | 클러스터 생성자 1명뿐, access entries로 통제 중 |

> kube-bench의 각 항목에는 Remediation(수정 방법)이 함께 출력됩니다 — 보고서가 곧 작업 지시서입니다.

## Step 3. trivy로 이미지 스캔

```bash
# 로컬(WSL2)에 trivy 설치 후
trivy image --severity CRITICAL,HIGH --ignore-unfixed public.ecr.aws/nginx/nginx:1.27 | head -30
```

예상: CVE 표 (라이브러리/심각도/현재·수정 버전). `--ignore-unfixed`로 "고칠 방법도 없는" 노이즈 제거 — 우선순위 규칙의 적용.

```bash
# 오래된 이미지와 비교 — 방치의 비용을 숫자로
trivy image --severity CRITICAL --quiet public.ecr.aws/docker/library/nginx:1.20 2>/dev/null | tail -3
```

✅ 한두 해 묵은 이미지의 CRITICAL 개수를 보라 — "업데이트는 기능이 아니라 보안 작업"임을 체감.

## Step 4. 클러스터 안 리소스 설정 스캔 (trivy의 또 다른 모드)

```bash
trivy k8s --report summary cluster 2>/dev/null | head -25 || \
  echo "k8s 스캔은 시간이 걸립니다 — --include-namespaces default 로 좁혀 재시도"
```

예상: 워크로드별 취약점 + **설정 감사**(모듈 32의 securityContext 누락 등이 잡힙니다!) 요약. kube-bench(클러스터 설정)와 trivy(이미지+워크로드 설정)가 상호 보완하는 구도.

## Step 5. ECR 자동 스캔 연결 (AWS 쪽 한 줄)

```bash
aws ecr put-registry-scanning-configuration --region ap-northeast-2 \
  --scan-type BASIC \
  --rules '[{"scanFrequency":"SCAN_ON_PUSH","repositoryFilters":[{"filter":"*","filterType":"WILDCARD"}]}]'
```

push 시 자동 스캔 — 결과는 콘솔/`aws ecr describe-image-scan-findings`. CI 게이트로 쓰는 법은 cicd 파트 21에서.

## 정리

```bash
kubectl delete job kube-bench --ignore-not-found
```
