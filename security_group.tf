resource "aws_security_group" "runner" {
  description = "Gitlab runner instances"
  name_prefix = "gitlab-runner-"
  vpc_id      = data.aws_subnet.current.vpc_id
}

resource "aws_security_group_rule" "ingress_ssh" {
  count = var.asg.ssh_access.source_cidr != "" ? 1 : 0

  cidr_blocks       = [var.asg.ssh_access.source_cidr]
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.runner.id
  to_port           = 22
  type              = "ingress"
}

resource "aws_security_group_rule" "egress_all" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = "-1"
  security_group_id = aws_security_group.runner.id
  to_port           = 0
  type              = "egress"
}
