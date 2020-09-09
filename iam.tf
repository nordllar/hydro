## denna klipp och klistrad..
## tillsvidare behåller jag denna som en egen.
resource "aws_iam_role" "iam_for_lambda_parse_content" {
  name = "iam_for_lambda_parse_documents"
  ## I would like to have the need for the following policy explained.
  # could I put in the policy below already here?
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_policy" "policy_parse_content" {
  name        = "policy_parse_content"
  description = "This is a cut-and-paste from the lambda iam-consul of the first dev deployment"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "sqs:DeleteMessage",
                "s3:PutObject",
                "s3:GetObject",
                "s3:PutBucketNotification",
                "lambda:InvokeFunction",
                "sqs:ReceiveMessage",
                "sqs:GetQueueAttributes",
                "lambda:InvokeAsync",
                "s3:GetBucketNotification"
            ],
            "Resource": [
                "${aws_sqs_queue.bucket_notification_sqs_raw.arn}",
                "${aws_sqs_queue.bucket_notification_dlq_raw.arn}",
                "${aws_s3_bucket.main_bucket.arn}",
                "${aws_s3_bucket.main_bucket.arn}/*",
                "${aws_lambda_function.lambda_parse_doc.arn}",
                "${aws_lambda_function.lambda_parse_image.arn}"
            ]
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "textract:DetectDocumentText",
                "rekognition:DetectLabels"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "iam_parse_document" {
  policy_arn = aws_iam_policy.policy_parse_content.arn
  role = aws_iam_role.iam_for_lambda_parse_content.name
}
resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole"{
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role = aws_iam_role.iam_for_lambda_parse_content.name
}
############################################
resource "aws_iam_role" "ec2_role" {
  name = "Tika_server_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "s3_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role = aws_iam_role.ec2_role.name
}
resource "aws_iam_role_policy_attachment" "sqs_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"
  role = aws_iam_role.ec2_role.name
}