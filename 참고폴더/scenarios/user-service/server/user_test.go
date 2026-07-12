package server

import (
	"context"
	"testing"

	pb "github.com/finn/eks-study/user-service/proto/userv1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func TestCreateAndGetUser(t *testing.T) {
	s := New()
	created, err := s.CreateUser(context.Background(), &pb.CreateUserRequest{Name: "finn", Email: "f@x.io"})
	if err != nil {
		t.Fatal(err)
	}
	if created.Id == "" {
		t.Fatal("expected non-empty id")
	}
	got, err := s.GetUser(context.Background(), &pb.GetUserRequest{Id: created.Id})
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "finn" {
		t.Errorf("expected finn, got %s", got.Name)
	}
}

func TestGetUserNotFoundReturnsNotFound(t *testing.T) {
	s := New()
	_, err := s.GetUser(context.Background(), &pb.GetUserRequest{Id: "missing"})
	if err == nil {
		t.Fatal("expected error")
	}
	if status.Code(err) != codes.NotFound {
		t.Errorf("expected NotFound, got %v", status.Code(err))
	}
}
