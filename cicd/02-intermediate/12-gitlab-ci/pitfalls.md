# 흔한 함정 5선

## 1. stage와 needs를 혼동해 파이프라인이 느려짐

GitLab 초심자는 stage만 씁니다 — 그러면 각 stage가 이전 stage **전체**의 완료를 기다립니다(build stage의 모든 잡이 끝나야 test stage 시작). 실제로는 `test-x`가 `build-x`만 필요한데 `build-y`까지 기다리는 낭비입니다. `needs:`로 DAG를 만들면 최단 경로로 병렬화됩니다(lab-02 Step 5). Actions에서 온 사람은 오히려 이걸 잘하는데, GitLab만 배운 사람이 stage에 갇히기 쉽습니다.

## 2. protected variable을 안 쓰고 시크릿 노출

GitLab CI/CD variable을 그냥 만들면 **모든 브랜치의 파이프라인**에서 읽힙니다 — 포크 MR이나 아무 브랜치의 파이프라인에서도(03의 포크 PR 위험과 같은 구조). 프로덕션 시크릿은 **protected variable**(protected 브랜치/태그에서만)로, 그리고 masked도 함께(로그 마스킹). 06의 environment secret이 GitLab에서는 protected variable + environment scope의 조합입니다.

## 3. self-managed 러너를 퍼블릭 프로젝트에

08의 절대 금지가 GitLab에도 그대로 이식됩니다 — 퍼블릭 프로젝트(또는 포크 MR)의 파이프라인이 우리 self-managed 러너(VPC 안)에서 실행되면, 누구나 MR을 열어 내부 스캔·시크릿 탈취를 시도할 수 있습니다. GitLab의 "포크 파이프라인" 설정으로 승인을 요구하고, Kubernetes executor 러너에 08의 방어(NetworkPolicy, IMDS 차단)를 그대로 적용하세요. 도구가 달라도 위험은 이식됩니다.

## 4. 통합을 이유로 도구를 이념적으로 고르기

"GitLab이 다 해주니까 무조건 GitLab" 또는 "요즘은 GitHub이니까 무조건 Actions" — 09의 함정이 반복됩니다. GitLab의 통합(내장 레지스트리·리뷰앱·스캔)은 매끄럽지만 벤더 종속과 기능 깊이의 대가가 있고, GitHub의 조합은 유연하지만 조립 부담이 있습니다. 기준은 이념이 아니라 맥락: 이미 어디로 소스를 관리하나, 온프레/에어갭인가, 통합을 원하나 best-of-breed를 원하나.

## 5. dind에 캐시가 안 먹는다고 포기

GitLab CI에서 `docker:dind` 서비스로 이미지를 빌드하면, dind 컨테이너가 잡마다 새로 떠서 레이어 캐시가 안 남습니다(04·10의 "호스트 재사용" 문제). 여기서 "GitLab은 캐시가 안 된다"고 결론짓는 것은 틀렸습니다 — 답은 04와 같습니다: BuildKit + 레지스트리 캐시(`--cache-from`/`--cache-to`), 또는 GitLab 캐시로 BuildKit 캐시 디렉터리를 보존. 도구가 아니라 캐시 원리(04)를 적용하는 문제입니다.

## 실무 사고 사례

> GitHub Actions에 익숙한 팀이 회사 인수로 GitLab로 이전했습니다. 첫 파이프라인은 stage만으로 짰습니다 — build stage에 8개 잡, test stage에 12개 잡. 각 stage가 이전 전체를 기다려서 파이프라인이 40분이 걸렸습니다(Actions에서는 needs DAG로 15분이던 것이). 팀은 "GitLab이 Actions보다 느리다"고 결론짓고 불만을 쌓았습니다. 3개월 뒤 GitLab에 익숙한 엔지니어가 합류해 `needs:`로 DAG를 만들자 18분이 됐습니다 — 도구의 문제가 아니라 stage 모델을 needs로 최적화하지 않은 것이었습니다. 더 흥미로운 뒷이야기: 그 과정에서 팀은 "우리가 Actions에서 당연하게 쓰던 needs를 GitLab에서는 stage에 갇혀 잊었다"는 것을 깨달았습니다 — 개념(DAG 병렬)은 이식되는데 그것을 표현하는 어휘가 달라 놓친 것입니다. 교훈: **도구를 바꿀 때 진짜 위험은 문법을 못 외우는 게 아니라, 이미 아는 개념을 새 어휘로 표현하는 법을 놓치는 것입니다** — 그래서 개념 매핑표(theory §1)가 문법 암기보다 중요합니다.
