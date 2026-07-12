# 흔한 함정 5선

## 1. 한 줄 생성 후 설정 파일 없이 운영

`eksctl create cluster --name x`로 만들고 끝 — 몇 달 뒤 "이 클러스터 어떻게 만들었지?"에 답할 수 없고, DR/복제/리뷰가 전부 막힙니다. 지금이라도 ClusterConfig로 역문서화해 Git에(lab-01 Step 1). 인프라도 코드입니다.

## 2. aws-auth ConfigMap 직접 편집 (구세대 습관)

옛 블로그대로 aws-auth를 손으로 — 들여쓰기 실수 하나로 **전원 인증 불능**(편집 수단이 그 CM 자체라 잠금 사고). 현행 표준은 access entries(API 객체, 검증·감사 가능). authenticationMode를 확인하고, CONFIG_MAP 모드 클러스터는 이전을 계획하세요.

## 3. 생성자 IAM을 일상용으로

클러스터를 만든(=admin entry를 가진) 강력한 IAM 사용자를 평소 kubectl에도 — 유출 시 클러스터 전체 장악. 일상 작업은 최소 권한 역할(View/Edit + 필요 ns)로, admin은 브레이크글라스로 분리. lab-02에서 만든 구조가 그 모범입니다.

## 4. kubeconfig를 비밀처럼 공유

"동료에게 kubeconfig 파일을 보내줬어요" — EKS kubeconfig엔 비밀이 없어서(exec뿐) 받은 사람의 **자기 IAM**으로 인증됩니다. 접근이 안 되는 이유는 파일이 아니라 access entry 부재. 올바른 온보딩: entry 등록(lab-02) + 본인이 `aws eks update-kubeconfig`.

## 5. CloudFormation 스택을 우회한 수동 변경

eksctl이 만든 SG/서브넷을 콘솔에서 직접 수정 — 다음 `eksctl upgrade/delete`에서 충돌하거나 drift로 남습니다. 변경도 가능한 한 ClusterConfig→eksctl 경로로, 불가피한 수동 변경은 기록을. "스택이 모르는 변경"은 미래의 지뢰입니다.

## 실무 사고 사례

> 금요일 오후, 운영자가 aws-auth ConfigMap에 신규 입사자를 추가하다 mapRoles의 들여쓰기를 한 칸 어긋냈습니다 — 저장 즉시 **모든 사용자/노드 인증 실패**(노드 kubelet도 이 CM으로 매핑되던 클러스터). kubectl로 고치려니 kubectl이 안 됩니다. 복구: 클러스터 생성자 IAM(어디에도 기록 안 된 숨은 admin)을 수소문해 그 자격증명으로 CM 원복 — 4시간 장애. 이후 조치: ① authenticationMode를 API로 전환(access entries) ② 생성자 특권을 명시적 entry로 정리 ③ 권한 변경은 IaC+리뷰로만. 이 사고 패턴이 흔해서 access entries가 만들어진 것입니다.
