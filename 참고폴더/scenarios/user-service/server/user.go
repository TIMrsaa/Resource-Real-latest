package server

import (
	"context"
	"sync"

	pb "github.com/finn/eks-study/user-service/proto/userv1"
	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type Server struct {
	pb.UnimplementedUserServiceServer
	mu    sync.RWMutex
	users map[string]*pb.User
}

func New() *Server { return &Server{users: make(map[string]*pb.User)} }

func (s *Server) CreateUser(_ context.Context, req *pb.CreateUserRequest) (*pb.User, error) {
	u := &pb.User{Id: uuid.NewString(), Name: req.Name, Email: req.Email}
	s.mu.Lock()
	s.users[u.Id] = u
	s.mu.Unlock()
	return u, nil
}

func (s *Server) GetUser(_ context.Context, req *pb.GetUserRequest) (*pb.User, error) {
	s.mu.RLock()
	u, ok := s.users[req.Id]
	s.mu.RUnlock()
	if !ok {
		return nil, status.Error(codes.NotFound, "user not found")
	}
	return u, nil
}
