package rabbitmq

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"database/sql"
	"encoding/json"
	"errors"
	"net"
	"os"
	"sync/atomic"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
	"oil-price-tracker/fetcher/internal/model"
)

type Publisher struct {
	DB                                           *sql.DB
	URL, CAFile, Exchange, RoutingKey, QueueName string
	Timeout, PollInterval                        time.Duration
	BatchSize                                    int
	Ready                                        atomic.Bool
}

func (p *Publisher) Publish(ctx context.Context, observations []model.Observation) error {
	if len(observations) == 0 {
		return errors.New("cannot publish an empty event")
	}
	key := "oil-prices:" + observations[0].ScheduledFor.UTC().Format(time.RFC3339)
	body, err := json.Marshal(struct {
		SchemaVersion int                 `json:"schema_version"`
		EventKey      string              `json:"event_key"`
		Observations  []model.Observation `json:"observations"`
	}{1, key, observations})
	if err != nil {
		return err
	}
	_, err = p.DB.ExecContext(ctx, `INSERT INTO published_queue_events(event_key,payload,status)
 VALUES($1,$2::jsonb,'pending') ON CONFLICT(event_key) DO NOTHING`, key, string(body))
	return err
}

// Each attempt owns its transport. An unconfirmed send remains retryable even
// when the broker may have accepted it before the connection timed out.
func (p *Publisher) send(ctx context.Context, body []byte) error {
	brokerCtx, cancel := context.WithTimeout(ctx, p.Timeout)
	defer cancel()

	// Registered before AMQP cleanup so cancellation stays active during the
	// graceful channel/connection closes, and also covers failed handshakes.
	var closeTransport func()
	defer func() {
		if closeTransport != nil {
			closeTransport()
		}
	}()

	uri, err := amqp.ParseURI(p.URL)
	if err != nil {
		return errors.New("invalid RabbitMQ URL")
	}
	if uri.Scheme != "amqps" {
		return errors.New("RabbitMQ requires amqps")
	}
	pem, err := os.ReadFile(p.CAFile)
	if err != nil {
		return err
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(pem) {
		return errors.New("invalid RabbitMQ CA")
	}
	conn, err := amqp.DialConfig(p.URL, amqp.Config{
		TLSClientConfig: &tls.Config{RootCAs: roots, ServerName: uri.Host, MinVersion: tls.VersionTLS12},
		Dial: func(network, address string) (net.Conn, error) {
			c, e := (&net.Dialer{}).DialContext(brokerCtx, network, address)
			if e != nil {
				return nil, e
			}
			// amqp091-go clears socket deadlines after its handshake and does
			// not honour publish contexts. Closing the raw socket interrupts
			// TLS, AMQP RPCs, writes, and cleanup regardless of those behaviors.
			stop := context.AfterFunc(brokerCtx, func() { _ = c.Close() })
			closeTransport = func() {
				stop()
				_ = c.Close()
			}
			return c, nil
		},
	})
	if err != nil {
		return errors.New("RabbitMQ connection failed")
	}
	defer conn.Close()
	ch, err := conn.Channel()
	if err != nil {
		return err
	}
	defer ch.Close()
	if _, err = ch.QueueInspect(p.QueueName); err != nil {
		return err
	}
	if body == nil {
		return nil
	}
	if err = ch.Confirm(false); err != nil {
		return err
	}
	returned := ch.NotifyReturn(make(chan amqp.Return, 1))
	confirm, err := ch.PublishWithDeferredConfirm(p.Exchange, p.RoutingKey, true, false, amqp.Publishing{
		ContentType: "application/json", DeliveryMode: amqp.Persistent, Body: body,
	})
	if err != nil {
		return err
	}
	ok, err := confirm.WaitContext(brokerCtx)
	if err != nil {
		return err
	}
	select {
	case <-returned:
		return errors.New("RabbitMQ returned an unroutable message")
	default:
	}
	if !ok {
		return errors.New("RabbitMQ rejected the message")
	}
	return nil
}

func (p *Publisher) dispatch(ctx context.Context) (bool, error) {
	tx, err := p.DB.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	var key string
	var body []byte
	err = tx.QueryRowContext(ctx, `SELECT event_key,payload FROM published_queue_events
 WHERE status='pending' AND next_attempt_at<=now() ORDER BY next_attempt_at,event_key
 LIMIT 1 FOR UPDATE SKIP LOCKED`).Scan(&key, &body)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	sendErr := p.send(ctx, body)
	if sendErr == nil {
		_, err = tx.ExecContext(ctx, `UPDATE published_queue_events SET status='sent',sent_at=now() WHERE event_key=$1`, key)
	} else {
		_, err = tx.ExecContext(ctx, `UPDATE published_queue_events SET
 next_attempt_at=now()+LEAST(power(2,LEAST(attempt_count,9))*interval '1 second',interval '5 minutes'),
 attempt_count=LEAST(attempt_count::bigint+1,2147483647)::integer WHERE event_key=$1`, key)
	}
	if err != nil {
		return true, err
	}
	if err = tx.Commit(); err != nil {
		return true, err
	}
	return true, sendErr
}

func (p *Publisher) Run(ctx context.Context) {
	timer := time.NewTicker(p.PollInterval)
	defer timer.Stop()
	for {
		for n := 0; n < p.BatchSize && ctx.Err() == nil; n++ {
			// Keep DB bookkeeping alive briefly after a broker deadline expires.
			attempt, cancel := context.WithTimeout(ctx, p.Timeout+5*time.Second)
			found, err := p.dispatch(attempt)
			if !found && err == nil {
				err = p.send(attempt, nil)
			}
			cancel()
			p.Ready.Store(err == nil)
			if !found {
				break
			}
		}
		select {
		case <-ctx.Done():
			p.Ready.Store(false)
			return
		case <-timer.C:
		}
	}
}
