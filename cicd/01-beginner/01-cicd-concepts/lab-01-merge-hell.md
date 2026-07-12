# Lab 01 — merge hell을 실측합니다: 통합 주기의 비용

"자주 합쳐라"는 조언은 흔합니다. 이 랩은 그것을 **숫자로** 만듭니다 — 같은 변경을 두 가지 통합 주기로 진행해 충돌의 크기를 비교합니다.

## Step 1. 실험장 만들기

```bash
mkdir -p ~/ci-lab/merge-demo && cd ~/ci-lab/merge-demo
git init -q && git config user.email "lab@example.com" && git config user.name "Lab"

# 공유 파일 — 여러 사람이 건드리는 전형적 모듈
cat > app.py <<'EOF'
def greet(name):
    return f"Hello, {name}"

def farewell(name):
    return f"Bye, {name}"

def main():
    print(greet("world"))
    print(farewell("world"))

if __name__ == "__main__":
    main()
EOF
git add -A && git commit -q -m "init" && git branch -M main
git tag baseline
```

## Step 2. 시나리오 A — "매일 합치는 팀" (CI)

앨리스와 밥이 **작은 변경마다** main에 합칩니다:

```bash
# 앨리스: greet 개선 → 즉시 병합
git checkout -q -b alice-1 main
sed -i 's/return f"Hello, {name}"/return f"Hello, {name}!"/' app.py
git commit -qam "alice: add exclamation"
git checkout -q main && git merge -q alice-1 && echo "A1 merged"

# 밥: 밥은 방금 앨리스 것을 당겨받고 시작합니다 (핵심!)
git checkout -q -b bob-1 main
sed -i 's/return f"Bye, {name}"/return f"Goodbye, {name}"/' app.py
git commit -qam "bob: formal farewell"
git checkout -q main && git merge -q bob-1 && echo "B1 merged"

# 앨리스: 다시 main에서 시작
git checkout -q -b alice-2 main
sed -i 's/print(greet("world"))/print(greet("Alice"))/' app.py
git commit -qam "alice: personalize"
git checkout -q main && git merge -q alice-2 && echo "A2 merged"

echo "=== 시나리오 A 결과: 충돌 0회 ==="
git log --oneline | head -4
```

각 병합에서 **바뀐 것은 남이 이미 반영한 코드 위의 작은 델타**뿐이라 git이 자동으로 처리했습니다.

## Step 3. 시나리오 B — "2주 브랜치 팀" (merge hell)

같은 변경을 **각자 오래 들고 있다가** 마지막에 합칩니다:

```bash
git checkout -q -b longlived main
git reset -q --hard baseline    # 실험 격리: 처음 상태로

# 앨리스가 자기 브랜치에서 세 가지를 다 합니다 (2주치)
git checkout -q -b alice-long baseline
sed -i 's/return f"Hello, {name}"/return f"Hello there, {name}!!"/' app.py
sed -i 's/print(greet("world"))/print(greet("Alice"))/' app.py
sed -i 's/    print(farewell("world"))/    print(farewell("Alice"))\n    print("---")/' app.py
git commit -qam "alice: two weeks of work"

# 밥도 같은 기간 자기 브랜치에서 (main을 한 번도 안 당겨받음)
git checkout -q -b bob-long baseline
sed -i 's/return f"Bye, {name}"/return f"Goodbye and farewell, {name}"/' app.py
sed -i 's/print(greet("world"))/print(greet("Bob"))/' app.py
sed -i 's/    print(farewell("world"))/    print(farewell("Bob"))\n    print("===")/' app.py
git commit -qam "bob: two weeks of work"

# 이제 합칩니다
git checkout -q -b integrate alice-long
git merge bob-long
```

예상 출력:

```
Auto-merging app.py
CONFLICT (content): Merge conflict in app.py
Automatic merge failed; fix conflicts and then commit the result.
```

충돌의 **크기**를 재봅시다:

```bash
git diff --name-only --diff-filter=U           # 충돌 파일
grep -c "^<<<<<<<\|^=======\|^>>>>>>>" app.py  # 충돌 마커 개수
sed -n '/^<<<<<<</,/^>>>>>>>/p' app.py | head -20
```

✅ **같은 총 변경량인데 결과가 다릅니다.** A는 충돌 0, B는 여러 헝크가 얽혀 있고 — 더 중요한 건, 이제 누군가 **두 사람의 의도를 동시에 복원**해야 한다는 점입니다. 2주 전 앨리스가 왜 `!!`를 붙였는지 아무도 모릅니다.

## Step 4. 비용을 숫자로

```bash
# 충돌 해결에 필요한 "결정"의 수 = 충돌 헝크 수
HUNKS=$(grep -c "^<<<<<<<" app.py)
echo "시나리오 B의 수동 결정 횟수: $HUNKS"
echo "시나리오 A의 수동 결정 횟수: 0"
```

```markdown
# 실측 기록
| | 시나리오 A (매일 병합) | 시나리오 B (2주 브랜치) |
|---|---|---|
| 총 변경량 | 동일 | 동일 |
| 병합 횟수 | 3 | 1 |
| 충돌 헝크 | 0 | __ |
| 사람의 판단 필요 | 없음 | 각 헝크마다 |
| 실패 시 원인 후보 | 마지막 작은 변경 | 2주치 전부 |
```

마지막 행이 진짜 비용입니다 — **통합 후 테스트가 깨졌을 때, A는 범인이 방금 그 커밋이고 B는 용의자가 수십 명**입니다. CI가 "매 통합마다 테스트"인 이유가 이것입니다.

## Step 5. 탈출구 — 피처 플래그의 논리

"기능이 완성돼야 합칠 수 있다"가 긴 브랜치의 진짜 원인입니다. 코드는 합치되 기능은 끄면?

```bash
git merge --abort
git checkout -q main
cat > app.py <<'EOF'
import os

FEATURE_FANCY_GREETING = os.getenv("FF_FANCY_GREETING", "false") == "true"

def greet(name):
    if FEATURE_FANCY_GREETING:        # 미완성 기능 — 켜지 않으면 없는 것과 같습니다
        return f"✨ Hello there, {name}! ✨"
    return f"Hello, {name}"

def main():
    print(greet("world"))

if __name__ == "__main__":
    main()
EOF
git commit -qam "feat: fancy greeting behind flag"

python3 app.py                              # Hello, world       (평소)
FF_FANCY_GREETING=true python3 app.py       # ✨ Hello there... (테스터만)
```

✅ **미완성 코드가 main에 있어도 안전합니다** — 트렁크 기반 개발(02)의 핵심 도구. 통합 주기와 기능 완성 주기를 분리하는 것이 열쇠입니다.

## 정리

```bash
cd ~ && rm -rf ~/ci-lab/merge-demo
```
