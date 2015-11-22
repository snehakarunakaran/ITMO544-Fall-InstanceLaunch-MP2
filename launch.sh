#!/bin/bash
./cleanup.sh



#declare a variable

declare -a instanceARR

#Subnet for RDS

SUBNETGROUPNAME='rdssubnet'
SUBNETID1='subnet-5e540975'
SUBNETID2='subnet-2e250a77'
aws rds create-db-subnet-group --db-subnet-group-name $SUBNETGROUPNAME --subnet-ids $SUBNETID1 $SUBNETID2 --db-subnet-group-description createdoncomdpmt


#Create DB Instance

DBINSTANCEIDENTIFIER='db1'
DBUSERNAME='testconnection1'
DBPASSWORD='testconnection1'
DBNAME='Project1'

aws rds create-db-instance --db-name $DBNAME --publicly-accessible --db-instance-identifier $DBINSTANCEIDENTIFIER --db-instance-class db.t2.micro --engine MySQL --allocated-storage 5 --master-username $DBUSERNAME --master-user-password $DBPASSWORD --db-subnet-group-name subnetgrp1test

aws rds wait db-instance-available --db-instance-identifier $DBINSTANCEIDENTIFIER

#create Read replica

aws rds create-db-instance-read-replica --db-instance-identifier mp1SKread-replica --source-db-instance-identifier $DBINSTANCEIDENTIFIER

mapfile -t instanceARR < <(aws ec2 run-instances --image-id $1 --count $2 --instance-type $3 --key-name $6 --security-group-id $4 --subnet-id $5 --associate-public-ip-address --iam-instance-profile Name=$7 --user-data file://../ITMO544-Fall-EnvSetup-MP2/install-env.sh --output table | grep InstanceId | sed "s/|//g" | tr -d ' ' | sed "s/InstanceId//g")

#aws ec2 run-instances --image-id ami-d05e75b8 --count 2 --instance-type t2.micro --key-name ITMO544-Fall2015-VirtualBox --security-group-id sg-18b4bc7f --subnet-id subnet-5e540975 --associate-public-ip-address --user-data file://../ITMO544-Fall-EnvSetup-MP2/install-env.sh --debug
echo ${instanceARR[@]}

aws ec2 wait instance-running --instance-ids ${instanceARR[@]}
echo "instances are running"

ELBNAME='itmo544SKelb'

ELBURL=(`aws elb create-load-balancer --load-balancer-name $ELBNAME --listeners Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80 --security-groups $4 --subnets $5 --output=text`);
echo $ELBURL
echo -e "\n Finished launching ELB and sleeping 25 seconds"
for i in {0..25}; do echo -ne '.'; sleep 1;done
echo "\n"

#Instance with load balancer

aws elb register-instances-with-load-balancer --load-balancer-name $ELBNAME --instances ${instanceARR[@]}

#Health Check Configuration

aws elb configure-health-check --load-balancer-name $ELBNAME --health-check Target=HTTP:80/index.html,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

echo -e "\n waiting for an extra 3 minutes before opening elb in browser"
for i in {0..180}; do echo -ne '.'; sleep 1;done
echo "\n"

# SNS
# SNS For ImageUpload

SNSIMAGETOPICNAME=ImageTopicSK

SNSIMAGEARN=(`aws sns create-topic --name $SNSIMAGETOPICNAME`)
aws sns set-topic-attributes --topic-arn $SNSIMAGEARN --attribute-name DisplayName --attribute-value $SNSIMAGETOPICNAME 


# SNS For Cloud MetricAlarm

SNSCLOUDMETRICNAME=CloudMetricTopicSK

SNSCLOUDMETRICSARN=(`aws sns create-topic --name $SNSCLOUDMETRICNAME`)
aws sns set-topic-attributes --topic-arn $SNSCLOUDMETRICSARN --attribute-name DisplayName --attribute-value $SNSCLOUDMETRICNAME

#Subcribe

EMAILID=sneha.karunakaran@gmail.com

aws sns subscribe --topic-arn $SNSCLOUDMETRICSARN --protocol email --notification-endpoint $EMAILID


#Launch Config

LAUNCHCONFIG='itmo544launchconfig'

aws autoscaling create-launch-configuration --launch-configuration-name $LAUNCHCONFIG --image-id $1 --key-name $6 --security-groups $4 --instance-type $3 --user-data file://../ITMO544-Fall-EnvSetup-MP2/install-env.sh --iam-instance-profile $7

#Autoscaling group

AUTOSCALINGNAME='itmo544autoscalinggroupname'

aws autoscaling create-auto-scaling-group --auto-scaling-group-name $AUTOSCALINGNAME --launch-configuration-name $LAUNCHCONFIG --load-balancer-names $ELBNAME  --health-check-type ELB --min-size 1 --max-size 3 --desired-capacity 2 --default-cooldown 600 --health-check-grace-period 120 --vpc-zone-identifier $5 

#AutoScaling Policy-Increase

SCALINGINCREASE=(`aws autoscaling put-scaling-policy --auto-scaling-group-name $AUTOSCALINGNAME --policy-name scalingpolicyincrease --scaling-adjustment 3 --adjustment-type ChangeInCapacity`)

#AutoScaling Policy-Decrease

SCALINGDECREASE=(`aws autoscaling put-scaling-policy --auto-scaling-group-name $AUTOSCALINGNAME --policy-name scalingpolicydecrease --scaling-adjustment -3 --adjustment-type ChangeInCapacity`)

#Cloud Watch Metric

aws cloudwatch put-metric-alarm --alarm-name AddCapacity --alarm-description "Alarm when CPU exceeds 30 percent" --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 60 --threshold 30 --comparison-operator GreaterThanOrEqualToThreshold --evaluation-periods 1 --unit Percent --dimensions "Name=AutoScalingGroupName,Value=$AUTOSCALINGNAME" --alarm-actions $SCALINGINCREASE $SNSCLOUDMETRICSARN

aws cloudwatch put-metric-alarm --alarm-name ReduceCapacity --alarm-description "Alarm when CPU falls below 10 percent" --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 60 --threshold 10 --comparison-operator LessThanOrEqualToThreshold --evaluation-periods 1 --unit Percent --dimensions "Name=AutoScalingGroupName,Value=$AUTOSCALINGNAME" --alarm-actions $SCALINGDECREASE $SNSCLOUDMETRICSARN







