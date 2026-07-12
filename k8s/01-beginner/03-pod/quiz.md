# 자가 점검 퀴즈

**Q1.** Pod 안 컨테이너들이 공유하는 namespace 3가지와 공유하지 않는 것 1가지를 쓰라.

**Q2.** pause 컨테이너의 역할과, 그것이 있어서 가능한 동작 하나를 쓰라.

**Q3.** 컨테이너 A가 만든 파일을 같은 Pod의 컨테이너 B가 읽으려면 무엇이 필요한가?

**Q4.** 1.36 기준 네이티브 sidecar를 선언하는 정확한 방법은? 일반 init 컨테이너와의 동작 차이는?

**Q5.** `kubectl delete pod`가 12초나 걸렸습니다. 내부에서 무슨 일이 있었는지 시퀀스로 설명하세요.

**Q6.** CrashLoopBackOff 상태의 Pod를 디버깅하는 첫 명령은? (`logs`를 쓴다면 어떤 옵션이 핵심인가)

**Q7.** READY가 `1/2`인 Pod의 의미는?

---

## 정답

**A1.** 공유: **NET, IPC, UTS** (+볼륨). 비공유: **MNT**(파일시스템; PID도 기본 분리).

**A2.** Pod의 namespace 세트를 소유한 채 영원히 잠자는 infra 컨테이너. 덕분에 **앱 컨테이너가 재시작돼도 Pod IP가 유지**됩니다.

**A3.** 같은 볼륨(`emptyDir` 등)을 양쪽에 `volumeMounts`로 마운트. (MNT namespace는 분리라 볼륨 없이는 안 보임)

**A4.** `initContainers` 항목에 넣고 `restartPolicy: Always` 지정. 일반 init은 "종료돼야" 다음 단계로 가지만, sidecar는 **종료되지 않고** 본 컨테이너보다 먼저 시작해 Pod가 끝날 때까지 삽니다(종료는 본 컨테이너 이후).

**A5.** ① Terminating 마킹, 엔드포인트에서 제거 ② preStop hook ③ SIGTERM 전송 ④ 앱이 무시 → grace period(이 경우 ~10초) 대기 ⑤ SIGKILL. 즉 앱이 SIGTERM을 처리하지 않았습니다.

**A6.** `kubectl logs <pod> --previous` — 현재가 아니라 **죽기 직전 컨테이너의 로그**를 봐야 죽은 원인이 나옵니다. (+ `describe`의 Last State / Exit Code)

**A7.** 컨테이너 2개 중 1개만 Ready. 나머지 하나가 크래시 중이거나 readiness probe 실패 — `kubectl describe`로 어느 컨테이너인지 확인.
