####################################
## variables
###################################
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}
# not so secret to be used when loading key to ec2.
variable "notSoSecret_key_path" {}
variable "key_name_notSoSecret" {}
variable "region" {
  default = "eu-west-1"
}
## S3 bucket
variable "bucket_name" {
  default = "hydro-dam-saftey"
}
variable "input_folder" {
  default = "raw"
}
variable "output_folder" {
  default = "preprocessed"
}
## VPC ##
variable "network_address_space" {
  default = "10.1.0.0/16"
}
variable "public_subnet_address_space" {
  default = "10.1.0.0/24"
}
variable "private_subnet_address_space" {
  default = "10.1.1.0/24"
}
variable "endpoint_service_name_s3" {
  default = "com.amazonaws.eu-west-1.s3"
}
## ec2 ##
variable "instance_type_tika_server" {
  default = "t2.micro"
}
variable "instance_type_public_server" {
  default = "t2.micro"
}
variable "tika_port" {
  default = 9998
}
## IAM ##
variable "AWSLambdaVPCAccessExecutionRole_arn" {
  default = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
