-module(rabbit_exchange_type_x_death_headers_SUITE).
-author("iifawzie@gmail.com").

-compile(export_all).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-define(WFM_SLEEP, 256).
-define(WFM_DEFAULT_NUMS, 5_000 div ?WFM_SLEEP). %% ~30s

all() ->
  [
    {group, non_parallel_tests}
  ].

groups() ->
  [
    {non_parallel_tests, [], [
      testing_message_rejected,
      testing_x_death_headers_extraction,
      testing_alarming_topology
    ]}
  ].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

init_per_suite(Config) ->
  rabbit_ct_helpers:log_environment(),
  Config1 = rabbit_ct_helpers:set_config(Config, [
    {rmq_nodename_suffix, ?MODULE}
  ]),
  rabbit_ct_helpers:run_setup_steps(Config1,
    rabbit_ct_broker_helpers:setup_steps() ++
    rabbit_ct_client_helpers:setup_steps()).

end_per_suite(Config) ->
  rabbit_ct_helpers:run_teardown_steps(Config,
    rabbit_ct_client_helpers:teardown_steps() ++
    rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
  Config.

end_per_group(_, Config) ->
  Config.

init_per_testcase(Testcase, Config) ->
  rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
  rabbit_ct_helpers:testcase_finished(Config, Testcase).


%% -------------------------------------------------------------------
%% Testcases.
%% -------------------------------------------------------------------


testing_message_rejected(Config) ->
  {_, Chan} = rabbit_ct_client_helpers:open_connection_and_channel(Config, 0),
  DLXExchange = <<"dlx">>,
  QueueName = <<"queue">>,
  FinalDeadLetterQueue = <<"failed_queue">>,

  declare_exchange(Chan, DLXExchange, <<"x-death-headers">>),
  declare_queue_with_dlx(Chan, QueueName, DLXExchange),
  declare_queue(Chan, FinalDeadLetterQueue),
  bind_queue_with_arguments(Chan, FinalDeadLetterQueue, DLXExchange, [
    {<<"x-match">>, longstr, <<"all-with-x">>},
    {<<"x-death[queue][rejected]-count">>, long, 1}
  ]),
  bind_queue_with_arguments(Chan, QueueName, DLXExchange, [
    {<<"x-match">>, longstr, <<"any">>}
  ]),

  Payload = <<"p">>,
  publish_message_with_headers(Chan, QueueName, Payload, []),

  wait_for_messages(Config, [[QueueName, <<"1">>, <<"1">>, <<"0">>]]),
  [DTag] = consume(Chan, QueueName, [Payload]),
  amqp_channel:cast(Chan, #'basic.reject'{delivery_tag = DTag, requeue = false}),
  wait_for_messages(Config, [[QueueName, <<"0">>, <<"0">>, <<"0">>]]),
  wait_for_messages(Config, [[FinalDeadLetterQueue, <<"1">>, <<"1">>, <<"0">>]]),

  cleanup_resources(Chan, [DLXExchange], [QueueName, FinalDeadLetterQueue]),
  passed.

testing_x_death_headers_extraction(Config) ->
  {_, Chan} = rabbit_ct_client_helpers:open_connection_and_channel(Config, 0),
  DLXExchange = <<"dlx">>,
  QueueName = <<"queue">>,
  FinalDeadLetterQueue = <<"failed_queue">>,

  declare_exchange(Chan, DLXExchange, <<"x-death-headers">>),
  declare_queue_with_dlx(Chan, QueueName, DLXExchange),
  declare_queue(Chan, FinalDeadLetterQueue),
  
  bind_queue_with_arguments(Chan, FinalDeadLetterQueue, DLXExchange, [
    {<<"x-match">>, longstr, <<"all-with-x">>},
    {<<"x-death[queue][rejected]-count">>, long, 1}
  ]),

  Payload = <<"test_payload">>,
  publish_message_with_headers(Chan, QueueName, Payload, []),

  wait_for_messages(Config, [[QueueName, <<"1">>, <<"1">>, <<"0">>]]),
  [DTag] = consume(Chan, QueueName, [Payload]),
  amqp_channel:cast(Chan, #'basic.reject'{delivery_tag = DTag, requeue = false}),
  
  wait_for_messages(Config, [[QueueName, <<"0">>, <<"0">>, <<"0">>]]),
  wait_for_messages(Config, [[FinalDeadLetterQueue, <<"1">>, <<"1">>, <<"0">>]]),
  
  [_DTTag] = consume(Chan, FinalDeadLetterQueue, [Payload]),

  cleanup_resources(Chan, [DLXExchange], [QueueName, FinalDeadLetterQueue]),
  passed.

testing_alarming_topology(Config) ->
  {_, Chan} = rabbit_ct_client_helpers:open_connection_and_channel(Config, 0),
  MainExchange = <<"main">>,
  DLXExchange = <<"dlx">>,
  Queue1 = <<"queue1">>,
  Queue2 = <<"queue2">>,
  AlarmingQueue = <<"alarming_queue">>,

  declare_exchange(Chan, MainExchange, <<"direct">>),
  declare_exchange(Chan, DLXExchange, <<"x-death-headers">>),
  
  declare_queue_with_dlx(Chan, Queue1, DLXExchange),
  declare_queue_with_dlx(Chan, Queue2, DLXExchange),
  declare_queue(Chan, AlarmingQueue),
  
  bind_queue_with_routing_key(Chan, Queue1, MainExchange, <<"start">>),
  
  bind_queue_with_arguments(Chan, Queue2, DLXExchange, [
    {<<"x-match">>, longstr, <<"all-with-x">>},
    {<<"x-death[queue1][rejected]-count">>, long, 1}
  ]),
  
  bind_queue_with_arguments(Chan, AlarmingQueue, DLXExchange, [
    {<<"x-match">>, longstr, <<"all-with-x">>},
    {<<"x-death[queue1][rejected]-count">>, long, 1},
    {<<"x-death[queue2][rejected]-count">>, long, 1}
  ]),

  Payload = <<"multi_death_payload">>,
  
  amqp_channel:call(Chan, #'basic.publish'{exchange = MainExchange, routing_key = <<"start">>},
    #amqp_msg{payload = Payload}),

  wait_for_messages(Config, [[Queue1, <<"1">>, <<"1">>, <<"0">>]]),
  [DTag1] = consume(Chan, Queue1, [Payload]),
  amqp_channel:cast(Chan, #'basic.reject'{delivery_tag = DTag1, requeue = false}),
  
  wait_for_messages(Config, [[Queue1, <<"0">>, <<"0">>, <<"0">>]]),
  wait_for_messages(Config, [[Queue2, <<"1">>, <<"1">>, <<"0">>]]),
  
  [DTag2] = consume(Chan, Queue2, [Payload]),
  amqp_channel:cast(Chan, #'basic.reject'{delivery_tag = DTag2, requeue = false}),
  
  wait_for_messages(Config, [[Queue2, <<"1">>, <<"1">>, <<"0">>]]),
  wait_for_messages(Config, [[AlarmingQueue, <<"1">>, <<"1">>, <<"0">>]]),

  cleanup_resources(Chan, [MainExchange, DLXExchange], [Queue1, Queue2, AlarmingQueue]),
  passed.

%% -------------------------------------------------------------------
%% Helpers.
%% -------------------------------------------------------------------


cleanup_resources(Chan, ExchangeNames, Queues) ->
  [amqp_channel:call(Chan, #'exchange.delete'{exchange = ExchangeName}) || ExchangeName <- ExchangeNames],
  [amqp_channel:call(Chan, #'queue.delete'{queue = Q}) || Q <- Queues],
  rabbit_ct_client_helpers:close_channel(Chan).


declare_exchange(Chan, ExchangeName, ExchangeType) ->
  #'exchange.declare_ok'{} = amqp_channel:call(Chan, #'exchange.declare'{
    exchange = ExchangeName,
    type = ExchangeType
  }).

declare_queue(Chan, QueueName) ->
  #'queue.declare_ok'{} = amqp_channel:call(Chan, #'queue.declare'{
    queue = QueueName
  }).

declare_queue_with_dlx(Chan, QueueName, DLXExchange) ->
  #'queue.declare_ok'{} = amqp_channel:call(Chan, #'queue.declare'{
    queue = QueueName,
    arguments = [{<<"x-dead-letter-exchange">>, longstr, DLXExchange}]
  }).

declare_queue_with_dlx_and_ttl(Chan, QueueName, DLXExchange, TTL) ->
  #'queue.declare_ok'{} = amqp_channel:call(Chan, #'queue.declare'{
    queue = QueueName,
    arguments = [
      {<<"x-message-ttl">>, long, TTL},
      {<<"x-dead-letter-exchange">>, longstr, DLXExchange}
    ]
  }).

bind_queue_with_routing_key(Chan, QueueName, ExchangeName, RoutingKey) ->
  #'queue.bind_ok'{} = amqp_channel:call(Chan, #'queue.bind'{
    queue = QueueName,
    exchange = ExchangeName,
    routing_key = RoutingKey
  }).

bind_queue_with_arguments(Chan, QueueName, ExchangeName, Arguments) ->
  #'queue.bind_ok'{} = amqp_channel:call(Chan, #'queue.bind'{
    queue = QueueName,
    exchange = ExchangeName,
    arguments = Arguments
  }).

publish_message_with_headers(Chan, RoutingKey, Payload, Headers) ->
  amqp_channel:call(Chan, #'basic.publish'{routing_key = RoutingKey},
    #amqp_msg{props = #'P_basic'{headers = Headers}, payload = Payload}).


consume(Chan, QName, Payloads) ->
  [begin
     {#'basic.get_ok'{delivery_tag = DTag}, #amqp_msg{payload = Payload}} =
       amqp_channel:call(Chan, #'basic.get'{queue = QName}),
     DTag
   end || Payload <- Payloads].


%%-------------------------------------------------------
%% Utils copied from the folks @ rabbit/queue_utils 
wait_for_messages(Config, Stats) ->
  wait_for_messages(Config, lists:sort(Stats), ?WFM_DEFAULT_NUMS).

wait_for_messages(Config, Stats, 0) ->
  ?assertEqual(Stats,
               lists:sort(
                 filter_queues(Stats,
                               rabbit_ct_broker_helpers:rabbitmqctl_list(
                                 Config, 0, ["list_queues", "name", "messages", "messages_ready",
                                             "messages_unacknowledged"]))));
wait_for_messages(Config, Stats, N) ->
  case lists:sort(
         filter_queues(Stats,
                       rabbit_ct_broker_helpers:rabbitmqctl_list(
                         Config, 0, ["list_queues", "name", "messages", "messages_ready",
                                     "messages_unacknowledged"]))) of
      Stats0 when Stats0 == Stats ->
          ok;
      _ ->
          timer:sleep(?WFM_SLEEP),
          wait_for_messages(Config, Stats, N - 1)
  end.
filter_queues(Expected, Got) ->
  Keys = [hd(E) || E <- Expected],
  lists:filter(fun(G) ->
                       lists:member(hd(G), Keys)
               end, Got).