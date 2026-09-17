# RabbitMQ role

Runs a durable RabbitMQ container on the former database VM when
`database_mode` is `managed`. AMQP listens on the private VM interface while
the management UI is bound to loopback only. The role never removes the
self-hosted PostgreSQL volume.
