package main

import (
	"net"
	"net/http"

	pb "github.com/finn/eks-study/user-service/proto/userv1"
	"github.com/finn/eks-study/user-service/server"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
	"google.golang.org/grpc"
)

func main() {
	log := logger.New("user-service")
	port := cfg.GetString("GRPC_PORT", "50051")

	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Error("listen", "err", err)
		return
	}
	s := grpc.NewServer()
	pb.RegisterUserServiceServer(s, server.New())

	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", metrics.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
		_ = http.ListenAndServe(":9090", mux)
	}()

	log.Info("gRPC starting", "port", port)
	if err := s.Serve(lis); err != nil {
		log.Error("serve", "err", err)
	}
}
