package messaging

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

type CommandPublisher struct {
	URL        string
	Exchange   string
	Queue      string
	RoutingKey string
}

type BackfillCommand struct {
	CommandID   string `json:"command_id"`
	CommandType string `json:"command_type"`
	Schema      int    `json:"schema_version"`
	RequestID   string `json:"request_id"`
	Instrument  string `json:"instrument_id"`
	From        string `json:"from"`
	To          string `json:"to"`
}

func (p *CommandPublisher) PublishBackfill(ctx context.Context, command BackfillCommand) error {
	connection, err := amqp.Dial(p.URL)
	if err != nil {
		return err
	}
	defer connection.Close()
	channel, err := connection.Channel()
	if err != nil {
		return err
	}
	defer channel.Close()
	if err := channel.Confirm(false); err != nil {
		return err
	}
	if err := declareCommandTopology(channel, p.Exchange, p.Queue, p.RoutingKey); err != nil {
		return err
	}
	body, err := json.Marshal(command)
	if err != nil {
		return err
	}
	confirmation := channel.NotifyPublish(make(chan amqp.Confirmation, 1))
	if err := channel.PublishWithContext(ctx, p.Exchange, p.RoutingKey, true, false, amqp.Publishing{
		ContentType: "application/json", DeliveryMode: amqp.Persistent,
		MessageId: command.CommandID, CorrelationId: command.RequestID,
		Timestamp: time.Now().UTC(), Body: body,
	}); err != nil {
		return err
	}
	select {
	case result := <-confirmation:
		if !result.Ack {
			return fmt.Errorf("rabbitmq did not confirm backfill command")
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func declareCommandTopology(channel *amqp.Channel, exchange, queue, route string) error {
	dlx := exchange + ".dlx"
	if err := channel.ExchangeDeclare(exchange, "direct", true, false, false, false, nil); err != nil {
		return err
	}
	if err := channel.ExchangeDeclare(dlx, "direct", true, false, false, false, nil); err != nil {
		return err
	}
	if _, err := channel.QueueDeclare(queue+".dlq", true, false, false, false, nil); err != nil {
		return err
	}
	if err := channel.QueueBind(queue+".dlq", queue, dlx, false, nil); err != nil {
		return err
	}
	arguments := amqp.Table{"x-dead-letter-exchange": dlx, "x-dead-letter-routing-key": queue}
	if _, err := channel.QueueDeclare(queue, true, false, false, false, arguments); err != nil {
		return err
	}
	return channel.QueueBind(queue, route, exchange, false, nil)
}
