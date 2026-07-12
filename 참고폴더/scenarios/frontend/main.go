package main

import (
	"net/http"

	"github.com/finn/eks-study/frontend/handler"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
)

func main() {
	log := logger.New("frontend")
	port := cfg.GetString("PORT", "8080")

	h, err := handler.New("templates/*.html")
	if err != nil {
		log.Error("template parse", "err", err)
		return
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", h.Index)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
	mux.Handle("/metrics", metrics.Handler())

	log.Info("frontend starting", "port", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Error("listen", "err", err)
	}
}
