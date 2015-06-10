module COMMON
  def compare_snapshot(current_data,original_snapshot)
    if original_snapshot.nil?
      create_snapshot([],empty_new=1)
      original_snapshot_data=[]
    else
      File.open(original_snapshot,"r") do |fd|
        original_snapshot_data=fd.readlines
      end
    end
    original_snapshot_data.map! do |i| i.chomp! end
    create_snapshot(current_data) if (original_snapshot_data.sort != current_data.sort) || original_snapshot_data.size == 0
    increase_wave= current_data - original_snapshot_data
    decrease_wave=original_snapshot_data - current_data
    puts "increase number: #{increase_wave.size}"
    puts "decrease number: #{decrease_wave.size}"
    if increase_wave.size > 0 && decrease_wave.size == 0
      return [1,increase_wave]
    elsif increase_wave.size == 0 && decrease_wave.size > 0
      return [2,decrease_wave]
    elsif increase_wave.size > 0 && decrease_wave.size > 0
      return [3,increase_wave,decrease_wave]
    else
      return [0]
    end
  end
  
  def judgment(current_data,original_snapshot)
    wave=compare_snapshot(current_data,original_snapshot)
    puts "compare return code: #{wave.inspect}"
    if wave.size == 1
      puts "nothing change"
    else
    puts "sendmail"
    generate_email(wave)
    end
  end

  def send_email(subject,summary,data,recipients=ALL)
    to_recipients=String.new
    recipients.map do |i|
      to_recipients << "<"+i+">,"
    end
    to_recipients.chop!
     body=<<-EOM
<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
</head>
<body bgcolor="#FFFFFF" text="#000000">
#{summary}<br>
#{data}
</body>
</html>
EOM
  
    content=<<-EOM
From: robot@example.com
To: #{to_recipients}
Subject: #{subject}
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: 7bit

#{body}
    EOM
  
    smtp = Net::SMTP.new 'smtp.163.com', 25
    smtp.start('163.com', 'user1@163.com', 'xxxxxxxxxx', :login)
    smtp.send_message(content, 'user1@163.com', recipients)
    smtp.finish
  end
end

class EC2
  include COMMON
  TAG=self.to_s
  def get_all_ec2_info
    region = ["us-west-1","us-west-2","us-east-1","ap-northeast-1","ap-southeast-1"]
    current_data=Array.new
    region.each do |region|
      string =`aws ec2 describe-instances --region=#{region}`.gsub(/=>/,':')
      json_string= JSON.parse(string)
      current_data<<get_region_ec2_info(json_string,region).split("\n")
    end
    current_data.flatten
  end
  
  def get_region_ec2_info(json_string , region)
    info=String.new
    json_string["Reservations"].each do |l1|
    l1["Instances"].each do |l2|
      array=Array.new
      l2["Tags"].each do |l3|
         array[0]=l3["Value"] if l3["Key"] == "Name" && l2["PublicIpAddress"] 
         array[0]=l3["Value"] if l3["Key"] == "Name" 
         array[1]=l3["Value"] if l3["Key"] == "project" 
         array[2]=l3["Value"] if l3["Key"] == "environment" 
         array[3]=l3["Value"] if l3["Key"] == "user_group" 
      end
      array[0]="name_null" if array[0] == nil
      array[1]="project_null" if array[1] == nil
      array[2]="env_null" if array[2] == nil
      next if array[3] != nil && USER_GROUP.include?(array[3])
      if l2["PublicIpAddress"] == nil
        array[3]="pubip_null" if l2["PublicIpAddress"] == nil
      else
        array[3]=l2["PublicIpAddress"]
      end
      info<<"#{l2["InstanceId"]};#{l2["State"]["Name"]};#{array[0]};#{array[1]};#{array[2]};#{array[3]};#{l2["InstanceType"]};#{l2["Placement"]["AvailabilityZone"]};#{l2["LaunchTime"]}\n" 
      end
    end
    info
  end
  
  def generate_email(wave)
    $log.info("#{TAG} sendmail")
  # 2 or 3 arguments
  # arguments format: status increase_info decrease_info
    action=wave[0]
    code=Proc.new do |message|
      table_data='<table cellpadding="2" cellspacing="2" border="1" width="100%"><tbody><tr><td valign="top">instance-id<br></td><td valign="top">status<br></td><td valign="top">hostname<br></td><td valign="top">project<br></td><td valign="top">environment<br></td><td valign="top">public_ip<br></td><td valign="top">type<br></td><td valign="top">region<br></td><td valign="top">launch_time<br></td>'
      message.each do |record|
        table_data<<"<tr>"
        record.split(";").each do |item|
          table_data<<"<td valgn='top'>#{item}<br></td>"
        end
        table_data<<"</tr>"
      end
      table_data<<"</tbody></table>"
    end
    if action == 1
      subject="#{wave[1].size} EC2 #{ wave[1].size == 1 ? "instance" : "instances"} added in AWS"
      summary="There were #{wave[1].size} EC2 #{ wave[1].size == 1 ? "instance" : "instances"} added in your AWS account."
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      data=code.call(wave[1])
    elsif action == 2
      subject="#{wave[1].size} EC2 #{ wave[1].size == 1 ? "instance" : "instances"} removed in AWS"
      summary="There were #{wave[1].size} EC2 #{ wave[1].size == 1 ? "instance" : "instances"} removed in your AWS account."
      $log.info("#{TAG} decrease number: #{wave[1].size} ; #{wave[1]}")
      data=code.call(wave[1])
    elsif action == 3
      subject="#{wave[1].size} New EC2 #{ wave[1].size == 1 ? "instance" : "instances"} status changed and #{wave[2].size} Original EC2 #{ wave[2].size == 1 ? "instance" : "instances"} status generated in AWS"
      summary="There were #{wave[1].size} new EC2 #{ wave[1].size == 1 ? "instance" : "instances"} status changed in your AWS account."
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      $log.info("#{TAG} decrease number: #{wave[2].size} ; #{wave[2]}")
      data=code.call(wave[1])+"<br>There were #{wave[2].size} old EC2 #{ wave[2].size == 1 ? "instance" : "instances"} status changed in your AWS account<br>"+code.call(wave[2])
    end
    send_email(subject,summary,data)
  end
  
  
  def create_snapshot(current_data,empty_new=0)
    bindir=Pathname.new(File.expand_path(File.dirname(__FILE__)))
    tmpdir=bindir+"../tmp"
    puts "tmpdir: #{tmpdir}"
    if empty_new == 0
      File.open("#{tmpdir}/ec2_snapshot_#{Time.now.to_i}.csv","w") do |fd|
        current_data.each do |item|
          fd.puts item
        end  
      end
    else
      puts "#{TAG} create empty snapshot"
      $log.info("#{TAG} create empty snapshot")
      File.open("#{tmpdir}/ec2_snapshot_#{Time.now.to_i}.csv","w") 
    end
  end
  
  def fetch_snapshot
    Dir[File.expand_path(File.dirname(__FILE__))+'/../tmp/ec2_snapshot_*.csv'].sort.last
  end
end

class RDS
  include COMMON
  TAG=self.to_s
  def get_all_rds_info
      region = REGION
      current_data=Array.new
      region.each do |region|
        string =`aws rds describe-db-instances --region=#{region}`.gsub(/=>/,':')
        json_string= JSON.parse(string)
  #      current_data<<get_region_rds_info(json_string,region).split("\n")
        current_data<<get_region_rds_info(json_string,region).split("\n")
      end
      current_data.flatten
  end
  def get_region_rds_info(json_string , region)
    info=String.new
    json_string["DBInstances"].each do |l1|
       info << "#{l1["Endpoint"]["Address"]};#{l1["DBInstanceClass"]};#{l1["Engine"]};#{l1["EngineVersion"]};#{l1["MultiAZ"]};#{l1["StorageType"]};#{l1["AllocatedStorage"]};#{l1["PubliclyAccessible"]};#{l1["AvailabilityZone"]};#{l1["InstanceCreateTime"]}\n" 
    end
    info
  end
  def generate_email(wave)
    $log.info("#{TAG} sendmail")
  # 2 or 3 arguments
  # arguments format: status increase_info decrease_info
    action=wave[0]
    code=Proc.new do |message|
      table_data='<table cellpadding="2" cellspacing="2" border="1" width="100%"><tbody>
                     <tr><td valign="top">endpoint<br></td>
                     <td valign="top">instance_type<br></td>
                     <td valign="top">engine<br></td>
                     <td valign="top">engine_version<br></td>
                     <td valign="top">multiAZ<br></td>
                     <td valign="top">storage_type<br></td>
                     <td valign="top">allocate_storage<br></td>
                     <td valign="top">public_accessible<br></td>
                     <td valign="top">availibity_zone<br></td>
                     <td valign="top">launch_time<br></td>'
      message.each do |record|
        table_data<<"<tr>"
        record.split(";").each do |item|
          table_data<<"<td valgn='top'>#{item}<br></td>"
        end
        table_data<<"</tr>"
      end
      table_data<<"</tbody></table>"
    end
    if action == 1
      subject="#{wave[1].size} RDS #{ wave[1].size == 1 ? "instance" : "instances"} added in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} RDS #{ wave[1].size == 1 ? "instance" : "instances"} added in your AWS account."
      data=code.call(wave[1])
    elsif action == 2
      subject="#{wave[1].size} RDS #{ wave[1].size == 1 ? "instance" : "instances"} removed in AWS"
      $log.info("#{TAG} decrease number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} RDS #{ wave[1].size == 1 ? "instance" : "instances"} removed in your AWS account."
      data=code.call(wave[1])
    elsif action == 3
      subject="#{wave[1].size} New RDS #{ wave[1].size == 1 ? "instance" : "instances"} status changed and #{wave[2].size} Original RDS #{wave[2].size == 1 ? "instance" : "instances"} status generated in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      $log.info("#{TAG} decrease number: #{wave[2].size} ; #{wave[2]}")
      summary="There were #{wave[1].size} new RDS #{ wave[1].size == 1 ? "instance" : "instances"} status changed in your AWS account."
      data=code.call(wave[1])+"<br>There were #{wave[2].size} old RDS #{ wave[2].size == 1 ? "instance" : "instances"} status changed in your AWS account<br>"+code.call(wave[2])
ld 
    end
   send_email(subject,summary,data)
  end
  def create_snapshot(current_data,empty_new=0)
    bindir=Pathname.new(File.expand_path(File.dirname(__FILE__)))
    tmpdir=bindir+"../tmp"
    puts "tmpdir: #{tmpdir}"
    if empty_new == 0
      File.open("#{tmpdir}/rds_snapshot_#{Time.now.to_i}.csv","w") do |fd|
        current_data.each do |item|
          fd.puts item
        end  
      end
    else
      puts "#{TAG} create empty snapshot"
      $log.info("#{TAG} create empty snapshot")
      File.open("#{tmpdir}/rds_snapshot_#{Time.now.to_i}.csv","w") 
    end
  end
  def fetch_snapshot
    Dir[File.expand_path(File.dirname(__FILE__))+'/../tmp/rds_snapshot_*.csv'].sort.last
  end
end

class S3
  include COMMON
  TAG=self.to_s
  def get_all_s3_info
    current_data=Array.new
    string =`aws s3api list-buckets`.gsub(/=>/,':')
    JSON.parse(string)["Buckets"].each do |item|
      current_data << "#{item["Name"]};#{get_bucket_location(item["Name"])};#{item["CreationDate"]}"
    end
    current_data.flatten
  end

  def get_bucket_location(bucket)
    region=JSON.parse(`aws s3api get-bucket-location --bucket #{bucket}`)["LocationConstraint"]
    region="standard" if region.nil?
    region
  end

  def generate_email(wave)
    $log.info("#{TAG} sendmail")
  # 2 or 3 arguments
  # arguments format: status increase_info decrease_info
    action=wave[0]
    code=Proc.new do |message|
      table_data='<table cellpadding="2" cellspacing="2" border="1" width="100%"><tbody>
                     <tr><td valign="top">bucket_name<br></td>
                     <td valign="top">location<br></td>
                     <td valign="top">create_date<br></td>'
      message.each do |record|
        table_data<<"<tr>"
        record.split(";").each do |item|
          table_data<<"<td valgn='top'>#{item}<br></td>"
        end
        table_data<<"</tr>"
      end
      table_data<<"</tbody></table>"
    end
    if action == 1
      subject="#{wave[1].size} S3 #{ wave[1].size == 1 ? "bucket" : "buckets" } added in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} S3 #{ wave[1].size == 1 ? "bucket" : "buckets" } added in your AWS account."
      data=code.call(wave[1])
    elsif action == 2
      subject="#{wave[1].size} S3 #{ wave[1].size == 1 ? "bucket" : "buckets" } removed in AWS"
      $log.info("#{TAG} decrease number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} S3 #{ wave[1].size == 1 ? "bucket" : "buckets" } removed in your AWS account."
      data=code.call(wave[1])
    elsif action == 3
      subject="#{wave[1].size} New S3 #{ wave[1].size == 1 ? "bucket" : "buckets" } status changed and #{wave[2].size} Original S3 #{ wave[2].size == 1 ? "bucket" : "buckets" } istatus generated in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      $log.info("#{TAG} decrease number: #{wave[2].size} ; #{wave[2]}")
      summary="There were #{wave[1].size} new S3 #{ wave[1].size == 1 ? "bucket" : "buckets" } status changed in your AWS account."
      data=code.call(wave[1])+"<br>There were #{wave[2].size} old S3 #{ wave[2].size == 1 ? "bucket" : "buckets" } status changed in your AWS account<br>"+code.call(wave[2])
    end
  send_email(subject,summary,data)
  end
  def create_snapshot(current_data,empty_new=0)
    bindir=Pathname.new(File.expand_path(File.dirname(__FILE__)))
    tmpdir=bindir+"../tmp"
    puts "tmpdir: #{tmpdir}"
    if empty_new == 0
      File.open("#{tmpdir}/s3_snapshot_#{Time.now.to_i}.csv","w") do |fd|
        current_data.each do |item|
          fd.puts item
        end  
      end
    else
      puts "create empty snapshot"
      $log.info("#{TAG} create empty snapshot")
      File.open("#{tmpdir}/s3_snapshot_#{Time.now.to_i}.csv","w") 
    end
  end
  def fetch_snapshot
    Dir[File.expand_path(File.dirname(__FILE__))+'/../tmp/s3_snapshot_*.csv'].sort.last
  end
end
class ROUTE53
  include COMMON
  TAG=self.to_s
  def get_route53_zone_info
    current_data=Array.new
    string =`aws route53 list-hosted-zones`.gsub(/=>/,':')
    JSON.parse(string)["HostedZones"].each do |item|
      current_data << "#{item["Name"]};#{item["Id"].sub!("/hostedzone/","")};#{item["ResourceRecordSetCount"]};#{item["Config"]["PrivateZone"]};#{item["Config"]["Comment"].nil? ? "null" : item["Config"]["Comment"]}"
    end
    current_data.flatten
  end

  def generate_email(wave)
    $log.info("#{TAG} sendmail")
  # 2 or 3 arguments
  # arguments format: status increase_info decrease_info
    action=wave[0]
    code=Proc.new do |message|
      table_data='<table cellpadding="2" cellspacing="2" border="1" width="100%"><tbody>
                     <tr><td valign="top">zone_name<br></td>
                     <td valign="top">zone_id<br></td>
                     <td valign="top">record_count<br></td>
                     <td valign="top">private_zone<br></td>
                     <td valign="top">description<br></td>'
      message.each do |record|
        table_data<<"<tr>"
        record.split(";").each do |item|
          table_data<<"<td valgn='top'>#{item}<br></td>"
        end
        table_data<<"</tr>"
      end
      table_data<<"</tbody></table>"
    end
    if action == 1
      subject="#{wave[1].size} ROUTE53 #{ wave[1].size == 1 ? "zone" : "zones" } added in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} ROUTE53 #{ wave[1].size == 1 ? "zone" : "zones" } added in your AWS account."
      data=code.call(wave[1])
    elsif action == 2
      subject="#{wave[1].size} ROUTE53 #{ wave[1].size == 1 ? "zone" : "zones" } removed in AWS"
      $log.info("#{TAG} decrease number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} ROUTE53 #{ wave[1].size == 1 ? "zone" : "zones" } removed in your AWS account."
      data=code.call(wave[1])
    elsif action == 3
      subject="#{wave[1].size} New ROUTE53 #{ wave[1].size == 1 ? "zone" : "zones" } status changed and #{wave[2].size} Original ROUTE53 #{ wave[2].size == 1 ? "zone" : "zones" } istatus generated in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      $log.info("#{TAG} decrease number: #{wave[2].size} ; #{wave[2]}")
      summary="There were #{wave[1].size} new ROUTE53 #{ wave[1].size == 1 ? "zone" : "zones" } status changed in your AWS account."
      data=code.call(wave[1])+"<br>There were #{wave[2].size} old ROUTE53 #{ wave[2].size == 1 ? "zone" : "zones" } status changed in your AWS account<br>"+code.call(wave[2])
    end
  send_email(subject,summary,data)
  end
  def create_snapshot(current_data,empty_new=0)
    bindir=Pathname.new(File.expand_path(File.dirname(__FILE__)))
    tmpdir=bindir+"../tmp"
    puts "tmpdir: #{tmpdir}"
    if empty_new == 0
      File.open("#{tmpdir}/route53_snapshot_#{Time.now.to_i}.csv","w") do |fd|
        current_data.each do |item|
          fd.puts item
        end  
      end
    else
      puts "create empty snapshot"
      $log.info("#{TAG} create empty snapshot")
      File.open("#{tmpdir}/route53_snapshot_#{Time.now.to_i}.csv","w") 
    end
  end
  def fetch_snapshot
    Dir[File.expand_path(File.dirname(__FILE__))+'/../tmp/route53_snapshot_*.csv'].sort.last
  end
end

class ELB
  include COMMON
  TAG=self.to_s
  def get_all_elb_info
    current_data=Array.new
    region=REGION
    region.each do |region|
      string=`aws elb describe-load-balancers --region=#{region}`
      current_data<<get_region_elb_info(JSON.parse(string),region).split("\n")
    end
    current_data.flatten
  end

  def get_region_elb_info(json_string,region)
      info=String.new
      json_string['LoadBalancerDescriptions'].each do |item|
        elb_listener=Array.new
        item['ListenerDescriptions'].each do |listener|
                elb_listener << "#{listener['Listener']['Protocol']} #{listener['Listener']['LoadBalancerPort']} #{listener['Listener']['InstanceProtocol']} #{listener['Listener']['InstancePort']}"
        end
        info << "#{item['DNSName'].gsub(/\.[a-z]{2,4}\-[a-z]{4,20}\-[0-9]{1,2}.elb.amazonaws.com/,'')};#{item['Instances'].size};#{elb_listener.join(" ")};#{item['AvailabilityZones'].join(" ")};#{item['CreatedTime']}\n"
      end
      info
  end

  def generate_email(wave)
    $log.info("#{TAG} sendmail")
  # 2 or 3 arguments
  # arguments format: status increase_info decrease_info
    action=wave[0]
    code=Proc.new do |message|
      table_data='<table cellpadding="2" cellspacing="2" border="1" width="100%"><tbody>
                     <tr><td valign="top">dns_name<br></td>
                     <td valign="top">backend_instance_count<br></td>
                     <td valign="top">elb_listen_protocol<br></td>
                     <td valign="top">elb_listen_port<br></td>
                     <td valign="top">backend_listen_protocol<br></td>
                     <td valign="top">backend_listen_port<br></td>
                     <td valign="top">availability_zone<br></td>
                     <td valign="top">create_time<br></td></tr>'
      message.each do |record|
        other_table_data=String.new
        table_data<<"<tr>"
        stage1=record.split(";")
        row_num=stage1[2].split.size/4 
        if row_num > 1
          stage1.each_with_index do |item,index|
            if index != 2
              table_data<<"<td rowspan=\"#{row_num}\"  valgn='top'>#{item}<br></td>"
            else
              elb_network_info=item.split
              elb_network_info.shift(4).each do |i|
                table_data<<"<td valgn='top'>#{i}<br></td>"
              end
            end
            if not elb_network_info.nil?
              while not elb_network_info.empty?
                other_table_data<<"<tr>"
                elb_network_info.shift(4).each do |i|
                  other_table_data<<"<td valgn='top'>#{i}<br></td>"
                end
                other_table_data<<"</tr>"
              end
            end
          end
        else
          stage1.each_with_index do |item,index|
            if index !=2
              table_data<<"<td valgn='top'>#{item}<br></td>"
            else
               item.split.each do |item|
                 table_data<<"<td valgn='top'>#{item}<br></td>"
               end
            end
          end
        end
        table_data<<"</tr>"
        table_data << other_table_data
      end
      table_data<<"</tbody></table>"
    end

    if action == 1
      subject="#{wave[1].size} ELB #{ wave[1].size == 1 ? "instance" : "instances" } added (suffix: elb.amazonaws.com) in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} ELB #{ wave[1].size == 1 ? "instance" : "instances" } added in your AWS account."
      data=code.call(wave[1])
    elsif action == 2
      subject="#{wave[1].size} ELB #{ wave[1].size == 1 ? "instance" : "instances" } removed (suffix: elb.amazonaws.com) in AWS"
      $log.info("#{TAG} decrease number: #{wave[1].size} ; #{wave[1]}")
      summary="There were #{wave[1].size} ELB #{ wave[1].size == 1 ? "instance" : "instances" } removed in your AWS account."
      data=code.call(wave[1])
    elsif action == 3
      subject="#{wave[1].size} New ELB #{ wave[1].size == 1 ? "instance" : "instances" } status changed and #{wave[2].size} Original ELB #{ wave[2].size == 1 ? "instance" : "instances" } istatus generated (suffix: elb.amazonaws.com) in AWS"
      $log.info("#{TAG} increase number: #{wave[1].size} ; #{wave[1]}")
      $log.info("#{TAG} decrease number: #{wave[2].size} ; #{wave[2]}")
      summary="There were #{wave[1].size} new ELB #{ wave[1].size == 1 ? "instance" : "instances" } status changed in your AWS account."
      data=code.call(wave[1])+"<br>There were #{wave[2].size} old ELB #{ wave[2].size == 1 ? "instance" : "instances" } status changed in your AWS account<br>"+code.call(wave[2])
    end
  send_email(subject,summary,data)
  end

  def create_snapshot(current_data,empty_new=0)
    bindir=Pathname.new(File.expand_path(File.dirname(__FILE__)))
    tmpdir=bindir+"../tmp"
    puts "tmpdir: #{tmpdir}"
    if empty_new == 0
      File.open("#{tmpdir}/elb_snapshot_#{Time.now.to_i}.csv","w") do |fd|
        current_data.each do |item|
          fd.puts item
        end  
      end
    else
      puts "create empty snapshot"
      $log.info("#{TAG} create empty snapshot")
      File.open("#{tmpdir}/elb_snapshot_#{Time.now.to_i}.csv","w") 
    end
  end
  def fetch_snapshot
    Dir[File.expand_path(File.dirname(__FILE__))+'/../tmp/elb_snapshot_*.csv'].sort.last
  end
end
