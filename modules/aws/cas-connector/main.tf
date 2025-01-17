/*
 * © Copyright 2022 HP Development Company, L.P.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

locals {
  prefix = var.prefix != "" ? "${var.prefix}-" : ""

  provisioning_script = "cas-connector-provisioning.sh"
  cas_mgr_script      = "get-connector-token.py"

  instance_info_list = flatten(
    [ for i in range(length(var.zone_list)):
      [ for j in range(var.instance_count_list[i]):
        {
          zone   = var.zone_list[i],
          subnet = var.subnet_list[i],
        }
      ]
    ]
  )
  tls_key_filename  = var.tls_key  == "" ? "" : basename(var.tls_key)
  tls_cert_filename = var.tls_cert == "" ? "" : basename(var.tls_cert)
}

resource "aws_s3_bucket_object" "get-connector-token-script" {
  count = length(local.instance_info_list) == 0 ? 0 : 1

  bucket = var.bucket_name
  key    = local.cas_mgr_script
  source = "${path.module}/${local.cas_mgr_script}"
}

resource "aws_s3_bucket_object" "tls-key" {
  count = length(local.instance_info_list) == 0 ? 0 : var.tls_key == "" ? 0 : 1

  bucket = var.bucket_name
  key    = local.tls_key_filename
  source = var.tls_key
}

resource "aws_s3_bucket_object" "tls-cert" {
  count = length(local.instance_info_list) == 0 ? 0 : var.tls_cert == "" ? 0 : 1

  bucket = var.bucket_name
  key    = local.tls_cert_filename
  source = var.tls_cert
}

resource "aws_s3_bucket_object" "cas-connector-provisioning-script" {
  count = length(local.instance_info_list) == 0 ? 0 : 1

  key     = local.provisioning_script
  bucket  = var.bucket_name
  content = templatefile(
    "${path.module}/${local.provisioning_script}.tmpl",
    {
      ad_service_account_password       = var.ad_service_account_password,
      ad_service_account_username       = var.ad_service_account_username,
      aws_region                        = var.aws_region,
      bucket_name                       = var.bucket_name,
      cas_connector_extra_install_flags = var.cas_connector_extra_install_flags,
      cas_mgr_deployment_sa_file        = var.cas_mgr_deployment_sa_file,
      cas_mgr_insecure                  = var.cas_mgr_insecure ? "true" : "",
      cas_mgr_script                    = local.cas_mgr_script,
      cas_mgr_url                       = var.cas_mgr_url,
      cloudwatch_enable                 = var.cloudwatch_enable,
      cloudwatch_setup_script           = var.cloudwatch_setup_script,
      computers_dn                      = var.computers_dn,
      customer_master_key_id            = var.customer_master_key_id,
      domain_controller_ip              = var.domain_controller_ip,
      domain_name                       = var.domain_name,
      ldaps_cert_filename               = var.ldaps_cert_filename,
      lls_ip                            = var.lls_ip,
      tls_cert                          = local.tls_cert_filename,
      tls_key                           = local.tls_key_filename,
      teradici_download_token           = var.teradici_download_token,
      users_dn                          = var.users_dn,
    }
  )
}

data "template_file" "user-data" {
  template = file("${path.module}/user-data.sh.tmpl")

  vars = {
    bucket_name         = var.bucket_name,
    provisioning_script = local.provisioning_script,
  }
}

# Need to do this to look up AMI ID, which is different for each region
data "aws_ami" "ami" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name]
  }
}

data "aws_iam_policy_document" "instance-assume-role-policy-doc" {
  statement {
    actions = [ "sts:AssumeRole" ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cas-connector-role" {
  count = length(local.instance_info_list) == 0 ? 0 : 1

  name               = "${local.prefix}cas-connector_role"
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy-doc.json
}

data "aws_kms_key" "encryption-key" {
  count = var.customer_master_key_id == "" ? 0 : 1

  key_id = var.customer_master_key_id
}

data "aws_iam_policy_document" "cas-connector-policy-doc" {
  statement {
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
    effect    = "Allow"
  }
  
  statement {
    actions   = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${var.bucket_name}/${local.provisioning_script}",
      "arn:aws:s3:::${var.bucket_name}/${local.cas_mgr_script}",
      "arn:aws:s3:::${var.bucket_name}/${var.cas_mgr_deployment_sa_file}",
      "arn:aws:s3:::${var.bucket_name}/${var.cloudwatch_setup_script}",
      "arn:aws:s3:::${var.bucket_name}/${var.ldaps_cert_filename}",
    ]
    effect    = "Allow"
  }

  # add minimal permissions to allow users to connect to instances using Session Manager
  dynamic statement {
    for_each = var.aws_ssm_enable ? [1] : []
    content {
      actions   = ["ssm:UpdateInstanceInformation",
                  "ssmmessages:CreateControlChannel",
                  "ssmmessages:CreateDataChannel",
                  "ssmmessages:OpenControlChannel",
                  "ssmmessages:OpenDataChannel"]
      resources = ["*"]
      effect    = "Allow"
    }
  }

  dynamic statement {
    for_each = aws_s3_bucket_object.tls-key
    iterator = i
    content {
      actions   = ["s3:GetObject"]
      resources = ["arn:aws:s3:::${var.bucket_name}/${local.tls_key_filename}"]
      effect    = "Allow"
    }
  }

  dynamic statement {
    for_each = aws_s3_bucket_object.tls-cert
    iterator = i
    content {
      actions   = ["s3:GetObject"]
      resources = ["arn:aws:s3:::${var.bucket_name}/${local.tls_cert_filename}"]
      effect    = "Allow"
    }
  }

  statement {
    actions   = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
    effect    = "Allow"
  }

  dynamic statement {
    for_each = data.aws_kms_key.encryption-key
    iterator = i
    content {
      actions   = ["kms:Decrypt"]
      resources = [i.value.arn]
      effect    = "Allow"
    }
  }
}

resource "aws_iam_role_policy" "cas-connector-role-policy" {
  count = length(local.instance_info_list) == 0 ? 0 : 1

  name = "${local.prefix}cas_connector_role_policy"
  role = aws_iam_role.cas-connector-role[0].id
  policy = data.aws_iam_policy_document.cas-connector-policy-doc.json
}

resource "aws_iam_instance_profile" "cas-connector-instance-profile" {
  count = length(local.instance_info_list) == 0 ? 0 : 1

  name = "${local.prefix}cas_connector_instance_profile"
  role = aws_iam_role.cas-connector-role[0].name
}

resource "aws_cloudwatch_log_group" "instance-log-group" {
  count = var.cloudwatch_enable ? length(local.instance_info_list) : 0

  name = "${local.prefix}${var.host_name}-${count.index}"
}

resource "time_sleep" "delay_destroy_log_group" {
  depends_on = [aws_cloudwatch_log_group.instance-log-group]

  destroy_duration = "5s"
}

resource "aws_instance" "cas-connector" {
  count = length(local.instance_info_list)

  depends_on = [
    aws_s3_bucket_object.tls-key,
    aws_s3_bucket_object.tls-cert,
    aws_s3_bucket_object.get-connector-token-script,
    aws_s3_bucket_object.cas-connector-provisioning-script,
    # wait 5 seconds before deleting the log group to account for delays in 
    # Cloudwatch receiving the last messages before an EC2 instance is shut down
    time_sleep.delay_destroy_log_group
  ]

  availability_zone = local.instance_info_list[count.index].zone
  subnet_id         = local.instance_info_list[count.index].subnet

  ami           = data.aws_ami.ami.id
  instance_type = var.instance_type

  root_block_device {
    volume_type = "gp2"
    volume_size = var.disk_size_gb
    tags = merge(
      {
        Name = "vol-${var.prefix}-sda1-connector"
      },
      {Environment = "${var.prefix}"} # var.common_tags
    )

  }

  vpc_security_group_ids = var.security_group_ids

  key_name = var.keypair_name

  iam_instance_profile = aws_iam_instance_profile.cas-connector-instance-profile[0].name

  user_data = data.template_file.user-data.rendered

  lifecycle {
    ignore_changes = [
      # Ignore changes to user_data, since we only use it when
      # the node initializes and we do not want subsequent
      # enhancements to user_data to cause the node to be replaced
      user_data,
      # Since the DC runs on a standard AWS Windows Server, it's possible that
      # AWS will eventually age out the AMI used to initially deploy the DC,
      # so we ignore AMI changes here
      ami,
      # if the ec2 instance_type is changed from the AWS Console, it will
      # cause terraform to think the ebs_optimized field has changed and
      # the instance will be replaced, so we ignore that field here
      ebs_optimized,
    ]
  }

  tags = {
    Name = "${local.prefix}${var.host_name}-${count.index}"
  }
}
