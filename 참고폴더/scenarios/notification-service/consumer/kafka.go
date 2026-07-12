package consumer

import (
	"context"

	"github.com/segmentio/kafka-go"
)

type Reader interface {
	FetchMessage(ctx context.Context) (kafka.Message, error)
	CommitMessages(ctx context.Context, msgs ...kafka.Message) error
	Close() error
}

type Consumer struct {
	r       Reader
	Handler func(ctx context.Context, payload []byte) error
}

func New(r Reader) *Consumer { return &Consumer{r: r} }

func (c *Consumer) Run(ctx context.Context) error {
	for {
		m, err := c.r.FetchMessage(ctx)
		if err != nil {
			return err
		}
		if err := c.Handler(ctx, m.Value); err != nil {
			continue
		}
		_ = c.r.CommitMessages(ctx, m)
	}
}
