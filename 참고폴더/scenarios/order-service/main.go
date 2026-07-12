package main

import (
	"log/slog"
	"net/http"

	"github.com/finn/eks-study/order-service/handler"
	"github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
	"github.com/gin-gonic/gin"
)

func main() {
	log := logger.New("order-service")
	port := config.GetString("PORT", "8080")

	r := gin.New()
	r.Use(gin.Recovery())
	h := handler.New()
	r.POST("/orders", h.Create)
	r.GET("/orders/:id", h.Get)
	r.GET("/healthz", func(c *gin.Context) { c.Status(http.StatusOK) })

	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", metrics.Handler())
		if err := http.ListenAndServe(":9090", mux); err != nil {
			log.Error("metrics server failed", "err", err)
		}
	}()

	log.Info("starting", "port", port)
	if err := r.Run(":" + port); err != nil {
		slog.Error("server failed", "err", err)
	}
}
