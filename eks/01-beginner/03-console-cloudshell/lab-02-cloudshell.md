# Lab 02 — CloudShell: 1분 셋업과 비상 시나리오

> 시나리오: 출장지 PC, 내 노트북 없음, 장애 콜 — 브라우저 하나로 클러스터에 도달합니다.

## Step 1. CloudShell 열기

콘솔 우상단의 터미널 아이콘(>_) → 리전이 ap-northeast-2인지 확인(좌상단 리전과 일치).

```bash
# 자격증명이 이미 잡혀 있습니다 — 입력한 적 없는데!
aws sts get-caller-identity
```

✅ 콘솔에 로그인한 IAM이 자동 주입 — CloudShell의 본질이자 한계(그 IAM 권한 그대로).

## Step 2. kubectl 셋업 — 영속 디렉터리에

```bash
mkdir -p ~/bin
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl ~/bin/
export PATH=$HOME/bin:$PATH && echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
kubectl version --client
```

> `~/`는 리전별 1GB 영속 — **다음 세션에도 남습니다.** (시스템 영역 설치는 휘발)

## Step 3. 클러스터 연결 — 단 한 줄

```bash
aws eks update-kubeconfig --name k8s-study --region ap-northeast-2
kubectl get nodes
kubectl auth whoami
```

✅ 모듈 02에서 배운 그대로: kubeconfig엔 비밀이 없으니 **자격증명(자동 주입) + entry(이미 등록된 내 IAM)** 만으로 즉시 연결. "어디서든 1분" — 이게 비상 runbook의 전제입니다.

## Step 4. 미니 비상 훈련 — k8s 38의 루틴을 CloudShell에서

```bash
# 상황 파악 3종 (장애 콜 첫 3분의 명령)
kubectl get nodes                                   # 노드 살았나
kubectl get pods -A | grep -v Running | head        # 죽어가는 것 있나
kubectl get events -A --sort-by=.lastTimestamp | tail -5    # 최근 무슨 일이
```

✅ 도구가 달라져도(노트북→CloudShell) 루틴은 같습니다 — 환경 독립적인 진단 습관의 가치.

## Step 5. eksctl도 (선택)

```bash
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" | tar xz -C ~/bin
eksctl get cluster --region ap-northeast-2
```

## Step 6. 한계 체험과 정리

```markdown
CloudShell이 부적합한 것 (직접 느껴보기):
- [ ] 세션 ~20분 유휴 시 종료 (긴 watch는 끊깁니다)
- [ ] 빌드/대용량 작업 (1GB 홈, 제한된 CPU)
- [ ] 리전 바꾸면 홈도 바뀜 (ap-northeast-2의 ~/bin은 서울 전용)
결론: 비상/일회성의 도구. 일상 운영은 내 환경 + IaC.
```

> 생성 리소스 없음 — cleanup 불필요. (CloudShell 홈의 kubectl은 남겨두면 다음 비상 때 셋업이 30초로 줍니다)
