# 학습 가이드 — Pod를 "왜"부터 배우기

## 이 모듈의 질문 3개

1. **왜 컨테이너를 직접 안 다루고 Pod라는 포장을 씌웠나요?** — "항상 같이 다녀야 하는 컨테이너들"(앱+로그수집기 등)을 원자 단위로 스케줄링하기 위해. 답은 namespace 공유에 있습니다.
2. **`kubectl get pods`에 안 보이는 pause 컨테이너는 뭔가?** — Pod의 namespace를 "들고 있는" 뼈대. 이걸 알면 "컨테이너가 재시작돼도 Pod IP가 안 바뀌는" 이유가 풀립니다.
3. **Pod는 언제 죽고 어떻게 죽나요?** — phase 전이와 종료 시퀀스(SIGTERM → 유예 → SIGKILL). graceful shutdown은 중급(모듈 14)에서 다시 깊게.

## 학습 전략

- theory의 "Pod = namespace 공유 그룹" 정의를 lab-01에서 `kubectl exec`로 직접 검증하는 흐름입니다. **두 컨테이너가 정말 같은 IP인지 눈으로 확인할 것.**
- init vs sidecar의 차이는 표로 외우지 말고 lab-02에서 **시작 순서를 타임라인으로 관찰**해서 익혀라.
- 이 모듈에서 Pod를 직접(`kind: Pod`) 만들지만, 다음 모듈부터는 절대 직접 만들지 않습니다(Deployment 사용). "직접 만들면 왜 안 되는지"를 마지막 퀴즈에서 확인.

## 연결

- 모듈 01의 NET namespace → Pod 정의의 근거
- 모듈 14(probe/graceful shutdown), 모듈 26(kubelet이 Pod를 만드는 코드 경로)에서 심화
