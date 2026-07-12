# user-service

gRPC 기반 사용자 CRUD 서비스. **서비스 간 통신** 학습용
(Part 2 09 모듈에서 order-service가 호출하는 형태로 사용 예정).

---

## REST vs gRPC (왜 한 서비스를 gRPC로?)

| 항목 | REST/HTTP | gRPC |
|------|-----------|------|
| 직렬화 | JSON (텍스트, 가독성 ↑) | Protobuf (바이너리, 크기 ↓) |
| 전송 | HTTP/1.1 또는 2 | HTTP/2 (스트리밍) |
| 스키마 | OpenAPI (선택) | .proto 파일 (필수, 강타입) |
| 성능 | 느림 (텍스트 파싱) | ~5-10x 빠름 |
| 브라우저 직접 호출 | ✅ | ❌ (gRPC-Web 필요) |
| 서비스 간 내부 통신 | OK | **권장** |

→ 본 커리큘럼은 "외부 노출 = REST(order-service), 내부 = gRPC(user-service)"
   라는 실무 패턴을 시뮬레이션.

---

## 코드 한눈에 보기

```
main.go
  ├─ net.Listen("tcp", ":50051")      # gRPC는 표준 포트 50051
  ├─ grpc.NewServer() + RegisterUserServiceServer(서버 구현체)
  ├─ :9090 메트릭/헬스체크 (별도 고루틴)
  └─ s.Serve(lis)                      # 블로킹, ctrl+c 까지 대기

server/user.go
  └─ User 구조체에 in-memory map (order-service와 동일 패턴)
  └─ GetUser, CreateUser 메서드 구현 (UserServiceServer 인터페이스)

proto/user.proto
  └─ 서비스 + 메시지 정의 (코드 생성의 단일 진실)

proto/userv1/*.pb.go
  └─ protoc 가 자동 생성한 Go 코드 (절대 수동 수정 X)
```

---

## 인터페이스

`proto/user.proto` 참고:

```proto
service UserService {
  rpc GetUser(GetUserRequest) returns (User);
  rpc CreateUser(CreateUserRequest) returns (User);
}
```

**proto 파일이 단일 진실의 원천 (Single Source of Truth)**:
- Go, Java, Python 등 어떤 언어든 같은 .proto에서 코드 생성
- 클라이언트/서버 인터페이스 자동 동기화
- 버전 관리 가능 (proto에 새 필드 추가 → 하위 호환)

---

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `GRPC_PORT` | `50051` | gRPC 리스너 포트 |

---

## 로컬 실행

```bash
go run .
# 출력: gRPC starting port=50051
```

---

## 호출 예시 (`grpcurl` 필요)

`grpcurl` = REST의 curl 같은 gRPC용 명령어 도구.

```bash
brew install grpcurl

# 사용자 생성
grpcurl -plaintext -d '{"name":"finn","email":"f@x.io"}' \
  localhost:50051 user.v1.UserService/CreateUser
# → {"id":"<uuid>","name":"finn","email":"f@x.io"}

# 사용자 조회
grpcurl -plaintext -d '{"id":"<uuid>"}' \
  localhost:50051 user.v1.UserService/GetUser
```

`-plaintext` = TLS 안 씀 (학습용). 운영은 mTLS 필수.

---

## 테스트

```bash
go test ./...
```

---

## proto 코드 재생성

`proto/user.proto` 를 수정한 경우 Go 코드 재생성:

```bash
PATH=$PATH:$(go env GOPATH)/bin protoc \
  --go_out=. --go_opt=paths=source_relative \
  --go-grpc_out=. --go-grpc_opt=paths=source_relative \
  proto/user.proto
mv proto/user.pb.go proto/userv1/
mv proto/user_grpc.pb.go proto/userv1/
```

생성된 `*.pb.go` 는 절대 손대지 말고, .proto만 수정 후 재생성.

---

## K8s 배포 패턴 (Part-2-09)

```yaml
spec:
  ports:
    - name: grpc
      port: 50051
      targetPort: 50051
      appProtocol: grpc        # K8s 1.20+ 표준 (LB가 H2 라우팅 인식)
```

**gRPC + LB 주의점**:
- ALB는 gRPC를 잘 지원 (HTTP/2, gRPC streaming 가능)
- NLB는 L4라 잘 동작 (단순 TCP 분배)
- ClusterIP + headless 조합으로 클라이언트 사이드 LB도 가능
  (gRPC는 long-lived connection이라 첫 연결만 분산되는 함정 주의)
