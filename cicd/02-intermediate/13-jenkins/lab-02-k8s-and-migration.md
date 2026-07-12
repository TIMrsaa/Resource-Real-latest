# Lab 02 — Jenkins on K8s와 마이그레이션 판단

Jenkins의 상태성을 K8s가 어디까지 완화하는지 보고, 레거시 Jenkins를 현대 CI로 옮기는 판단·전략을 세웁니다.

## Step 1. Jenkins on K8s — agent를 Pod로 (개념)

```bash
cat <<'EOF'
# Helm으로 Jenkins on EKS
# helm install jenkins jenkins/jenkins \
#   --set controller.installPlugins="{kubernetes,workflow-aggregator,git,configuration-as-code}" \
#   --set persistence.size=20Gi          # ★ controller 상태용 PV (여전히 상태!)

# Jenkinsfile의 K8s agent
agent {
  kubernetes {
    yaml '''
      spec:
        containers:
        - name: build
          image: golang:1.23
          command: [sleep]
          args: [infinity]
    '''
  }
}
# → 잡마다 Pod 생성 (08 ARC, 12 k8s executor와 같은 사상)
EOF
```

## Step 2. K8s가 해결하는 것과 못 하는 것

```markdown
# Jenkins on K8s의 진실
| 문제 | K8s가 해결? |
|------|-----------|
| agent 확장 | ✅ Pod로, Karpenter 확장(eks 17) |
| agent 격리 | ✅ ephemeral Pod(08) |
| agent 상태 오염 | ✅ 잡마다 새 Pod |
| **controller 상태** | ❌ 여전히 PV에 설정·히스토리 |
| **controller SPOF** | ❌ controller Pod가 죽으면 멈춤 |
| **controller 백업** | ❌ PV 백업이 우리 책임(k8s 36의 Velero) |
| **플러그인 업그레이드** | ❌ 여전히 호환성 지옥 |
```

✅ 핵심: **"Jenkins를 K8s에 올렸다"가 상태성을 없애지 않습니다.** agent 문제는 풀리지만 controller는 여전히 상태를 가진 SPOF입니다. JCasC(Configuration as Code)로 controller 설정을 코드화하면 상태성이 **완화**되지만(재구축 가능), 빌드 히스토리·플러그인 상태는 여전히 PV에 삽니다.

## Step 3. controller 백업 — 우리 책임 (k8s 36 회수)

```markdown
# Jenkins controller 백업 전략 (k8s 36의 원리)
- JENKINS_HOME(PV)을 Velero로 백업 (k8s 36)
- 또는 JCasC로 설정 코드화 + 잡을 SCM에(Jenkinsfile) → 상태를 최소화
- 이상적: controller가 "재구축 가능"하도록 (설정=코드, 잡=SCM, 시크릿=외부)
  → 그러면 controller PV 손실 = 히스토리만 잃음(치명적 아님)
- k8s 36의 교훈: "백업이 아니라 복구를 설계" — controller 복구 훈련
```

## Step 4. 마이그레이션 판단 — 옮길 것인가 (산출물)

레거시 Jenkins를 만났습니다. 떠날지 판단합니다:

```markdown
# Jenkins 마이그레이션 판단 워크시트
## 떠나야 하는 신호 (점수)
- [ ] controller 운영에 주당 __시간 이상 소모 (HA·백업·플러그인)
- [ ] 방치된/취약한 플러그인에 의존 (보안 부채 — 21)
- [ ] 잡이 UI에만 있고 코드화 안 됨 (재현·리뷰 불가)
- [ ] 개발자가 Jenkins를 기피 (개발자 경험)
- [ ] SaaS CI로 대체 가능한 표준 워크플로

## 머물러야 하는 신호
- [ ] 플러그인으로만 되는 특수 통합 (레거시 시스템, 특수 HW)
- [ ] 에어갭/규제로 SaaS 불가
- [ ] 40년치 잡의 이식 비용 > 운영 비용
- [ ] 팀의 Jenkins 전문성 (재교육 비용)

## 판단
떠남 신호 > 머묾 신호 → 마이그레이션 계획
그 반대 → JCasC·K8s agent로 현대화하며 유지
```

## Step 5. 마이그레이션 전략 — 점진(strangler fig)

빅뱅은 실패합니다(eks 23 kubefed의 교훈). 점진 전략:

```markdown
# Jenkins → 현대 CI 마이그레이션 (strangler fig)
1. 문서화 먼저: 각 Jenkins 잡이 "무엇을 하는지" 파악
   → UI 잡은 대개 문서가 없습니다. 이게 마이그레이션의 진짜 비용
2. 새 것은 새 도구로: 신규 서비스의 CI는 GitHub Actions/GitLab
   → Jenkins는 더 커지지 않습니다
3. 잡을 하나씩 이전 (02의 브랜치 바이 앱스트랙션):
   - 우선순위: 자주 바뀌는 잡, 표준적인 잡부터
   - 각 이전이 독립적으로 완료 (한 잡 옮겨도 나머지 동작)
   - 병행 운영: 이전 중엔 양쪽에서 (검증)
4. 특수 잡은 마지막 (또는 남김): 플러그인 의존 잡은 이전이 어렵거나 불가
5. Jenkins 축소 → 필요시 유지, 아니면 제거

# 안티패턴 (하지 말 것)
- ❌ "6개월 안에 전부 이전" 빅뱅 → 40년치를 한 번에 = 실패
- ❌ 문서화 없이 이전 → "이 잡이 뭐 하는지 모르는데 옮김" = 장애
- ❌ 병행 없이 전환 → 롤백 불가
```

✅ eks 23의 fleet 마이그레이션, 02의 브랜치 바이 앱스트랙션, 11의 expand-contract — 모두 같은 사상이 마이그레이션에 적용됩니다: **큰 변화를 독립적으로 완료 가능한 작은 단계로.**

## Step 6. 중급 트랙 졸업 점검

```markdown
06 → Actions 재사용·배포통제                    [ ]
07 → OIDC (04의 장기 키 부채 상환)              [ ]
08 → self-hosted 러너 (ARC on EKS)             [ ]
09~11 → AWS Code 시리즈 (오케스트레이션·빌드·배포) [ ]
12 → GitLab CI (이식성·통합 철학)              [ ]
13 → Jenkins (상태성·플러그인·마이그레이션)     [ ]
→ 고급(14~20): GitOps가 배포 패러다임을 바꿉니다 — push에서 pull로
```

## 정리

```bash
bash cleanup.sh
```
