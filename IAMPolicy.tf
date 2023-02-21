
################                  Lambda Function IAM Roles                    #################
################             Provides Access between lambda and S3             #################
################            Provides Access for API Gateway to lambda          #################



 resource "aws_iam_role" "iamLambdaRole" {
  name = "iamLambdaRoleInterview"

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

 resource "aws_iam_policy" "iamLambdaPolicy" {
  name        = "iamLambdaPolicyInterview"
  description = "This is a policy for API Gateway interview questions POC"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "s3:Get*",
                "s3:List*"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
  })
} 


resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = "${aws_iam_role.iamLambdaRole.name}"
  policy_arn = "${aws_iam_policy.iamLambdaPolicy.arn}"
}
  


resource "aws_lambda_permission" "lambdaPermissions" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.S3DataRetrieverLambda.function_name}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.apiDataSourceRetrieval.execution_arn}/*/*/*"
}

################ API Gateway (Restricts access to web app only for api gateway... had my IP for testing as well)        #################
################                  Adds restriction for API gateway to be reachable by ec2 instance                      #################
################ This is good security for data store to only be reachable by our front end app through the API gateway #################

resource "aws_api_gateway_rest_api_policy" "iamGateway" {
  rest_api_id = aws_api_gateway_rest_api.apiDataSourceRetrieval.id


  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "execute-api:Invoke",
      "Resource": "*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": [ "${aws_instance.myWebApp.public_ip}/32", "2603:8081:8c00:c8f9:389b:4b51:6473:c470", "68.203.146.23" ]
        }
      }
    },
    {
        "Effect": "Allow",
        "Principal": "*",
        "Action": "execute-api:Invoke",
        "Resource": "*"
    }
  ]
}
EOF
}

################     Potential enhancement. Build a role to explicitly deny s3 bucket access for EC2        #################
################                         Not implemented due to limited time                                #################
################                Current state give enough for proof POC(Proof of concept)                    #################