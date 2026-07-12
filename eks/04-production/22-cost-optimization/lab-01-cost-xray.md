# Lab 01 — 비용 엑스레이: 고아 색출과 requests 갭 측정

절감의 ①단(끄기)과 ②단(다이어트)의 **표적 목록**을 실측으로 만듭니다. 이 랩의 스크립트들은 그대로 cron에 올릴 가치가 있습니다.

```bash
export AWS_REGION=ap-northeast-2
```

## Step 1. 고아 사냥 ① — 미부착 EBS 볼륨

PVC를 지워도 ReclaimPolicy·수동 생성·실패 잔재로 볼륨이 남습니다(08). `available` 상태 = 아무도 안 쓰는데 과금 중:

```bash
aws ec2 describe-volumes --region $AWS_REGION \
  --filters Name=status,Values=available \
  --query 'Volumes[].{id:VolumeId,GiB:Size,created:CreateTime,type:VolumeType}' --output table

# 월 요금 어림: GiB 합계 × gp3 단가(~$0.09/GiB·월 서울 기준 — 요금표 확인)
aws ec2 describe-volumes --region $AWS_REGION --filters Name=status,Values=available \
  --query 'sum(Volumes[].Size)' --output text | awk '{printf "고아 EBS 합계: %d GiB ≈ $%.2f/월\n", $1, $1*0.09}'
```

## Step 2. 고아 사냥 ② — 유령 LB와 늙은 스냅샷

```bash
# 유령 LB 후보: k8s가 만든 이름 패턴인데, 현재 클러스터의 Ingress/Service와 대조
aws elbv2 describe-load-balancers --region $AWS_REGION \
  --query 'LoadBalancers[].{name:LoadBalancerName,created:CreatedTime}' --output table
kubectl get ingress,svc -A | grep -iE "loadbalancer|alb" || echo "(클러스터 쪽 LB 소유자 없음)"
# → AWS엔 있는데 클러스터에 주인이 없으면 유령 (14의 그 유출) — 시간당 과금 중!

# 오래된 스냅샷 (36의 TTL 규율이 없던 시절의 유산)
aws ec2 describe-snapshots --owner-ids self --region $AWS_REGION \
  --query 'Snapshots[?StartTime<=`2026-01-01`].{id:SnapshotId,GiB:VolumeSize,when:StartTime}' --output table
```

## Step 3. 고아 사냥 ③ — 관측의 유령 (12의 복습)

```bash
# retention 없는(무기한) 로그 그룹과 그 크기
aws logs describe-log-groups --region $AWS_REGION \
  --query 'logGroups[?retentionInDays==null].{name:logGroupName,GiB:storedBytes}' --output table
```

## Step 4. requests 갭 — 다이어트 후보 top N

"예약 대비 실사용"을 전 워크로드에 대해 계산합니다 (metrics-server 필요):

```bash
cat > gap-report.sh <<'EOF'
#!/usr/bin/env bash
# requests(mCPU) vs 실사용(mCPU) 갭 — 큰 순서로
set -euo pipefail
join <(kubectl get pods -A -o json | python3 -c "
import json,sys
for p in json.load(sys.stdin)['items']:
    if p['status'].get('phase')!='Running': continue
    req=sum(int(str(c.get('resources',{}).get('requests',{}).get('cpu','0')).rstrip('m') or 0)
            if 'm' in str(c.get('resources',{}).get('requests',{}).get('cpu','0'))
            else int(float(c.get('resources',{}).get('requests',{}).get('cpu','0') or 0)*1000)
            for c in p['spec']['containers'])
    print(p['metadata']['namespace']+'/'+p['metadata']['name'], req)" | sort) \
     <(kubectl top pods -A --no-headers 2>/dev/null | awk '{gsub("m","",$3); print $1"/"$2, $3}' | sort) \
| awk '{gap=$2-$3; if($2>0) printf "%-60s req=%5dm use=%5dm gap=%5dm (%d%%)\n", $1, $2, $3, gap, gap*100/$2}' \
| sort -t= -k4 -rn | head -15
EOF
chmod +x gap-report.sh && ./gap-report.sh
```

읽는 법: gap% 높은 순 = 다이어트 우선순위. 단 **스냅샷 한 장으로 결정하지 말 것** — 피크 시간대 포함 며칠의 p95(Prometheus가 있으면 15의 쿼리로)가 정식 근거입니다.

## Step 5. 정찰 보고서 (산출물)

```markdown
# 비용 정찰 보고서 — YYYY-MM-DD
## ① 즉시 끄기 (리스크 0)
- 고아 EBS: _개, _GiB ≈ $_/월 → 삭제 (스냅샷 후)
- 유령 LB: _개 ≈ $_/월 → 소유자 확인 후 삭제
- 무기한 로그 그룹: _개, _GiB → retention 14d 일괄
## ② 다이어트 후보 (검증 후)
| 워크로드 | requests | p95 실사용 | 제안 | 예상 절감 |
|----------|---------|-----------|------|----------|
| (gap-report top 5) | | | req = p95×1.3 | |
## ③ 이후 단계 메모
- consolidation 상태(17): [ ] / Spot 후보: __ / Graviton 후보(19 측정 필요): __
- 약정 검토는 ②③ 완료 후 — 현재 기준선 추정: __ vCPU
## 다음 정찰: +1개월 (이 스크립트들을 cron으로)
```

## 정리

읽기 전용 + 스크립트 파일. lab-02에서 계량기를 답니다.
