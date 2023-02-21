#########               The idea behind how this infrastructure should work       ###########
#########                                 ...                                     ###########
#########                       EC2 (Front End Web App)                           ###########
#########                                  _                                      ###########
#########                                 | |                                     ###########
#########                                .   .                                    ###########
#########                                 . .                                     ###########
#########                                  .                                      ###########
#########                     API Gateway (API Endpoint)                          ###########
#########                                  _                                      ###########
#########                                 | |                                     ###########
#########                                .   .                                    ###########
#########                                 . .                                     ###########
#########                                  .                                      ###########
#########              Lambda (Serverless unction to Retrieve Data)               ###########
#########                                  _                                      ###########
#########                                 | |                                     ###########
#########                                .   .                                    ###########
#########                                 . .                                     ###########
#########                                  .                                      ###########
#########                        S3 Bucket (Data Source)                          ###########



provider "aws" {
  region = "us-east-1"
  access_key = "Acces Key"
  secret_key = "Secret Key"
}

provider "archive" {}


########## EC2 Instance Configuration (Front End Web App) ###########


# VPC Definition
resource "aws_vpc" "webAppVpc" {
  cidr_block = "10.0.0.0/16"
}

#Internet Gateway Definition
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.webAppVpc.id
  tags = {
    Name = "WebAppIG"
  }
}

#Custom route tables for internet gateway
resource "aws_route_table" "igRouteTable" {
  vpc_id = aws_vpc.webAppVpc.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }


  tags = {
    Name = "webAppRouteTables"
  }
}

# Create a public subnet
resource "aws_subnet" "webAppPublicSubnet" {
  vpc_id     = aws_vpc.webAppVpc.id
  cidr_block = "10.0.1.0/24"

  availability_zone = "us-east-1a"

  tags = {
    Name = "Public Subnet"
  }
}

# Associate Subnet With Resource
resource "aws_route_table_association" "WebAppRoute" {
  subnet_id      = aws_subnet.webAppPublicSubnet.id
  route_table_id = aws_route_table.igRouteTable.id

}

#AWS Security Group
resource "aws_security_group" "publicSecurityGroup" { 
  name        = "allowWebTraffic"
  description = "Allow Web and ssh trafic"
  vpc_id      = aws_vpc.webAppVpc.id


  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
   ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

 ingress {
    description      = "ssh"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["68.203.146.23/32"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    # -1 here indicate any protocol
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allowTrafficToWebApp"
  }
}


# Create a network interface with an available IP in the subnet
resource "aws_network_interface" "privateIP" {
  subnet_id       = aws_subnet.webAppPublicSubnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.publicSecurityGroup.id]
  depends_on = [aws_internet_gateway.gw]


}

#Assign an elastic IP to the network interface
resource "aws_eip" "one" {
  vpc                       = true
  network_interface = aws_network_interface.privateIP.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]

  tags = {

      Name = "networkInterfaceSubnet1"
  }
}

# EC2 instance
resource "aws_instance" "myWebApp" {
  ami           = "ami-09d56f8956ab235b3"
  instance_type = "t2.nano"
  availability_zone = "us-east-1a"


  #PPk key being used
  key_name = "WebAppKey"

   network_interface {

       device_index = 0
       network_interface_id = aws_network_interface.privateIP.id

   }

   user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo Web server is live > /var/www/html/index.html'
                EOF

  tags = {
    Name = "WebAppFrontEndApp"
  }

}



########## API Gateway ###########

resource "aws_api_gateway_rest_api" "apiDataSourceRetrieval" {
  name = "interviewAPI"
 
}


resource "aws_api_gateway_resource" "apiDataSourceResource" {
  rest_api_id = aws_api_gateway_rest_api.apiDataSourceRetrieval.id
  parent_id   = aws_api_gateway_rest_api.apiDataSourceRetrieval.root_resource_id
  path_part   = "dataSource"
}

resource "aws_api_gateway_method" "APIDataSourceGet" {
  rest_api_id   = aws_api_gateway_rest_api.apiDataSourceRetrieval.id
  resource_id   = aws_api_gateway_resource.apiDataSourceResource.id
  http_method   = "GET"
  authorization = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.apiDataSourceRetrieval.id
  resource_id             = aws_api_gateway_resource.apiDataSourceResource.id
  http_method             = aws_api_gateway_method.APIDataSourceGet.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.S3DataRetrieverLambda.invoke_arn
}

resource "aws_api_gateway_deployment" "apiInterviewDeployment" {
  rest_api_id = aws_api_gateway_rest_api.apiDataSourceRetrieval.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.apiDataSourceRetrieval.body))
  }

  depends_on = [aws_api_gateway_integration.integration]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "apiInterviewStage" {
  deployment_id = aws_api_gateway_deployment.apiInterviewDeployment.id
  rest_api_id   = aws_api_gateway_rest_api.apiDataSourceRetrieval.id
  stage_name    = "apiInterviewStage"
}




#########                       Print testable API Gateway endpoints              ###########
output "invokeArn"   {value= aws_api_gateway_deployment.apiInterviewDeployment.invoke_url}
output "stageName"   {value= aws_api_gateway_stage.apiInterviewStage.stage_name}
output "pathPart"    {value= aws_api_gateway_resource.apiDataSourceResource.path_part} 
output "urlPath"     {value = "${aws_api_gateway_deployment.apiInterviewDeployment.invoke_url}${aws_api_gateway_stage.apiInterviewStage.stage_name}/${aws_api_gateway_resource.apiDataSourceResource.path_part}"}




########## Lambda (API Functionality Triggered By API Gateway to reach Datastore) ###########

data "archive_file" "lambdaFile" {
  type        = "zip"
  source_file = "lambdaScripts/lambda.py"
  output_path = "lambdaScripts/lambda.zip"
}

 resource "aws_lambda_function" "S3DataRetrieverLambda" {
  # If the file is not in the current working directory you will need to include a 
  # path.module in the filename.
  filename      = "${data.archive_file.lambdaFile.output_path}"
  function_name = "test"
  role          = aws_iam_role.iamLambdaRole.arn
  handler       = "lambda.lambda_handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("${data.archive_file.lambdaFile.output_path}")

  runtime = "python3.8"

  environment {
    variables = {
      foo = "bar"
    }
  }
} 


########## S3 Bucket(Data Store) ###########

resource "aws_s3_bucket" "DataStore" {
  bucket = "mtafsir"

  tags = {
    Name        = "DataStore"
  }
}