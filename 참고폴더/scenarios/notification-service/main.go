package main

import (
	"context"
	"net/http"
	"os/signal"
	"strings"
	"syscall"

	"github.com/finn/eks-study/notification-service/consumer"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
	"github.com/segmentio/kafka-go"
)

func main() {
	log := logger.New("notification-service")
	brokers := strings.Split(cfg.GetString("KAFKA_BROKERS", "localhost:9092"), ",")
	topic := cfg.GetString("KAFKA_TOPIC", "notifications")
	group := cfg.GetString("KAFKA_GROUP", "notification-service")

	r := kafka.NewReader(kafka.ReaderConfig{
		Brokers: brokers, Topic: topic, GroupID: group,
	})
	defer r.Close()

	c := consumer.New(r)
	c.Handler = func(_ context.Context, payload []byte) error {
		log.Info("notification", "payload", string(payload))
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
	log.Info("kafka consumer starting", "topic", topic, "group", group)
	if err := c.Run(ctx); err != nil && err != context.Canceled {
		log.Error("consumer", "err", err)
	}
}
