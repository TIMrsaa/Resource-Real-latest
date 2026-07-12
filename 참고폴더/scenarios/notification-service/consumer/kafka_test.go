package consumer

import (
	"context"
	"errors"
	"io"
	"testing"

	"github.com/segmentio/kafka-go"
)

type fakeReader struct {
	msgs []kafka.Message
	idx  int
}

func (f *fakeReader) FetchMessage(_ context.Context) (kafka.Message, error) {
	if f.idx >= len(f.msgs) {
		return kafka.Message{}, io.EOF
	}
	m := f.msgs[f.idx]
	f.idx++
	return m, nil
}
func (f *fakeReader) CommitMessages(_ context.Context, _ ...kafka.Message) error { return nil }
func (f *fakeReader) Close() error                                                 { return nil }

func TestProcessHandlesAllMessagesUntilEOF(t *testing.T) {
	r := &fakeReader{msgs: []kafka.Message{
		{Value: []byte(`{"to":"u1","msg":"hi"}`)},
		{Value: []byte(`{"to":"u2","msg":"yo"}`)},
	}}
	c := New(r)
	count := 0
	c.Handler = func(_ context.Context, _ []byte) error { count++; return nil }

	err := c.Run(context.Background())
	if !errors.Is(err, io.EOF) {
		t.Fatalf("expected EOF, got %v", err)
	}
	if count != 2 {
		t.Errorf("expected 2 processed, got %d", count)
	}
}
