package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os/signal"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/finn/eks-study/payment-service/consumer"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
)

func main() {
	log := logger.New("payment-service")
	queueURL := cfg.GetString("SQS_QUEUE_URL", "")
	if queueURL == "" {
		log.Error("SQS_QUEUE_URL is required")
		return
	}

	awsCfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Error("aws config", "err", err)
		return
	}
	c := consumer.New(sqs.NewFromConfig(awsCfg), queueURL)
	c.Handler = func(ctx context.Context, payload []byte) error {
		var msg map[string]any
		_ = json.Unmarshal(payload, &msg)
		log.Info("processed payment", "msg", msg)
		return nil
	}

	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", metrics.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
		_ = http.ListenAndServe(":9090", mux)
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log.Info("starting consumer", "queue", queueURL)
	if err := c.Run(ctx); err != nil && err != context.Canceled {
		log.Error("run failed", "err", err)
	}
}
