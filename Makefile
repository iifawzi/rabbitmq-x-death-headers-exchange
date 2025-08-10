PROJECT = rabbitmq_x_death_headers_exchange
PROJECT_DESCRIPTION = RabbitMQ exchange that behaves like the standard Headers exchange, but with the added capability to route messages based on the x-death header.

RABBITMQ_VERSION = v3.13.2
current_rmq_ref = $(RABBITMQ_VERSION)

define PROJECT_APP_EXTRA_KEYS
	{broker_version_requirements, ["3.13.0"]}
endef

dep_amqp_client                = git_rmq-subfolder rabbitmq-erlang-client $(RABBITMQ_VERSION)
dep_rabbit_common              = git_rmq-subfolder rabbitmq-common $(RABBITMQ_VERSION)
dep_rabbit                     = git_rmq-subfolder rabbitmq-server $(RABBITMQ_VERSION)
dep_rabbitmq_ct_client_helpers = git_rmq-subfolder rabbitmq-ct-client-helpers $(RABBITMQ_VERSION)
dep_rabbitmq_ct_helpers        = git_rmq-subfolder rabbitmq-ct-helpers $(RABBITMQ_VERSION)

DEPS = rabbit_common rabbit
TEST_DEPS = ct_helper rabbitmq_ct_helpers rabbitmq_ct_client_helpers amqp_client
dep_ct_helper = git https://github.com/extend/ct_helper.git master

DEP_EARLY_PLUGINS = rabbit_common/mk/rabbitmq-early-plugin.mk
DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include ../../rabbitmq-components.mk
include ../../erlang.mk
