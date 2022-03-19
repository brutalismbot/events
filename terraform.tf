#################
#   TERRAFORM   #
#################

terraform {
  required_version = "~> 1.0"

  cloud {
    organization = "brutalismbot"

    workspaces { name = "events" }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

###########
#   AWS   #
###########

provider "aws" {
  region = "us-west-2"
  assume_role { role_arn = var.AWS_ROLE_ARN }
  default_tags { tags = local.tags }
}

#################
#   VARIABLES   #
#################

variable "AWS_ROLE_ARN" {}

##############
#   LOCALS   #
##############

locals {
  is_enabled = {
    reddit = {
      dequeue = true
      post    = true
      reject  = true
      verify  = true
    }

    slack = {
      beta_app_home_opened = true
      beta_enable_disable  = true
      install              = true
      post                 = true
      post_channel         = true
      uninstall            = true
    }

    twitter = {
      post = true
    }
  }

  tags = {
    App  = "Brutalismbot"
    Name = "Brutalismbot"
    Repo = "https://github.com/brutalismbot/events"
  }
}

#################
#   EVENT BUS   #
#################

resource "aws_cloudwatch_event_bus" "bus" {
  name = "brutalismbot"
}

#########################
#   REDDIT :: DEQUEUE   #
#########################

data "aws_iam_role" "events" {
  name = "brutalismbot-events"
}

data "aws_sfn_state_machine" "reddit_dequeue" {
  name = "brutalismbot-reddit-dequeue"
}

resource "aws_cloudwatch_event_rule" "reddit_dequeue" {
  description         = "Dequeue next post from /r/brutalism"
  event_bus_name      = "default"
  is_enabled          = local.is_enabled.reddit.dequeue
  name                = "brutalismbot-reddit-dequeue"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "reddit_dequeue" {
  arn       = data.aws_sfn_state_machine.reddit_dequeue.id
  input     = jsonencode({})
  role_arn  = data.aws_iam_role.events.arn
  rule      = aws_cloudwatch_event_rule.reddit_dequeue.name
  target_id = "state-machine"
}

######################
#   REDDIT :: POST   #
######################

data "aws_sfn_state_machine" "reddit_post" {
  name = "brutalismbot-reddit-post"
}

module "reddit_post" {
  source = "./eventbridge"

  description       = "Handle new posts from Reddit"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "reddit-post"
  is_enabled        = local.is_enabled.reddit.post
  state_machine_arn = data.aws_sfn_state_machine.reddit_post.arn

  pattern = {
    source      = ["reddit"]
    detail-type = ["post"]
  }
}

########################
#   REDDIT :: REJECT   #
########################

data "aws_sfn_state_machine" "reddit_reject" {
  name = "brutalismbot-reddit-reject"
}

module "reddit_reject" {
  source = "./eventbridge"

  description       = "Reject posts from Reddit"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "reddit-post-reject"
  is_enabled        = local.is_enabled.reddit.reject
  state_machine_arn = data.aws_sfn_state_machine.reddit_reject.arn

  pattern = {
    source      = ["slack/beta"]
    detail-type = ["callback", "POST /callbacks"]
    detail = {
      type       = ["block_actions"]
      action_ids = ["reject"]
    }
  }
}

#########################
#   REDDITY :: VERIFY   #
#########################

data "aws_sfn_state_machine" "reddit_verify" {
  name = "brutalismbot-reddit-verify"
}

module "reddit_verify" {
  source = "./eventbridge"

  description       = "Verify new posts from Reddit"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "reddit-post-verify"
  is_enabled        = local.is_enabled.reddit.verify
  state_machine_arn = data.aws_sfn_state_machine.reddit_verify.arn

  pattern = {
    source      = ["reddit"]
    detail-type = ["post/slack/verify"]
  }
}

#####################################
#   SLACK :: BETA APP HOME OPENED   #
#####################################

data "aws_sfn_state_machine" "slack_beta_app_home_opened" {
  name = "brutalismbot-slack-beta-app-home-opened"
}

module "slack_beta_app_home_opened" {
  source = "./eventbridge"

  description       = "Handle Slack beta app home opened events"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "slack-beta-app-home-opened"
  is_enabled        = local.is_enabled.slack.beta_app_home_opened
  state_machine_arn = data.aws_sfn_state_machine.slack_beta_app_home_opened.arn

  pattern = {
    source      = ["slack/beta"]
    detail-type = ["event", "POST /events"]
    detail      = { event = { type = ["app_home_opened"] } }
  }
}

####################################
#   SLACK :: BETA ENABLE/DISABLE   #
####################################

data "aws_sfn_state_machine" "slack_beta_enable_disable" {
  name = "brutalismbot-slack-beta-enable-disable"
}

module "slack_beta_enable_disable" {
  source = "./eventbridge"

  description       = "Handle Slack beta enable/disable callbacks"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "slack-beta-enable-disable"
  is_enabled        = local.is_enabled.slack.beta_enable_disable
  state_machine_arn = data.aws_sfn_state_machine.slack_beta_enable_disable.arn

  pattern = {
    source      = ["slack/beta"]
    detail-type = ["callback", "POST /callbacks"]
    detail      = { view = { callback_id = ["enable_disable"] } }
  }
}

########################
#   SLACK :: INSTALL   #
########################

data "aws_sfn_state_machine" "slack_install" {
  name = "brutalismbot-slack-install"
}

module "slack_install" {
  source = "./eventbridge"

  description       = "Handle Slack install events"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "slack-install"
  is_enabled        = local.is_enabled.slack.install
  state_machine_arn = data.aws_sfn_state_machine.slack_install.arn

  pattern = {
    source      = ["slack", "slack/beta"]
    detail-type = ["oauth", "GET /oauth/v2"]
  }
}

#####################
#   SLACK :: POST   #
#####################

data "aws_sfn_state_machine" "slack_post" {
  name = "brutalismbot-slack-post"
}

module "slack_post" {
  source = "./eventbridge"

  description       = "Handle new posts from Reddit for Slack"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "slack-post"
  is_enabled        = local.is_enabled.slack.post
  state_machine_arn = data.aws_sfn_state_machine.slack_post.arn

  pattern = {
    source      = ["reddit"]
    detail-type = ["post/slack"]
  }
}

#############################
#   SLACK :: POST CHANNEL   #
#############################

data "aws_sfn_state_machine" "slack_post_channel" {
  name = "brutalismbot-slack-post-channel"
}

module "slack_post_channel" {
  source = "./eventbridge"

  description       = "Handle new posts from Reddit for a Slack workspace"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "slack-post-channel"
  is_enabled        = local.is_enabled.slack.post_channel
  state_machine_arn = data.aws_sfn_state_machine.slack_post_channel.arn

  pattern = {
    source      = ["reddit"]
    detail-type = ["post/slack/channel"]
  }
}

##########################
#   SLACK :: UNINSTALL   #
##########################

data "aws_sfn_state_machine" "slack_uninstall" {
  name = "brutalismbot-slack-uninstall"
}

module "slack_uninstall" {
  source = "./eventbridge"

  description       = "Handle Slack uninstall events"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "slack-uninstall"
  is_enabled        = local.is_enabled.slack.uninstall
  state_machine_arn = data.aws_sfn_state_machine.slack_uninstall.arn

  pattern = {
    source      = ["slack", "slack/beta"]
    detail-type = ["event", "POST /events"]
    detail      = { event = { type = ["app_uninstalled"] } }
  }
}

#######################
#   TWITTER :: POST   #
#######################

data "aws_sfn_state_machine" "twitter_post" {
  name = "brutalismbot-twitter-post"
}

module "twitter_post" {
  source = "./eventbridge"

  description       = "Handle new posts from Reddit for Twitter"
  event_bus_name    = aws_cloudwatch_event_bus.bus.name
  identifier        = "twitter-post"
  is_enabled        = local.is_enabled.twitter.post
  state_machine_arn = data.aws_sfn_state_machine.twitter_post.arn

  pattern = {
    source      = ["reddit"]
    detail-type = ["post/twitter"]
  }
}

###############
#   OUTPUTS   #
###############

output "event_bus" {
  value = {
    arn  = aws_cloudwatch_event_bus.bus.arn
    name = aws_cloudwatch_event_bus.bus.name
  }
}

output "roles" {
  value = {
    reddit_dequeue     = null
    reddit_post        = module.reddit_post.role.name
    reddit_reject      = module.reddit_reject.role.name
    reddit_verify      = module.reddit_verify.role.name
    slack_post         = module.slack_post.role.name
    slack_post_channel = module.slack_post_channel.role.name
    slack_uninstall    = module.slack_uninstall.role.name
    twitter_post       = module.twitter_post.role.name
  }
}

output "rules" {
  value = {
    reddit_dequeue     = null
    reddit_post        = module.reddit_post.rule.name
    reddit_reject      = module.reddit_reject.rule.name
    reddit_verify      = module.reddit_verify.rule.name
    slack_post         = module.slack_post.rule.name
    slack_post_channel = module.slack_post_channel.rule.name
    slack_uninstall    = module.slack_uninstall.rule.name
    twitter_post       = module.twitter_post.rule.name
  }
}