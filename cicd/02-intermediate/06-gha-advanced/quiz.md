# 자가 점검 퀴즈

**Q1.** composite action / reusable workflow / starter workflow를 "무엇을 만드는가"와 "갱신 전파" 기준으로 구분하세요.

**Q2.** composite action에 넣을 수 없는 속성 네 가지와, 그 이유를 한 문장으로.

**Q3.** `secrets: inherit`과 명시적 전달의 차이는? 각각 언제 쓰는가요?

**Q4.** reusable workflow를 SHA로 고정해야 하는 이유가 서드파티 액션보다 더 강한 이유는?

**Q5.** reusable workflow 안에서 `GITHUB_TOKEN`의 권한은 누가 정하는가요? 이 설계의 안전성은?

**Q6.** 동적 매트릭스에서 `fromJSON`이 빈 배열일 때 무슨 일이 일어나며, 두 가지 방어책은?

**Q7.** environment의 보호 규칙 네 가지를 들고, "승인 대기 중 러너를 점유하지 않는다"의 실무적 의미는?

**Q8.** 프로덕션 시크릿을 저장소 시크릿이 아니라 environment 시크릿에 두는 것의 보안 효과는?

---

## 정답

**A1.** composite action = **스텝 묶음**(호출한 잡의 러너에서 실행), 참조 버전으로 자동 전파. reusable workflow = **잡들**(자체 `runs-on`·services·matrix 가능), 자동 전파. starter workflow = **파일 템플릿**(복사됨), 이후 갱신은 **수동**(복사본이므로).

**A2.** `runs-on`, `services`, `strategy: matrix`, `permissions`(그리고 `environment`, `needs`) — 전부 **잡의 속성**이기 때문. composite action은 잡 안의 스텝 묶음이라 잡 자체를 정의하거나 그 속성을 가질 수 없습니다.

**A3.** `inherit`는 호출자의 **모든 시크릿**을 넘깁니다(편의, 큰 폭발 반경). 명시적 전달은 `secrets: NAME: ${{ secrets.NAME }}`로 지정한 것만(최소 권한). 규칙: **같은 저장소 안이면 inherit 허용, 다른 저장소(조직 공용)에는 명시 전달만.** 프로덕션 자격증명은 아예 environment로 격리.

**A4.** 조직 공용 reusable workflow는 **수십~수백 저장소가 동시에** 그것을 실행하고, 시크릿이 그 경로로 흐릅니다 — 태그가 재지정되거나 저장소가 탈취되면 한 번의 커밋으로 전 조직의 시크릿이 유출됩니다. 서드파티 액션보다 신뢰 범위가 넓고 전파가 즉각적이므로 SHA 고정 + 저장소 보호가 더 절실합니다.

**A5.** **호출자의 `permissions:`** 가 상한을 정합니다 — 호출당하는 워크플로가 그보다 넓힐 수 없습니다. 안전한 설계입니다: 공용 워크플로가 몰래 `contents: write`를 얻어 저장소를 조작할 수 없고, 각 저장소가 자기 위험을 스스로 통제합니다.

**A6.** 매트릭스 원소가 0개면 그 잡은 **아예 생성되지 않고**, 그것을 `needs`로 참조하는 후속 잡의 result가 `skipped`가 됩니다 → 수렴 잡이 `success`만 허용하면 게이트가 영원히 실패합니다. 방어: ① 매트릭스 잡에 `if: <count> != '0'` ② 수렴 잡에서 `skipped`도 통과로 허용(`[ "$R" = "success" ] || [ "$R" = "skipped" ]`).

**A7.** required reviewers(승인자), wait timer(대기 시간 — 취소 기회), deployment branches(배포 가능 브랜치 제한), environment secrets/variables. 승인 대기 중 러너 미점유의 의미: **비용 없이 며칠도 대기 가능**하며, 승인이 병목이어도 CI 큐를 막지 않습니다 — 01의 "배포 버튼은 사람이 누른다"를 비용 없이 구현합니다.

**A8.** 저장소 시크릿은 **모든 워크플로의 모든 잡**에서 읽힙니다(PR CI 포함). environment 시크릿은 그 환경을 선언한 잡에서만 읽히고, 그 잡은 승인·브랜치 정책을 통과해야 실행됩니다 → 프로덕션 자격증명의 접근이 "누가, 어느 브랜치에서, 승인 후"라는 **경계 안으로** 들어옵니다. 실수로 추가된 워크플로나 내부 기여자의 브랜치에서도 노출되지 않습니다.
