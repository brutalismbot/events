###########
#   IAM   #
###########

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "AssumeEvents"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "access" {
  statement {
    sid       = "StatesStartExecution"
    actions   = ["states:StartExecution"]
    resources = [var.state_machine_arn]
  }
}

resource "aws_iam_role" "role" {
  assume_role_policy = data.aws_iam_policy_document.trust.json
  description        = var.description
  name               = "brutalismbot-events-${var.identifier}-${random_string.suffix.id}"

  inline_policy {
    name   = "access"
    policy = data.aws_iam_policy_document.access.json
  }
}

resource "random_string" "suffix" {
  length  = 12
  lower   = false
  special = false
}

####################
#   EVENTIBRIDGE   #
####################

resource "aws_cloudwatch_event_rule" "rule" {
  description         = var.description
  event_bus_name      = "default"
  is_enabled          = var.is_enabled
  name                = "brutalismbot-${var.identifier}"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "target" {
  arn            = var.state_machine_arn
  event_bus_name = aws_cloudwatch_event_rule.rule.event_bus_name
  input          = jsonencode(var.input)
  role_arn       = aws_iam_role.role.arn
  rule           = aws_cloudwatch_event_rule.rule.name
  target_id      = "state-machine"
}
