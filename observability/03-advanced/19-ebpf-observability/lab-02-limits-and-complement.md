# Lab 02 — 한계의 실증과 OTel 분담 설계

> eBPF 관측의 한계 세 가지(앱 내부·여정·TLS)를 실험으로 확인하고, "eBPF + OTel"의 분담표를 설계합니다. 도구 애호가 아니라 영토 지도를 만드는 것이 목적입니다.

## 0. 준비 (lab-01 이어서)

## 1. 한계 ① 실증 — 앱 내부는 안 보입니다

```bash
# 내부에서 시간을 쓰는 앱 (sleep = 내부 처리 흉내)
kubectl -n shop delete deployment backend
kubectl -n shop create deployment backend --image=busybox -- sh -c '
  while true; do
    { echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"; sleep 0.001; } | nc -l -p 8080 -q 1;
  done' 2>/dev/null || \
kubectl -n shop create deployment slow-backend --image=python:3.12-slim -- sh -c '
  pip install flask -q && python -c "
from flask import Flask; import time
app = Flask(__name__)
@app.route(\"/\")
def slow():
    time.sleep(1.2)          # 내부 처리 1.2s — DB? 계산? 커널은 모릅니다
    return \"ok\"
app.run(host=\"0.0.0.0\", port=8080)"'
sleep 60

cilium hubble port-forward &
sleep 3
hubble observe --namespace shop --protocol http --last 5
# http-request → (1.2s 후) http-response 200
# → 지연이 "있다"는 것은 보입니다 (요청·응답 시각차)
# → 그러나 그 1.2초가 무엇인지(DB 대기? GC? 계산?)는 커널의 시야 밖
```

**결론** — eBPF는 "이 서비스가 느리다"까지(구간의 사실), "안에서 무엇이"는 계측(11)의 span·속성 또는 프로파일링(20)의 스택이 필요합니다. 층이 다릅니다.

## 2. 한계 ② 실증 — 여정을 이을 실이 없습니다

```bash
# frontend가 두 백엔드를 순차 호출하는 구조라면 (A→B, A→C):
hubble observe --namespace shop --last 20
# frontend→B의 흐름과 frontend→C의 흐름이 각각 보입니다
# ★ 그러나 "같은 사용자 요청에서 나온 호출들"인지 알 수 없습니다
#   — 커널엔 trace_id가 없습니다 (그건 앱이 헤더에 싣는 약속, 04)
# 동시 요청이 섞이면: 흐름들의 시간 상관으로도 확정 불가
```

**결론** — 04의 정의 그대로: 여정(trace)은 컨텍스트 전파라는 앱 수준 약속의 산물입니다. eBPF 관측은 트레이스의 **대체가 아니라 이웃** — 구간 사실(eBPF)과 여정(OTel)은 다른 질문에 답합니다.

## 3. 한계 ③ 확인 — TLS (개념 실험)

```
frontend→backend를 HTTPS로 바꾸면:
  L4 흐름: 여전히 보임 (누가 누구와, 얼마나)
  L7 파싱: 소켓의 바이트가 암호문 — HTTP 경로·코드 소멸
uprobe(SSL_write 후킹) 접근: 라이브러리·정적 링크 여부에 의존 — 일반해 아님
서비스 메시(cncf 24)의 mTLS 환경: 사이드카/ztunnel 경유 구간의 가시성은
  메시 자신의 텔레메트리가 맡는 구조가 자연스러움
→ "암호화가 늘수록 L7 자동 관측의 영토는 줄어든다" — 설계 시 전제할 것
```

## 4. 분담표 설계 — 영토 지도 (이 모듈의 산출물)

질문 카탈로그(05)를 도구 영토에 매핑합니다:

| 질문 | eBPF(Hubble류) | OTel(11·16) | 프로파일링(20) | X-Ray(17) |
|------|---------------|-------------|---------------|-----------|
| 누가 누구와 통신? | ★ 즉답 | 계측된 곳만 | — | AWS 구간 포함 |
| 연결이 왜 안 됨? | ★ verdict | — | — | — |
| 서비스 RED(무계측) | ★ L7 파싱(평문) | — | — | — |
| 요청의 여정(어디가) | ✗ 실이 없음 | ★ trace | — | ★ +AWS 구간 |
| 앱 내부 "왜 1.2s" | ✗ | 수동 span | ★ 스택 | — |
| 비즈니스 맥락(금액·테넌트) | ✗ | ★ 속성 | — | annotation |
| DNS 이상(ndots) | ★ 흐름 | — | — | — |
| TLS 트래픽 L7 | △ 조건부 | ★ (앱 안이라 무관) | — | ★ |

```
도입 순서의 정석 (theory 5절 재확인):
  ① eBPF 기본 지도 — 즉시·전체·마찰 0 (특히 CNI가 이미 Cilium이면 공짜에 가까움)
  ② 핵심 경로 OTel — 여정·맥락이 필요한 곳부터 (04의 가치)
  ③ 필요 지점 프로파일링(20) — "내부의 왜"가 반복되는 곳
  각 단계에서 "이 질문은 누구의 영토?"를 표로 확인 — 중복 투자도
  공백 방치도 피합니다 (17의 공백 목록화의 일반화)
```

## 5. SIGNALS-MAP 갱신 (과제)

```
새 줄 추가:
  네트워크 흐름: Hubble(eBPF) — verdict·L7(평문)·DNS  ✅
  영토 지도: 분담표(위)를 SIGNALS-MAP에 첨부 — 질문→도구 매핑
갱신 로그: "19 수료 — 계측 없는 지도 확보, 한계·분담 명시"
```

## 6. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name ebpf
rm -f /tmp/kind-cilium.yaml
```

## 정리

- 한계 실증: 1.2초는 보여도 그 내역은 안 보임(①), 흐름들을 여정으로 이을 실이 없음(②), TLS에서 L7 소멸(③)
- eBPF는 트레이스의 대체가 아니라 이웃 — 구간의 사실 vs 여정의 인과
- 분담표(질문→영토)가 이 모듈의 산출물 — 중복 투자와 공백 방치를 동시에 예방
- 도입 정석: eBPF 지도(즉시) → OTel 여정(핵심부터) → 프로파일링(반복되는 내부 의문)
- **★ 도구의 영토를 정확히 아는 것이 관측 아키텍처 설계입니다 — 다음: 앱 내부의 최심부(20)**
