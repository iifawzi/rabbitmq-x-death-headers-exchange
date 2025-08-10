# RabbitMQ X-Death Headers Exchange

<img width="1359" height="781" alt="Screenshot 2025-08-10 at 23 48 40" src="https://github.com/user-attachments/assets/9370c17e-0a34-4fdb-bc81-f50df22ac865" />


## Overview

The X-Death Headers Exchange is a custom RabbitMQ exchange type that extends the standard headers exchange functionality by enabling routing decisions based on the `x-death` headers. This solves a limitation in RabbitMQ where the standard headers exchange cannot route messages based on death information.

## Problem Solved

In standard RabbitMQ, when a message is dead-lettered (rejected, expired, or queue exceeded), it accumulates `x-death` headers containing information about why and where it "died". However, the standard headers exchange doesn't allow routing based on them. 

This exchange type removes that limitation. Making it possible to have bindings on x-death information when using `all-with-x` and `any-with-x` matchings. 


If you're looking for more advanced routing capabilities for more sophisticated DLQ topologies, you might be looking for [RADLX](https://github.com/iifawzi/rabbitmq-retry-aware-dlx) (RabbitMQ exchange that enables atomic, per-message death decisions with retries) 

## Installation

1. Download the compatible version from the [releases](releases/) directory
2. Place the `.ez` file in your RabbitMQ plugins directory
3. Enable the plugin:
```bash
rabbitmq-plugins enable rabbitmq_retry_aware_dlx
```

### Version Compatibility

| RabbitMQ Version | Plugin Version  |
|------------------|-----------------|
| 4.0.4+           | v4.1.3          |
| 4.0.0 - 4.0.3    | v4.0.3          |
| 3.13.3 - 3.13.7  | v3.13.7         |
| 3.13.0 - 3.13.2  | v3.13.2         |

For other versions, please [create an issue](https://github.com/your-repo/issues).

## How It Works

### Header Mapping

When a message with x-death headers arrives to the exchange, the death information is automatically mapped to routable headers with the following pattern:

```
x-death[<queue_name>][<reason>]-<property> = <value>
```

For example, if a message was rejected from a queue named "orders", the following headers would be created:
- `x-death[orders][rejected]-count` = 1
- `x-death[orders][rejected]-exchange` = "original.exchange"
- `x-death[orders][rejected]-routing-keys` = "order.created,order.processed"

### Routing Example

```
┌─────────────────┐
│ Original Queue  │
│    "orders"     │
└────────┬────────┘
         │ Message rejected
         ▼
┌─────────────────┐     x-death header:
│  Dead Letter    │     [{
│    Exchange     │       queue: "orders",
│ "x-death-dlx"   │       reason: "rejected",
│                 │       count: 1,
└────────┬────────┘       exchange: "app.exchange",
         │                routing-keys: ["order.new"]
         │              }]
         ▼
┌─────────────────────────────────────────┐
│     X-Death Headers Exchange Maps to:   │
│                                         │
│  x-death[orders][rejected]-count = 1    │
│  x-death[orders][rejected]-exchange =   │
│           "app.exchange"                │
│  x-death[orders][rejected]-routing-keys │
│           = "order.new"                 │
└──────────────┬──────────────────────────┘
               │
               ├─── Binding 1: x-match="all-with-x"
               │    x-death[orders][rejected]-count = 1
               │    ▼
               │    ┌─────────────────┐
               │    │ Retry Queue     │
               │    └─────────────────┘
```

## Usage Example

```bash
# Declare the x-death-headers exchange
rabbitmqadmin declare exchange name=dlx type=x-death-headers

# Declare queue1 with dead letter exchange
rabbitmqadmin declare queue name=queue1 arguments='{"x-dead-letter-exchange":"dlx"}'

# Declare queue2 with TTL and dead letter exchange  
rabbitmqadmin declare queue name=queue2 arguments='{"x-message-ttl":1000,"x-dead-letter-exchange":"dlx"}'

# Declare the alarming queue
rabbitmqadmin declare queue name=alarming_queue

# Bind queue2 to dlx for messages that rejected from queue1
rabbitmqadmin declare binding source=dlx destination=queue2 destination_type=queue \
  arguments='{"x-match":"all-with-x","x-death[queue1][rejected]-count":1}'

# Bind alarming_queue to dlx for messages that expired from queue2 and rejected from queue1
rabbitmqadmin declare binding source=dlx destination=alarming_queue destination_type=queue \
  arguments='{"x-match":"all-with-x","x-death[queue1][rejected]-count":1,"x-death[queue2][expired]-count":1}'

# Publish a test message to queue1
rabbitmqadmin publish exchange="" routing_key=queue1 payload="test message"
```

### What Happens:

1. Message is published to `queue1`
2. After the message is rejected, will be dead-lettered to the `dlx` exchange
3. The exchange maps the death info: `x-death[queue1][rejected]-count = 1`
4. Message routes to `queue2` (matches the first binding)
5. After a second message expired from `queue2` 
6. Now the exchange has the message with headers: `x-death[queue1][rejected]-count = 1` AND `x-death[queue2][expired]-count = 1`
7. Message routed to `alarming_queue` (matches the second binding requiring both conditions)

## Matching Modes

The exchange supports all standard headers exchange matching modes:

- **`all`**: All headers (excluding x-prefixed) must match
- **`any`**: Any header (excluding x-prefixed) must match
- **`all-with-x`**: All headers (including x-death mapped headers) must match
- **`any-with-x`**: Any header (including x-death mapped headers) must match

For x-death routing capabilities that this exchange provides, you'll need to use `all-with-x` or `any-with-x` modes.

## License

This project is licensed under the Mozilla Public License 2.0 - see the LICENSE file for details.
