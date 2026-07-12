# 흔한 함정 5선

## 1. 캐시 sync 전에 일 시작

`WaitForCacheSync` 없이 워커를 돌리면 — 캐시가 비어 "객체 없음"으로 오판해 삭제/생성 폭주를 만들 수 있습니다 (특히 "캐시에 없으면 자식 삭제" 류 로직과 결합하면 참사). sync 대기는 의식이 아니라 안전벨트입니다.

## 2. 핸들러 안에서 무거운 일 하기

이벤트 핸들러는 informer의 배달 고루틴에서 돕니다 — 여기서 API 호출/슬립을 하면 **전체 이벤트 배달이 막힙니다.** 핸들러의 일은 "키를 큐에 넣기"까지. 처리는 워커에서.

## 3. 캐시에서 받은 객체를 직접 수정

Lister/Indexer가 주는 포인터는 **공유 캐시의 원본**입니다 — 필드를 고치면 캐시가 오염되어 다른 코드가 "유령 상태"를 봅니다. 수정 전 `DeepCopy()`가 철칙. (controller-runtime client는 기본적으로 복사본을 주지만, 생짜 Lister는 아닙니다!)

## 4. DeleteFunc의 tombstone 처리 누락

삭제 이벤트의 obj가 실제 객체가 아니라 `DeletedFinalStateUnknown`(tombstone)일 수 있습니다 (watch 단절 중 삭제된 경우). 타입 단언이 panic — 표준 처리:

```go
if tomb, ok := obj.(cache.DeletedFinalStateUnknown); ok { obj = tomb.Obj }
```

## 5. 셀렉터 없는 전체 watch

필요한 건 라벨 몇 개짜리인데 전 네임스페이스 전체 Pod를 informer로 — 메모리(캐시에 전부 적재)와 API 부하 둘 다 낭비. factory 옵션의 LabelSelector/FieldSelector/Namespace로 **watch 범위 최소화**가 client-go 매너의 핵심 (모듈 21 사고사례의 예방책).

## 실무 사고 사례

> 사내 감사 도구가 informer로 전 클러스터 Secret을 캐싱했습니다(셀렉터 없음). 클러스터가 크자 도구의 메모리가 8GB를 넘어 OOMKilled 반복 — 재시작마다 **전체 Secret List**가 발생해 API 서버/etcd에 주기적 부하 스파이크(410→relist 폭풍과 같은 모양). 게다가 Secret 전체 캐싱은 그 Pod 침해 시 전 클러스터 자격증명 노출이라는 보안 문제이기도 했습니다. 수정: 감사에 필요한 메타데이터만(PartialObjectMetadata informer) + 네임스페이스 샤딩. 교훈: **informer는 공짜 캐시가 아니라 "전부 메모리에 들고 있겠다"는 선언**입니다 — 무엇을 들지 골라라.
