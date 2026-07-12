package consumer

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

type Client interface {
	ReceiveMessage(ctx context.Context, in *sqs.ReceiveMessageInput, opts ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error)
	DeleteMessage(ctx context.Context, in *sqs.DeleteMessageInput, opts ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error)
}

type Consumer struct {
	client   Client
	queueURL string
	Handler  func(ctx context.Context, payload []byte) error
}

func New(client Client, queueURL string) *Consumer {
	return &Consumer{client: client, queueURL: queueURL}
}

func (c *Consumer) PollOnce(ctx context.Context) error {
	out, err := c.client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(c.queueURL),
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     5,
	})
	if err != nil {
		return fmt.Errorf("receive: %w", err)
	}
	for _, m := range out.Messages {
		if err := c.Handler(ctx, []byte(*m.Body)); err != nil {
			continue
		}
		_, _ = c.client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
			QueueUrl:      aws.String(c.queueURL),
			ReceiptHandle: m.ReceiptHandle,
		})
	}
	return nil
}

func (c *Consumer) Run(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			if err := c.PollOnce(ctx); err != nil {
				return err
			}
		}
	}
}
