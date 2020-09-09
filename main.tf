## Jag inleder med at ordna ett bucket som i sin tur triggar en lambda.
## Förslagsvis så startar vi med att skapa en tom bucket men med rätt mapp-struktur
## Vi kopierar sen de filer som ska behandlas dit från "anann bucket"

#################################
## providers
#################################
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region = var.region
}
#################################
## data sources
#################################
data "archive_file" "parseDoc_zip" {
    type          = "zip"
    source_file   = "handler.py"
    output_path   = "lambda_function.zip"
}
data "archive_file" "parseIm_zip" {
    type          = "zip"
    source_file   = "handler2.py"
    output_path   = "lambda_function2.zip"
}
data "aws_availability_zones" "available" {}

## Getting the right linux ami - this is a cut and paste ##
data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

################################
## locals
################################
locals {
  s3_bucket_name = "${var.bucket_name}-${random_integer.rand.result}"
  common_tags = {Name = "Hydro-dam-documents"}
}
################################
## resources
################################

#####################
## Random Integer ##
####################
resource "random_integer" "rand" {
  max = 1000000
  min = 1000
}
##############
## Buckets ##
#############
resource "aws_s3_bucket" "main_bucket" {
  bucket        = local.s3_bucket_name
  acl           = "private"
  force_destroy = true
}

## Prefix in the Bucket ##
resource "aws_s3_bucket_object" "input_prefix" {
  bucket = aws_s3_bucket.main_bucket.id
  key = "${var.input_folder}/"
}

resource "aws_s3_bucket_object" "output_prefix" {
  bucket = aws_s3_bucket.main_bucket.id
  key = "${var.output_folder}/"
  acl = "private"
}

## Block public access ##
resource "aws_s3_bucket_public_access_block" "block_public_access_main_bucket" {
  bucket = aws_s3_bucket.main_bucket.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}


## Notification for the bucket ##
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification
resource "aws_s3_bucket_notification" "bucket_trigger" {
  bucket = aws_s3_bucket.main_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.bucket_notification_sqs_raw.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = aws_s3_bucket_object.input_prefix.key
  }
  queue {
    events = ["s3:ObjectCreated:*"]
    queue_arn = aws_sqs_queue.bucket_notification_sqs_preprocessed.arn
    filter_prefix = aws_s3_bucket_object.output_prefix.key
  }
}

###############
## SQS Queue ##
###############
# https://xebia.com/blog/event-handling-in-aws-using-terraform/

resource "aws_sqs_queue" "bucket_notification_sqs_raw" {
  name = "s3-event-notification-queue-raw"
  policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[
{
        "Effect": "Allow",
        "Principal": {"AWS":"*"},
        "Action": "sqs:SendMessage",
        "Resource": "arn:aws:sqs:*:*:s3-event-notification-queue-raw",
        "Condition":{
            "ArnLike":{"aws:SourceArn":"${aws_s3_bucket.main_bucket.arn}"}
        }
    }
]
}
POLICY
  redrive_policy = jsonencode(
{
  "deadLetterTargetArn":aws_sqs_queue.bucket_notification_dlq_raw.arn
  "maxReceiveCount":5

})
  visibility_timeout_seconds = 300
}
## dead letter queue ##
resource "aws_sqs_queue" "bucket_notification_dlq_raw" {
  name = "bucket_notification_dlq_raw"
}
# this following sqs will be used to trigger loading of the neo4j-database.
# There is still some development to follow before we have that in place.
resource "aws_sqs_queue" "bucket_notification_sqs_preprocessed" {
  name = "s3-event-notification-queue-preprocessed"
  policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[
{
        "Effect": "Allow",
        "Principal": {"AWS":"*"},
        "Action": "sqs:SendMessage",
        "Resource": "arn:aws:sqs:*:*:s3-event-notification-queue-preprocessed",
        "Condition":{
            "ArnLike":{"aws:SourceArn":"${aws_s3_bucket.main_bucket.arn}"}
        }
    }
]
}
POLICY
  redrive_policy = jsonencode(
{
  "deadLetterTargetArn":aws_sqs_queue.bucket_notification_dlq_preprocessed.arn
  "maxReceiveCount":5

})
  visibility_timeout_seconds = 300
}
## dead letter queue ##
resource "aws_sqs_queue" "bucket_notification_dlq_preprocessed" {
  name = "bucket_notification_dlq_preprocessed"
}
#############
## lambda ##
resource "aws_lambda_function" "lambda_parse_doc" {
  filename = data.archive_file.parseDoc_zip.output_path
  function_name = "Parse_Documents"
  handler = "handler.lambda_handler"
  role = aws_iam_role.iam_for_lambda_parse_content.arn
  runtime = "python3.8"
  source_code_hash = filebase64sha256(data.archive_file.parseDoc_zip.output_path)
  vpc_config {
    security_group_ids = [aws_security_group.tika_server_sg.id]
    subnet_ids = [aws_subnet.private_subnet.id]
  }
}
resource "aws_lambda_function" "lambda_parse_image" {
  filename = data.archive_file.parseIm_zip.output_path
  function_name = "Parse_image"
  handler = "handler.lambda_handler"
  role = aws_iam_role.iam_for_lambda_parse_content.arn
  runtime = "python3.8"
  source_code_hash = filebase64sha256(data.archive_file.parseIm_zip.output_path)
}
## lambda event source mapping ##
resource "aws_lambda_event_source_mapping" "lambda_ES_SQS_Bucket" {
  batch_size = 1
  event_source_arn = aws_sqs_queue.bucket_notification_sqs_raw.arn
  function_name = aws_lambda_function.lambda_parse_doc.function_name
  enabled = true
}
## Här ska ännu tillkomma den andra lambda funktionen.

#####################
## EC2 #############
###################
resource "aws_iam_instance_profile" "ec2_instance_profile_s3_read_only" {
  name = "ec2_instance_profile_s3_read_only"
  role = aws_iam_role.ec2_role.name
}
resource "aws_instance" "tika_server" {
  ami = data.aws_ami.aws-linux.id
  instance_type = var.instance_type_tika_server
  security_groups = [aws_security_group.tika_server_sg.id]
  subnet_id = aws_subnet.private_subnet.id
  key_name = var.key_name_notSoSecret
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile_s3_read_only.name
}
resource "aws_instance" "public_server" {
  ami = data.aws_ami.aws-linux.id
  instance_type = var.instance_type_public_server
  security_groups = [aws_security_group.public_server_sg.id]
  subnet_id = aws_subnet.public_subnet.id
  key_name = var.key_name
}
##################################
## VPC ##########################
################################
## VPC
resource "aws_vpc" "vpc_for_tika_server" {
  cidr_block = var.network_address_space
}
## Subnets
resource "aws_subnet" "public_subnet" {
  cidr_block = var.public_subnet_address_space
  vpc_id = aws_vpc.vpc_for_tika_server.id
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = "true"
}
resource "aws_subnet" "private_subnet" {
  cidr_block = var.private_subnet_address_space
  vpc_id = aws_vpc.vpc_for_tika_server.id
  availability_zone = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = "false"
}
## IGW
resource "aws_internet_gateway" "igw"{
  vpc_id = aws_vpc.vpc_for_tika_server.id
}
## NAT Gateway
resource "aws_eip" "eip" {
  vpc = "true"
  depends_on = [aws_internet_gateway.igw]
}
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip.id
  subnet_id = aws_subnet.public_subnet.id
  depends_on = [aws_internet_gateway.igw, aws_eip.eip]
}
## VPC endpoint S3
resource "aws_vpc_endpoint" "s3_ep" {
  service_name = var.endpoint_service_name_s3
  vpc_id = aws_vpc.vpc_for_tika_server.id
}
## routes
resource "aws_route_table" "public_table"{
  vpc_id = aws_vpc.vpc_for_tika_server.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table" "private_table" {
  vpc_id = aws_vpc.vpc_for_tika_server.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}
resource "aws_vpc_endpoint_route_table_association" "s3_endpoint_route_private" {
  route_table_id = aws_route_table.private_table.id
  vpc_endpoint_id = aws_vpc_endpoint.s3_ep.id
}
## association subnets and routes
resource "aws_route_table_association" "public_rtb"{
  route_table_id = aws_route_table.public_table.id
  subnet_id = aws_subnet.public_subnet.id
}
resource "aws_route_table_association" "private_rtb"{
  route_table_id = aws_route_table.private_table.id
  subnet_id = aws_subnet.private_subnet.id
}
## ACL
# Nothing done here, maybe later

## Security groups
resource "aws_security_group" "tika_server_sg" {
  name = "tika_server_sg"
  vpc_id = aws_vpc.vpc_for_tika_server.id
  ingress {
    from_port = var.tika_port
    protocol = "tcp"
    to_port = var.tika_port
    #cidr_blocks = [var.private_subnet_address_space]
    self = true
  }
  # borde öppna upp för ssh från det publika subnetet
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_address_space]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "public_server_sg" {
  name = "public_server_sg"
  vpc_id = aws_vpc.vpc_for_tika_server.id
  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}
