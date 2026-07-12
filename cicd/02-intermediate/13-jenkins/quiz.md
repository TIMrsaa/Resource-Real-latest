# 자가 점검 퀴즈

**Q1.** Jenkins가 오래 살아남은 세 가지 이유는? 각각의 대가는?

**Q2.** Jenkins의 아키텍처가 GitHub Actions와 근본적으로 다른 점은? 그것이 만드는 우리의 책임은?

**Q3.** Jenkinsfile의 stage/steps/when/post를 다른 도구의 무엇에 매핑하는가요?

**Q4.** Jenkins를 K8s에 올리면 해결되는 것과 여전히 남는 것을 구분하세요.

**Q5.** JCasC(Configuration as Code)가 controller의 상태성을 어떻게 완화하는가요?

**Q6.** 플러그인 생태계의 힘과 세 가지 대가는?

**Q7.** Declarative와 Scripted Pipeline의 차이와, 팀에 Declarative를 권하는 이유는?

**Q8.** 레거시 Jenkins 마이그레이션에서 "문서화가 먼저"인 이유와, 빅뱅이 실패하는 이유는?

---

## 정답

**A1.** ① 플러그인 생태계(1,800+ — 무엇이든 연결) → 대가: 공급망 위험·유지보수 부채. ② 온프레 완전 통제(에어갭·규제 대응) → 대가: 운영 부담(HA·백업·업그레이드 우리 책임). ③ 벤더 독립 → 대가: SaaS의 편의(자동 관리)를 못 누림.

**A2.** Jenkins는 **controller가 상태를 갖습니다**(잡 정의·히스토리·설정·플러그인) — SPOF이며 백업·HA·업그레이드가 우리 책임. GitHub Actions는 무상태(GitHub이 상태 관리, SPOF 없음, 자동 업그레이드). 이 상태성이 Jenkins의 완전한 통제(힘)이자 운영 부담(부채)입니다.

**A3.** stage = job(Actions)/stage(GitLab). steps = steps/script. when = if:/rules:. post{always} = if:always()/after_script. environment = env/variables. 12의 매핑표 그대로 — 어휘만 Groovy입니다.

**A4.** 해결: agent의 확장(Pod+Karpenter), 격리(ephemeral Pod), 상태 오염(잡마다 새 Pod). 남음: **controller의 상태성**(PV에 설정·히스토리), controller SPOF, 백업·플러그인 업그레이드 책임. "K8s에 올렸다"가 controller 문제를 풀지 않습니다.

**A5.** JCasC는 controller 설정(플러그인·보안·잡 등)을 YAML 코드로 정의합니다 — controller PV를 잃어도 그 코드에서 **재구축 가능**하게 만듭니다. 잡을 SCM(Jenkinsfile)에, 시크릿을 외부에 두면 controller 상태가 최소화되어, PV 손실이 "히스토리만 잃음"으로 완화됩니다(치명적 아님).

**A6.** 힘: 어떤 도구·클라우드·프로토콜·레거시 시스템과도 연결(무엇이든 됩니다). 대가: ① 공급망 위험(플러그인은 controller에서 실행되는 서드파티 코드 — 취약점이 시크릿 장악) ② 유지보수 부채(플러그인 간 버전 충돌, 업그레이드 지옥) ③ 방치된 플러그인(유지보수 중단 → 보안 패치 없음).

**A7.** Declarative는 구조가 강제되어 읽기 쉽고 검증·UI 도구가 잘 동작. Scripted는 순수 Groovy로 무제한 유연하나 복잡·유지보수 어려움(아무도 못 읽는 파이프라인이 되기 쉽습니다). 팀에 Declarative를 권하는 이유: 파이프라인은 선언이어야 하고, 복잡 로직이 필요하면 Shared Library로 격리(테스트 가능하게)하는 것이 낫습니다.

**A8.** 문서화가 먼저인 이유: UI로 만들어진 레거시 잡은 대개 Jenkinsfile도 문서도 없고, 무엇을·왜 하는지 아는 사람이 퇴사했을 수 있습니다 — "옛 도구가 조용히 하던 일"을 모르면 이전할 수 없습니다. 빅뱅이 실패하는 이유: 40년치(혹은 몇 년치) 잡을 한 번에 옮기면 숨은 의존성이 터지고 롤백이 불가능합니다(eks 23 kubefed의 교훈). 점진(strangler fig)으로 각 이전을 독립 완료 가능하게, 병행 검증하며 옮겨야 합니다.
