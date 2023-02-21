# This does not due to much, but it shows a proof of concept for a lambda function api retrieveing data from a datasurce. This obviously could be modified for RDS data bases or etc... with a bit more logic added.


import json
import boto3


def lambda_handler(event, context):
    
	#Retrieve bucket information
    s3_resource = boto3.resource('s3')
    bucket = s3_resource.Bucket('mtafsir')

    output = []

    for object in bucket.objects.all():
        output.append(object.key)

	#Output Results 
    responseObject = {}
    responseObject['statusCode'] = 200
    responseObject['headers'] = {}
    responseObject['headers']['Content-Type'] = 'application/json'
    responseObject['body'] = json.dumps(output)
    
    return responseObject