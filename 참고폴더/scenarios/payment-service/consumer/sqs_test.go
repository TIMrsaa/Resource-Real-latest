package consumer

import (
	"context"
	"errors"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

type fakeClient struct {
	messages   []types.Message
	deletedIDs []string
	receiveErr error
}

func (f *fakeClient) ReceiveMessage(_ context.Context, _ *sqs.ReceiveMessageInput, _ ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error) {
	if f.receiveErr != nil {
		return nil, f.receiveErr
	}
	out := &sqs.ReceiveMessageOutput{Messages: f.messages}
	f.messages = nil
	return out, nil
}

func (f *fakeClient) DeleteMessage(_ context.Context, in *sqs.DeleteMessageInput, _ ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error) {
	f.deletedIDs = append(f.deletedIDs, *in.ReceiptHandle)
	return &sqs.DeleteMessageOutput{}, nil
}

func TestConsumerProcessesAndDeletesMessages(t *testing.T) {
	body := `{"order_id":"o1","amount":100}`
	rh := "rh-1"
	client := &fakeClient{messages: []types.Message{{Body: &body, ReceiptHandle: &rh}}}

	c := New(client, "https://example/q")
	processed := 0
	c.Handler = func(ctx context.Context, payload []byte) error {
		processed++
		return nil
	}

	if err := c.PollOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if processed != 1 {
		t.Errorf("expected 1 processed, got %d", processed)
	}
	if len(client.deletedIDs) != 1 {
		t.Errorf("expected 1 deletion, got %d", len(client.deletedIDs))
	}
}

func TestConsumerSurfacesReceiveError(t *testing.T) {
	client := &fakeClient{receiveErr: errors.New("boom")}
	c := New(client, "q")
	c.Handler = func(_ context.Context, _ []byte) error { return nil }
	if err := c.PollOnce(context.Background()); err == nil {
		t.Fatal("expected error, got nil")
	}
}
